#!/bin/sh
# Builds the marketing + docs site into site/: web examples, API docs, generated pages.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ "$1" != "--no-wasm" ]; then
  for d in examples/*/; do
    n="$(basename "$d")"
    if [ "$1" = "--rebuild" ] || [ ! -f "dist/web/$n/$n.wasm" ]; then
      echo "== building $n for web"
      sh script/build-web.sh "examples/$n/main.cr" "dist/web/$n" > "/tmp/eagle_web_$n.log" 2>&1 || { tail -5 "/tmp/eagle_web_$n.log"; echo "(skipped $n)"; }
    fi
  done
fi
mkdir -p site/docs
crystal docs src/eagle.cr -o site/docs/api > /dev/null 2>&1
crystal run script/site_gen.cr
echo "open site/index.html (or: cd site && python3 -m http.server)"
