#!/bin/sh
# Regenerate slides/og.png (the social preview image, 1200x630 @2x) from the
# first frame of the built deck.  Run after `node slides/build.js`.
# Needs Google Chrome (or set CHROME=/path/to/chromium).
set -e
cd "$(dirname "$0")"
tmp=$(mktemp -d)
"${CHROME:-google-chrome}" --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=2 --window-size=1200,630 --virtual-time-budget=4000 \
  --user-data-dir="$tmp" --screenshot="$PWD/og.png" "file://$PWD/index.html" >/dev/null 2>&1
rm -rf "$tmp"
echo "og.sh: wrote slides/og.png"
