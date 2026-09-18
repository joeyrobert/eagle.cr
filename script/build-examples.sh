#!/bin/sh
# Type-check every example, or link each executable when passed --link.
set -eu

case "${1:-}" in
  "") link=false ;;
  --link) link=true ;;
  *)
    echo "usage: $0 [--link]" >&2
    exit 2
    ;;
esac

cd "$(dirname "$0")/.."
mkdir -p bin/examples
fail=0
for f in examples/*/main.cr; do
  n="$(basename "$(dirname "$f")")"
  if [ "$link" = true ]; then
    if crystal build "$f" -o "bin/examples/$n"; then
      echo "ok $n"
    else
      echo "FAIL $n"
      fail=1
    fi
  else
    if crystal build "$f" --no-codegen; then
      echo "ok $n"
    else
      echo "FAIL $n"
      fail=1
    fi
  fi
done
exit $fail
