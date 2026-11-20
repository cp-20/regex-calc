#!/bin/sh
# Download the OFL font sources used by the deck into slides/fonts/src/.
# build.js subsets them (subset.py) to the glyphs actually used and embeds them as woff2.
#   LINE Seed JP   (text)  https://github.com/google/fonts/tree/main/ofl/lineseedjp  (OFL-LINESeedJP.txt)
#   Monaspace Neon (code)  https://github.com/githubnext/monaspace                 (OFL-MonaspaceNeon.txt)
set -e
cd "$(dirname "$0")"
mkdir -p src
for w in Regular Bold ExtraBold; do
  curl -sSfL -o "src/LINESeedJP-$w.ttf" "https://github.com/google/fonts/raw/main/ofl/lineseedjp/LINESeedJP-$w.ttf"
done
v=v1.400
tmp=$(mktemp -d)
curl -sSfL -o "$tmp/m.zip" "https://github.com/githubnext/monaspace/releases/download/$v/monaspace-static-$v.zip"
unzip -q -o "$tmp/m.zip" -d "$tmp"
for w in Regular Medium SemiBold; do
  find "$tmp" -name "MonaspaceNeon-$w.otf" -exec cp {} "src/MonaspaceNeon-$w.otf" \;
done
rm -rf "$tmp"
ls -l src
