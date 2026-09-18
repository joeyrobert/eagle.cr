#!/bin/sh
# Packages a release tarball for install.sh: script/package-release.sh eagle-macos-arm64 [path/to/eagle]
# Layout: bin/eagle plus src/ (the engine source at HEAD, used for examples and web exports).
set -eu
NAME="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${2:-$ROOT/bin/eagle}"
STAGE="$ROOT/dist/$NAME"
rm -rf "$STAGE" "$STAGE.tar.gz"
mkdir -p "$STAGE/bin" "$STAGE/src"
cp "$BIN" "$STAGE/bin/eagle"
chmod 755 "$STAGE/bin/eagle"
git -C "$ROOT" archive --format=tar HEAD | tar -x -C "$STAGE/src"
tar -czf "$STAGE.tar.gz" -C "$STAGE" bin src
echo "$STAGE.tar.gz ($(du -k "$STAGE.tar.gz" | cut -f1) KB)"
