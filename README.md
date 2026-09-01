# zc

Write git commit messages with AI. Reads your staged diff, proposes a
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) message,
commits on confirmation.

No dependencies - just Zig's standard library.

## Install

Needs [Zig 0.14.1](https://ziglang.org/download/).

```sh
git clone https://github.com/rocktimsaikia/zc
cd zc
zig build -Doptimize=ReleaseSafe --prefix ~/.local
```

Make sure `~/.local/bin` is on your `PATH`.

## Setup

`zc` reads your key from the environment:

```sh
export OPENAI_API_KEY=sk-...
```

Get a key at <https://platform.openai.com/api-keys>.

Don't put that line in a shell config you commit to a dotfiles repo. Keep it in
a file the repo doesn't track and source it:

```sh
# in ~/.zshrc
[ -f ~/.secrets ] && source ~/.secrets
```

Any secret manager works too, since they all end in an exported env var:

```sh
op run --env-file=.env -- zc          # 1Password
export OPENAI_API_KEY=$(pass openai)  # pass
```

## Usage

```sh
git add .
zc
```

```
feat(parse): return null for empty input

commit? [Y/n]
```

Enter or `y` commits. `n` or anything else aborts. Nothing is committed until
you say so.

```sh
zc --help    # no API call
```

## How it works

```
git diff --cached  ->  OpenAI chat completions  ->  y/n  ->  git commit -m
```

Around 200 lines in `src/main.zig`. `std.process.Child` for git, `std.json` for
the request and response, `std.http.Client` for the call. Nothing else.

Model is `gpt-5.4-mini`, set at the top of `src/main.zig`. It was picked by
measurement: ~1s and ~11 output tokens per message, versus 13s and ~1170 for
`gpt-5-mini`, which spends most of them on reasoning this task doesn't need.

## License

MIT
