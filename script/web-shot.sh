#!/bin/sh
# Build an example for the web and screenshot it in headless Chrome: script/web-shot.sh name [seconds]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="$1"; BUDGET="${2:-4000}"
sh "$ROOT/script/build-web.sh" "$ROOT/examples/$NAME/main.cr" "$ROOT/dist/web/$NAME" > /tmp/web_build_$NAME.log 2>&1 || { tail -20 /tmp/web_build_$NAME.log; exit 1; }
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
cd /tmp && timeout 90 "$CHROME" --headless=new --use-angle=swiftshader --enable-unsafe-swiftshader --enable-logging=stderr --v=0 --window-size=1024,700 --virtual-time-budget=$BUDGET --screenshot="$ROOT/screenshots/web_$NAME.png" "http://localhost:8765/$NAME/" 2>&1 | grep "CONSOLE" | grep -v "ReadPixels\|AudioContext was not allowed" | sed 's/.*CONSOLE:[0-9]*\] //' | head -8
echo "screenshot: screenshots/web_$NAME.png"
