# zc

AI commit messages. Reads your staged diff, proposes a
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) message,
commits on confirmation. No dependencies beyond Zig's standard library.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/rocktimsaikia/zc/main/install.sh | sh
```

Needs [Zig 0.14.1](https://ziglang.org/download/). Installs to `~/.local/bin`,
override with `PREFIX`.

## Setup

```sh
export OPENAI_API_KEY=sk-...
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

Enter or `y` commits. Anything else aborts.

## License

MIT
