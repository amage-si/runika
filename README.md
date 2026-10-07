# Runika

**TrueType font reading in Bend 2: character map, metrics, and glyph outlines.**

Runika is the font layer of the AMAGE UI ecosystem. It reads a TrueType file,
validates the tables it needs, maps Unicode scalars to glyphs, and returns
metrics and outlines in font units. The parsers are written in Bend 2; they do
not call FreeType, HarfBuzz, Skia, or any other font engine, and there is no
hand-written native code.

**Status:** early Linux implementation, tested with **Bend 2.0.35**. It reads a
documented subset of TrueType, enough for Latin text with the fonts installed
on the development machine. It is not a complete OpenType implementation.

## What works today

- sfnt TrueType 1.0: big-endian table directory, `head`, `maxp` 1.0, `hhea`,
  `hmtx`, short and long `loca`, and `glyf`.
- `cmap` format 4 from the Unicode platform or Microsoft Unicode BMP, including
  `idDelta`, `idRangeOffset`, and glyph-array entries of zero.
- Simple glyphs: end points, skipped instructions, repeated flags, short and
  full x/y deltas, on/off-curve points, and TrueType's implied closing, turned
  into explicit paths.
- Composite glyphs with signed 8/16-bit XY arguments, translation, uniform
  scale, separate x/y scales, and 2×2 F2Dot14 matrices, with scaled or
  unscaled offsets. Nested components are expanded in order, within limits.
- Outlines as a [Splina](https://github.com/amage-si/splina) `Path`: `MoveTo`,
  `Line`, `Quad`, `ClosePath`, `NonZero` fill. Implied on-curve points between
  consecutive quadratic controls are computed in Bend. Each contour is closed
  explicitly, in font order.
- A Latin-1 table built with every font: for U+0000..U+00FF (the scalars Syllo
  lays out) the glyph and advance the `cmap` and `hmtx` give, computed once at
  parse time. `F.info` and `F.glyph_id` answer those characters in eight steps
  instead of a `cmap` search and an `hmtx` read, with the same results and
  errors (a character the font could not answer goes through the tables).
- The file's identity (`head` checkSumAdjustment) for caches of derived data.

The native suite has **58 checks**: truncated and out-of-range input, offset
and slice overflow, every byte/u16/u32 read at every offset and alignment of
small buffers, every table checksum of Liberation Sans against its directory
(each word of the file read through the byte tree), malformed directories and
`loca`, flag repeats, composite cycles, signed composite arguments with
F2Dot14 scale, `cmap` glyph-array edge cases, the Latin-1 table answering
exactly as the tables do (U+0000 to U+012B), its rebuild after a `cmap` is
replaced, and reference values from Liberation Sans.

Outside the suite, `tools/` compares Runika against **fontTools 4.66.1**: all
191 characters of ASCII 32–126 and Latin-1 160–255 in Liberation Sans
(59 of them composite) matched exactly on glyph id, advance, bearing, contour
order, and **all 4908 points** (x, y, and on-curve flag). For example, "ã" is
glyph 165 with 3 contours, 73 points, advance 1139, and bearing 87.
See [docs/validation.md](docs/validation.md).

## Quick start

Requirements: the [Bend 2 toolchain](https://bend-lang.com), Clang 14 or newer,
and the [Splina](https://github.com/amage-si/splina) repository cloned next to
Runika, because Runika returns Splina's path type. The tests and example read
Liberation Sans 2.1.5 from
`/usr/share/fonts/liberation/LiberationSans-Regular.ttf`; see
[Test font](#test-font).

```sh
mkdir amage && cd amage
git clone https://github.com/amage-si/runika.git Runika
git clone https://github.com/amage-si/splina.git Splina
cd Runika
export BEND_NO_TELEMETRY=1
bend version
mkdir -p build
bend tests.bend -o build/tests
./build/tests --threads 2 --gpu off
```

The directory names matter: imports use relative paths such as
`../Splina/path.bend`.

Print the glyph id and outline size of "ã":

```sh
bend examples/outline.bend -o build/outline
./build/outline --threads 2 --gpu off
# U+00E3 glyph=165 path_commands=...
```

## Using the API

```bend
import Base
import ../Runika/font.bend as F
import ../Runika/glyf.bend as G
```

| Function | Result |
| --- | --- |
| `F.load(path)` | `IO(Result<&2,&2,String,F.Font>)`: reads and validates a font file. |
| `F.parse(bytes)` | Validates a font from a byte `View`. |
| `F.glyph_id(font, scalar)` | Glyph id for a Unicode scalar; `0` when the font has no mapping. |
| `F.info(font, scalar)` | `Info{glyph, advance}`: glyph id and, for a present glyph, its advance (Latin-1 from the table). |
| `F.metric(font, glyph)` | `Metric{advance, bearing}` from `hmtx`, in font units. |
| `F.units`, `F.ascender`, `F.descender`, `F.line_gap`, `F.checksum` | Header values and the file's identity. |
| `G.raw(font, glyph)` | Contours as lists of `RawPoint{x, y, on}`, composites expanded. |
| `G.outline(font, glyph)` | The glyph as a closed Splina `Path`, in font units. |

Coordinates stay in font units with **y pointing up**. Converting to screen
pixels belongs to the rasterizer ([Dithra](https://github.com/amage-si/dithra)).
Read the [API reference](docs/api.md) for types, limits, and error behavior.

## Current boundaries

Not implemented: TrueType collections (TTC), CFF/CFF2, WOFF/WOFF2, `cmap`
formats 12/13/14 (so no scalars outside the BMP), variable-font axes (only the
default `glyf` outline is read), color glyphs (COLR/CPAL/SVG/bitmap), GSUB,
GPOS, kerning, complex shaping, hinting and TrueType instructions, and
component alignment by point indices (point attachment is rejected).
Metrics are the explicit `hmtx` values; `USE_MY_METRICS`, `ROUND_XY_TO_GRID`,
and phantom points are not applied.

Glyphs are validated on demand, not when the font is opened. sfnt checksums
and overlap between table regions are not audited. Runika is not a complete
OpenType sanitizer, and the tests are evidence for the declared subset, not a
proof of correct parsing for every font.

Font bytes live in an immutable tree of 32-bit words (four bytes per leaf):
an aligned `u32` read of Liberation Sans takes ~0.23 µs (it was ~1.8 µs with a
byte per leaf), and loading the font ~7 ms (~30 ms before). A native `Array<U32>` would read
in ~1 ns, but Bend arrays are affine and a font is shared `Data`; see
[docs/api.md](docs/api.md#byte-storage-and-performance) for the measurements
and why fonts are passed boxed (one pointer). After the Latin-1 table and the
callers' caches (Chromi's demo text), bytes are read when a font loads and
when a glyph is rasterized for the first time. No performance advantage over
existing engines is claimed.

## Test font

The tests assert values from one specific file, Liberation Sans Regular 2.1.5:
2048 units per em, 2620 glyphs, ascender 1854, descender −434, line gap 67,
SHA-256 `baccc64becc3eb7d104b7c84d99f5314a0a1f896e2b3ea6c2f22fc08d2003bee`.
The font is not included in this repository. Install it from your
distribution (`ttf-liberation` on Arch) or from the
[Liberation Fonts](https://github.com/liberationfonts/liberation-fonts)
releases, and make it available at the path above. Another version of the
font may make the reference checks fail.

## Repository map

| Path | Purpose |
| --- | --- |
| [font.bend](font.bend) | Table directory, `head`/`hhea`/`maxp`, `cmap`, `hmtx`, `loca`, the Latin-1 table. |
| [glyf.bend](glyf.bend) | Simple and composite glyphs, raw points, Splina outlines. |
| [bytes.bend](bytes.bend) | Bounds-checked byte views over a word tree, and file loading. |
| [check.bend](check.bend) | Small test helpers, also used by sibling suites. |
| [tests.bend](tests.bend), [test_support.bend](test_support.bend) | Native checks and synthetic font data. |
| [examples/outline.bend](examples/outline.bend) | Loads a font and outlines one glyph. |
| [tools/](tools/) | Validation only: glyph dump and the fontTools comparison. |
| [docs/api.md](docs/api.md) | Types, limits, and contracts. |
| [docs/validation.md](docs/validation.md) | Reference comparison and development notes. |

## Direction

Next are `cmap` format 12 for scalars outside the BMP, kerning and the GPOS/GSUB
data that Latin text needs, and broader font coverage measured on real files.
These are goals, not supported features.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development rules. The API is
experimental and may change. Licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT](LICENSE-MIT), at your option.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option. Unless you explicitly state otherwise, any contribution
intentionally submitted for inclusion in this work, as defined in the
Apache-2.0 license, shall be dual licensed as above, without any additional
terms or conditions.
