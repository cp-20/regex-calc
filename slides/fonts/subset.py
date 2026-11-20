#!/usr/bin/env python3
"""Subset an OFL font to the glyphs the deck uses and save it as woff2.

    python3 subset.py SRC OUT FAMILY WEIGHT CHARS_FILE

The SIL OFL forbids using a Reserved Font Name (e.g. "Monaspace") for a
modified version, and a subset is a modified version.  So the subset is
renamed to FAMILY ("Deck Sans" / "Deck Mono"), while the copyright (name ID 0)
and license (IDs 13, 14) records are kept as the OFL requires.
Needs: pip install fonttools brotli
"""
import sys
from fontTools import subset
from fontTools.ttLib import TTFont

src, out, family, weight, chars_file = sys.argv[1:6]
with open(chars_file, encoding='utf-8') as f:
    text = f.read()

font = TTFont(src)
opts = subset.Options()
opts.layout_features = ['*']
opts.flavor = 'woff2'
opts.name_IDs = [0, 13, 14]  # keep copyright + license, drop the original names
sub = subset.Subsetter(opts)
sub.populate(text=text)
sub.subset(font)

name = font['name']
full = f'{family} {weight}'
for nid, value in ((1, family), (2, 'Regular'), (3, f'{full};deck-subset'), (4, full),
                   (6, full.replace(' ', '-')), (16, family), (17, weight)):
    name.setName(value, nid, 3, 1, 0x409)
if 'CFF ' in font:  # OpenType/CFF keeps its own copy of the names
    cff = font['CFF '].cff
    cff.fontNames = [full.replace(' ', '-')]
    top = cff.topDictIndex[0]
    top.FamilyName, top.FullName = family, full
subset.save_font(font, out, opts)
