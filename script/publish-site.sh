#!/bin/sh
# Publishes site/ to the gh-pages branch, which GitHub Pages serves. Run script/build-site.sh first.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f site/index.html ] || { echo "no site/ yet: run script/build-site.sh first"; exit 1; }
W="$(mktemp -d)/gh-pages"
git fetch -q origin gh-pages
git worktree add -q -B gh-pages "$W" origin/gh-pages
rsync -a --delete --exclude .git --exclude .DS_Store site/ "$W/"
touch "$W/.nojekyll"
cd "$W"
git add -A
if git diff --cached --quiet; then
  echo "site unchanged"
else
  git commit -q -m "Publish site from $(git -C "$ROOT" rev-parse --short HEAD)"
  git push -q origin gh-pages
  echo "published: https://joeyrobert.github.io/eagle.cr/"
fi
cd "$ROOT"
git worktree remove --force "$W"
