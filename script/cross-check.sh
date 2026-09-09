#!/bin/sh
# Verifies the engine compiles for Windows and Linux targets (object files only; linking needs the target libs).
set -e
cd "$(dirname "$0")/.."
for t in x86_64-pc-windows-msvc x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu; do
  echo "== $t"
  crystal build examples/smoke/main.cr --cross-compile --target "$t" -o "/tmp/eagle_cross_$t" > /dev/null
  echo "ok"
done
