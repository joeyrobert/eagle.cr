#!/bin/sh
# Drives the web text field in headless Chrome with synthetic IME and clipboard events: script/web-input-check.sh [http_port [debug_port]]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-8791}"
OUT="$ROOT/dist/web/input_app"
sh "$ROOT/script/build-web.sh" "$ROOT/spec/web/input_app.cr" "$OUT" > /tmp/web_input_build.log 2>&1 || { tail -20 /tmp/web_input_build.log; exit 1; }
cp "$ROOT/spec/web/input_check.html" "$OUT/index.html"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
cd "$OUT"
python3 -m http.server "$PORT" --bind 127.0.0.1 > /dev/null 2>&1 &
SERVER=$!
DEBUG_PORT="${2:-9337}"
PROFILE="$(mktemp -d)"
"$CHROME" --headless=new --use-angle=swiftshader --enable-unsafe-swiftshader --window-size=600,300 --remote-debugging-port="$DEBUG_PORT" --user-data-dir="$PROFILE" "http://127.0.0.1:$PORT/" > /dev/null 2>&1 &
BROWSER=$!
trap 'kill $SERVER $BROWSER 2>/dev/null; sleep 1; rm -rf "$PROFILE" 2>/dev/null; true' EXIT
node "$ROOT/script/web_input_read.mjs" "$DEBUG_PORT"
