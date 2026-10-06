"""Independent test oracle: compare Runika's glyph dump with fontTools.

Not imported or executed by the Bend library. Requires fontTools (the recorded
comparison used 4.66.1). Produce the dump with tools/reference_dump.bend first:

    bend tools/reference_dump.bend -o build/reference-dump
    ./build/reference-dump --threads 2 --gpu off > build/bend-reference.jsonl
    python3 tools/fonttools_reference.py build/bend-reference.jsonl

The dump covers U+0020..U+007E and U+00A0..U+00FF. Every row must match
fontTools exactly: glyph id, hmtx advance and bearing, contour order, every
x/y coordinate and every on-curve flag.
"""
from pathlib import Path
import hashlib
import json
import sys

import fontTools
from fontTools.ttLib import TTFont

DEFAULT_FONT = '/usr/share/fonts/liberation/LiberationSans-Regular.ttf'


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit('usage: fonttools_reference.py DUMP.jsonl [FONT.ttf]')
    dump = Path(sys.argv[1])
    source = Path(sys.argv[2] if len(sys.argv) == 3 else DEFAULT_FONT)
    font = TTFont(source)
    cmap = font.getBestCmap()
    rows = [json.loads(line) for line in dump.read_text().splitlines() if line.strip()]
    assert len(rows) == 191, f'expected 191 rows, got {len(rows)}'
    compounds = 0
    total_points = 0
    for got in rows:
        scalar = got[0]
        name = cmap[scalar]
        glyph = font['glyf'][name]
        points, ends, flags = glyph.getCoordinates(font['glyf'])
        contours = []
        start = 0
        for end in ends:
            contours.append([[float(x), float(y), int(flags[i] & 1)]
                             for i, (x, y) in enumerate(points[start:end + 1], start)])
            start = end + 1
        expected = [scalar, font.getGlyphID(name), *font['hmtx'][name], contours]
        assert got == expected, (scalar, name, got, expected)
        compounds += glyph.isComposite()
        total_points += len(points)

    print(json.dumps({
        'reference': 'fontTools ' + fontTools.__version__,
        'font': str(source),
        'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'scalars': len(rows),
        'composite_glyphs': compounds,
        'exact_points_checked': total_points,
        'result': 'PASS',
    }, indent=2))


if __name__ == '__main__':
    main()
