#!/bin/sh
# Build a Crystal game for the browser: script/build-web.sh path/to/main.cr out_dir
set -e
SRC="$1"; OUT="${2:-dist/web/$(basename $(dirname "$SRC"))}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/.wasm-toolchain"
if [ ! -d "$TOOL/libs" ]; then
  echo "downloading wasm libs..."
  mkdir -p "$TOOL/libs"
  curl -sL https://github.com/lbguilherme/wasm-libs/releases/download/0.0.3/wasm32-wasi-libs.tar.gz | tar xz -C "$TOOL/libs"
fi
export PATH="$ROOT/script/wasm-bin:$PATH"
mkdir -p "$OUT"
NAME="$(basename "$OUT")"
EAGLE_WASM_LIBS="$TOOL/libs" crystal build "$SRC" --target wasm32-unknown-wasi --release \
  -o "$OUT/$NAME.wasm" ${EAGLE_WASM_FLAGS:-}
cp "$ROOT/web/eagle.js" "$OUT/eagle.js"
if [ ! -f "$OUT/index.html" ]; then
cat > "$OUT/index.html" <<HTML
<!doctype html>
<html><head><meta charset="utf-8"><title>$NAME</title>
<style>html,body{margin:0;background:#111;color:#ddd;font-family:system-ui;height:100%}canvas{display:block;margin:0 auto;background:#000}</style></head>
<body><canvas id="eagle"></canvas>
<script type="module">
import { runEagle } from "./eagle.js";
runEagle("./$NAME.wasm", document.getElementById("eagle"), { antialias: true });
</script></body></html>
HTML
fi
ls -la "$OUT"
