# Validation notes

## Native checks

`tests.bend` runs 51 checks. Synthetic byte sequences
(`test_support.bend`) cover malformed input: truncated directories and glyph
streams, overflowing offsets, invalid `loca`, repeats past the point count,
point attachment, conflicting transforms, a composite that refers to itself,
and `cmap` glyph-array offsets that are odd, before the array, or past its end.
Reference checks against Liberation Sans 2.1.5 assert the header values and,
for U+0020, U+0041, U+00E3, U+00E7, U+00E9, and U+00FA, the glyph id, advance,
bearing, contour count, and point count.

## Independent reference

The fontTools comparison checks much more than the suite, but it is a test
oracle, not part of the library:

1. `tools/reference_dump.bend` prints one JSON row per scalar for
   U+0020..U+007E and U+00A0..U+00FF: scalar, glyph id, advance, bearing, and
   every contour with every point as `[x, y, on]`.
2. `tools/fonttools_reference.py` loads the same font with fontTools and
   asserts that each row is identical to fontTools' glyph id, `hmtx` entry,
   and `getCoordinates` result (composites expanded by fontTools).

The recorded run used fontTools 4.66.1 and Liberation Sans Regular 2.1.5
(SHA-256 `baccc64becc3eb7d104b7c84d99f5314a0a1f896e2b3ea6c2f22fc08d2003bee`):
191 scalars, 59 composite glyphs, 4908 points, all equal.

This covers one font and the Latin-1 range. Other fonts, larger glyph sets, and
adversarial files beyond the synthetic cases have not been compared.

## Development notes

- The first recursive byte-counting and byte-validation helpers were not
  tail-recursive. Running them on a whole font file (about 400 KB) failed with
  `bend: memory fault (machine stack overflow?)`. Rewriting them as tail
  recursion fixed it. Prefer tail recursion for loops over input-sized lists.
- The official file effect accepts the mode `"r"`, not `"rb"` (`rb` fails with
  `Invalid argument`).
- The generated native runtime reserves an 8 GiB virtual arena at start-up
  (with `MAP_NORESERVE`); resident memory for these programs is far lower.
  Running a binary under `RLIMIT_AS`/`ulimit -v` below that reservation fails
  immediately with `bend: reservation failed`. Do not limit virtual memory to
  control resident memory.
