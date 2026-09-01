#!/bin/sh
# curl -fsSL https://raw.githubusercontent.com/rocktimsaikia/zc/main/install.sh | sh
set -eu

PREFIX="${PREFIX:-$HOME/.local}"
REPO="https://github.com/rocktimsaikia/zc"

for cmd in zig git; do
    command -v "$cmd" >/dev/null || {
        echo "$cmd not found" >&2
        [ "$cmd" = zig ] && echo "install Zig 0.14.1: https://ziglang.org/download/" >&2
        exit 1
    }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone --depth 1 -q "$REPO" "$tmp/zc"
cd "$tmp/zc"
zig build -Doptimize=ReleaseSafe --prefix "$PREFIX"

echo "installed $PREFIX/bin/zc"
case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) echo "note: $PREFIX/bin is not on your PATH" >&2 ;;
esac
