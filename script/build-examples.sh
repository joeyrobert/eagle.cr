#!/bin/sh
# Type-check every example, link each executable with --link, or link and run 30 frames of each with --run.
set -eu

case "${1:-}" in
  "") link=false; run=false ;;
  --link) link=true; run=false ;;
  --run) link=true; run=true ;;
  *)
    echo "usage: $0 [--link|--run]" >&2
    exit 2
    ;;
esac

cd "$(dirname "$0")/.."
mkdir -p bin/examples screenshots/examples
fail=0
for f in examples/*/main.cr; do
  n="$(basename "$(dirname "$f")")"
  if [ "$link" = true ]; then
    if ! crystal build "$f" -Dwithout_mt -o "bin/examples/$n"; then
      echo "FAIL $n"
      fail=1
    elif [ "$run" = true ] && ! EAGLE_FRAMES=30 EAGLE_SCREENSHOT="screenshots/examples/$n.png" "bin/examples/$n" >/dev/null; then
      echo "FAIL $n (run)"
      fail=1
    elif [ "$run" = true ] && [ ! -s "screenshots/examples/$n.png" ]; then
      echo "FAIL $n (no screenshot)"
      fail=1
    else
      echo "ok $n"
    fi
  else
    if crystal build "$f" -Dwithout_mt --no-codegen; then
      echo "ok $n"
    else
      echo "FAIL $n"
      fail=1
    fi
  fi
done
exit $fail
