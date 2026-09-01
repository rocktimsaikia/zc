const std = @import("std");

const api_url = "https://api.openai.com/v1/chat/completions";
const model = "gpt-5.4-mini";
const max_diff_bytes = 10 * 1024 * 1024;

const system_prompt =
    \\Write a git commit message for the staged diff.
    \\
    \\Follow the Conventional Commits 1.0.0 specification exactly.
    \\
    \\Structure:
    \\  <type>[optional scope]: <description>
    \\
    \\  [optional body]
    \\
    \\  [optional footer(s)]
    \\
    \\Specification rules:
    \\- A type is REQUIRED: a noun, then an OPTIONAL scope, an OPTIONAL !, then a
    \\  terminal colon and one space.
    \\- feat MUST be used when the commit adds a feature.
    \\- fix MUST be used when the commit is a bug fix.
    \\- Other types MAY be used: docs, style, refactor, perf, test, build, ci,
    \\  chore, revert.
    \\- A scope is OPTIONAL: a noun in parentheses naming a section of the
    \\  codebase, e.g. fix(parser):
    \\- The description MUST immediately follow the colon and space.
    \\- A body is OPTIONAL and MUST begin one blank line after the description.
    \\  It is free-form and MAY span multiple paragraphs.
    \\- Footers are OPTIONAL and begin one blank line after the body. Each footer
    \\  is a token, then ': ' or ' #', then a value. Tokens MUST use - instead of
    \\  spaces, e.g. Reviewed-by. BREAKING CHANGE is the one exception.
    \\- Breaking changes MUST be shown either as ! immediately before the colon in
    \\  the prefix, or as a footer 'BREAKING CHANGE: <description>'. The text
    \\  BREAKING CHANGE MUST be uppercase.
    \\
    \\Decide first whether the diff changes or removes existing public API or
    \\behaviour: a changed signature, a renamed or deleted export, a new thrown
    \\error, a different return value, a changed default. If it does, that is a
    \\breaking change and you MUST mark it with ! before the colon, and add a
    \\BREAKING CHANGE: footer saying what callers have to do differently.
    \\
    \\House style, on top of the spec:
    \\- Description is lowercase, imperative mood, no trailing period.
    \\- Keep the description under 72 characters.
    \\- Add a body only when the reason for the change is not obvious from the
    \\  diff. Wrap the body at 72 columns.
    \\
    \\Output only the commit message. No code fences, no preamble, no explanation.
;

const usage =
    \\zc - write commit messages with AI
    \\
    \\usage: zc [options]
    \\
    \\  -h, --help  show this help
    \\
    \\Reads the staged diff, proposes a commit message, and commits on confirmation.
    \\Offers to stage everything when nothing is staged.
    \\Requires OPENAI_API_KEY.
    \\
;

pub fn main() !void {
    // `std.process.exit` below skips defers; the OS reclaims the arena anyway.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print("{s}", .{usage});
            return;
        }
        std.debug.print("unknown option: {s}\n\n{s}", .{ arg, usage });
        return;
    }

    var diff = try git(alloc, &.{ "git", "diff", "--cached" });
    if (diff.len == 0) {
        const changed = try git(alloc, &.{ "git", "diff", "--stat" });
        // --exclude-standard honours .gitignore, so ignored files never appear
        // here and `git add -A` below cannot sweep them in.
        const untracked = try git(alloc, &.{ "git", "ls-files", "--others", "--exclude-standard" });

        if (changed.len == 0 and untracked.len == 0) {
            std.debug.print("nothing to commit.\n", .{});
            return;
        }

        std.debug.print("nothing staged. available:\n", .{});
        if (changed.len > 0) std.debug.print("\n{s}", .{changed});
        if (untracked.len > 0) std.debug.print("\nuntracked:\n{s}", .{untracked});
        std.debug.print("\n", .{});

        if (!confirm("stage all and continue?")) {
            std.debug.print("aborted\n", .{});
            return;
        }

        _ = try git(alloc, &.{ "git", "add", "-A" });
        diff = try git(alloc, &.{ "git", "diff", "--cached" });
        if (diff.len == 0) {
            std.debug.print("nothing staged\n", .{});
            return;
        }
    }

    const api_key = std.process.getEnvVarOwned(alloc, "OPENAI_API_KEY") catch {
        std.debug.print("OPENAI_API_KEY is not set\n", .{});
        std.process.exit(1);
    };

    const message = try generate(alloc, api_key, diff);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n{s}\n\n", .{message});

    if (!confirm("commit?")) {
        std.debug.print("aborted\n", .{});
        return;
    }
    std.debug.print("{s}", .{try git(alloc, &.{ "git", "commit", "-m", message })});
}

// Minimal spinner on stderr, drawn from its own thread while a blocking call
// runs. Silent when stderr is not a TTY, so piped output stays clean.
const Spinner = struct {
    thread: ?std.Thread = null,
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    const frames = [_][]const u8{ "\u{280b}", "\u{2819}", "\u{2839}", "\u{2838}", "\u{283c}", "\u{2834}", "\u{2826}", "\u{2827}", "\u{2807}", "\u{280f}" };

    fn start(self: *Spinner, label: []const u8) void {
        if (!std.io.getStdErr().isTty()) return;
        self.thread = std.Thread.spawn(.{}, run, .{ self, label }) catch null;
    }

    fn done(self: *Spinner) void {
        const thread = self.thread orelse return;
        self.stop.store(true, .release);
        thread.join();
        self.thread = null;
    }

    fn run(self: *Spinner, label: []const u8) void {
        const stderr = std.io.getStdErr().writer();
        var i: usize = 0;
        while (!self.stop.load(.acquire)) : (i += 1) {
            stderr.print("\r{s} {s}", .{ frames[i % frames.len], label }) catch return;
            std.time.sleep(80 * std.time.ns_per_ms);
        }
        stderr.print("\r\x1b[K", .{}) catch {}; // erase the line on the way out
    }
};

// Run git and return its stdout. Failure is fatal and already reported, so
// callers only ever see success. argv[1] is the subcommand, used in messages.
fn git(alloc: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    const result = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = argv,
        .max_output_bytes = max_diff_bytes,
    });
    switch (result.term) {
        .Exited => |code| if (code != 0) {
            std.debug.print("git {s} failed: {s}\n", .{ argv[1], result.stderr });
            std.process.exit(1);
        },
        else => {
            std.debug.print("git {s} was killed\n", .{argv[1]});
            std.process.exit(1);
        },
    }
    return result.stdout;
}

fn generate(alloc: std.mem.Allocator, api_key: []const u8, diff: []const u8) ![]const u8 {
    const Message = struct { role: []const u8, content: []const u8 };
    const Request = struct {
        model: []const u8 = model,
        messages: []const Message,
    };

    var body = std.ArrayList(u8).init(alloc);
    try std.json.stringify(Request{
        .messages = &.{
            .{ .role = "system", .content = system_prompt },
            .{ .role = "user", .content = diff },
        },
    }, .{}, body.writer());

    // Header values must outlive the request; this one lives in the arena.
    const auth = try std.fmt.allocPrint(alloc, "Bearer {s}", .{api_key});

    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    var response = std.ArrayList(u8).init(alloc);

    var spinner: Spinner = .{};
    spinner.start("generating commit message");
    errdefer spinner.done();

    const result = try client.fetch(.{
        .location = .{ .url = api_url },
        .method = .POST,
        .payload = body.items,
        .extra_headers = &.{
            .{ .name = "authorization", .value = auth },
            .{ .name = "content-type", .value = "application/json" },
        },
        .response_storage = .{ .dynamic = &response },
    });

    spinner.done();

    if (result.status != .ok) {
        std.debug.print("api returned {d}:\n{s}\n", .{ @intFromEnum(result.status), response.items });
        std.process.exit(1);
    }

    // `content` is null when the model refuses or returns only a tool call.
    const Choice = struct { message: struct { content: ?[]const u8 = null } };
    const Response = struct { choices: []const Choice };

    const parsed = try std.json.parseFromSlice(Response, alloc, response.items, .{
        .ignore_unknown_fields = true,
    });

    if (parsed.value.choices.len > 0) {
        if (parsed.value.choices[0].message.content) |text| {
            const trimmed = std.mem.trim(u8, text, " \t\r\n");
            if (trimmed.len > 0) return trimmed;
        }
    }

    std.debug.print("no message in api response:\n{s}\n", .{response.items});
    std.process.exit(1);
}

fn confirm(prompt: []const u8) bool {
    std.debug.print("{s} [Y/n] ", .{prompt});

    var buf: [64]u8 = undefined;
    // `catch null` covers a stray paste longer than the buffer; `orelse` covers
    // Ctrl-D and a closed stdin. Neither is a human saying yes, so both abort.
    const maybe = std.io.getStdIn().reader().readUntilDelimiterOrEof(&buf, '\n') catch null;
    const line = maybe orelse return false;

    const answer = std.mem.trim(u8, line, " \t\r");
    if (answer.len == 0) return true; // bare Enter accepts
    return std.ascii.eqlIgnoreCase(answer, "y") or std.ascii.eqlIgnoreCase(answer, "yes");
}
