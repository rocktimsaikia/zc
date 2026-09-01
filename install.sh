#!/bin/sh
# curl -fsSL https://raw.githubusercontent.com/rocktimsaikia/zc/main/install.sh | sh
set -eu

PREFIX="${PREFIX:-$HOME/.local}"
REPO="rocktimsaikia/zc"

os=$(uname -s)
arch=$(uname -m)

case "$os" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    *) echo "unsupported os: $os" >&2; exit 1 ;;
esac

case "$arch" in
    x86_64 | amd64) arch=x86_64 ;;
    arm64 | aarch64) arch=aarch64 ;;
    *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
esac

command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

url="https://github.com/$REPO/releases/latest/download/zc-$arch-$os.tar.gz"
echo "downloading zc-$arch-$os"
curl -fsSL "$url" | tar -xz -C "$tmp"

mkdir -p "$PREFIX/bin"
cp "$tmp/zc" "$PREFIX/bin/zc"
chmod 755 "$PREFIX/bin/zc"

echo "installed $PREFIX/bin/zc"
case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) echo "note: $PREFIX/bin is not on your PATH" >&2 ;;
esac
