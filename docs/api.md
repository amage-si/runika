# Runika API

Runika depends on `Base` from the official Bend toolchain and on the path types
of [Splina](https://github.com/amage-si/splina) (`Splina/path.bend`). Import
paths are relative to the calling file. A module next to the `Runika` and
`Splina` directories uses:

```bend
import Base
import ./Runika/font.bend as F
import ./Runika/glyf.bend as G
import ./Splina/path.bend as P
```

Pure functions return `Result<&2, &2, String, T>`: `Done{value}` or
`Fail{message}`. Malformed input never aborts the program.

## Types

```bend
Font{upem: U32, ascender: F32, descender: F32, line_gap: F32,
     glyph_count: U32, metric_count: U32, long_loca: Bool,
     cmap: View, hmtx: View, loca: View, glyf: View,
     checksum: U32, latin: Latin}
   | Alias{font: Font}
Latin = Known{glyph: U32, advance: F32} | Unknown{} | Half{lo: Latin, hi: Latin}
Info{glyph: U32, advance: F32}
Metric{advance: F32, bearing: F32}
RawPoint{x: F32, y: F32, on: Bool}
```

`Font` keeps the validated header values (`hhea` ascender, descender, and line
gap; `maxp` glyph count; `hhea` number of long metrics), views of the
validated tables, the `head` checkSumAdjustment (`checksum`, the file's
identity) and the Latin-1 table (`latin`). Obtain it with `load` or `parse`;
building it by hand is only meant for internal tests, and such a font must
go through `with_latin`, which computes the table from its own `cmap` and
`hmtx` (as must a font whose `cmap` or `hmtx` is replaced). `Alias` exists
only to keep fonts boxed (see below): nothing builds one, and every function
answers for the font it wraps. All values are in font units.

`View` (`bytes.bend`) is an immutable, bounds-checked byte buffer. Reads return
`Fail` past the end, and `slice` checks `offset <= length` and
`count <= length - offset` before adding.

## Entry points

| Function | Contract |
| --- | --- |
| `F.load(path: String)` | `IO(Result<&2,&2,String,Font>)`. Reads at most 2 MiB plus one byte; a missing file is a `Fail`, not a process abort. |
| `F.parse(bytes: View)` | Validates the sfnt directory and the `head`, `maxp`, `hhea`, `hmtx`, `loca`, and `cmap` tables. |
| `F.glyph_id(font, scalar: U32)` | `cmap` format 4 lookup (Latin-1 from the table). Returns `0` for an unmapped scalar. Fails for scalars above U+FFFF and for surrogates. |
| `F.info(font, scalar: U32)` | `Info{glyph, advance}`: the glyph (`0` when unmapped) and, for a present glyph, its `hmtx` advance; no advance is read for glyph `0`. Same errors as `glyph_id` then `metric`. |
| `F.metric(font, glyph: U32)` | `Metric` from `hmtx`. Fails for a glyph id outside `maxp`. |
| `F.with_latin(font)` | The font with its Latin-1 table recomputed from its `cmap` and `hmtx`. |
| `F.units`, `F.ascender`, `F.descender`, `F.line_gap`, `F.checksum` | Header values and identity, for callers that should not depend on `Font`'s fields. |
| `F.glyph_data(font, glyph)` | The glyph's `glyf` bytes, located through `loca`. |
| `G.raw(font, glyph)` | `List<&2, List<&2, RawPoint>>`: contours of a simple glyph, or of a composite expanded with its transforms. |
| `G.outline(font, glyph)` | `P.Path{segments, P.NonZero{}}` with `MoveTo`, `Line`, `Quad`, and `ClosePath`. |

A glyph that the font does not contain maps to id `0` (`.notdef`). Callers decide
what to do with it; Syllo rejects text whose characters map to `0`.

## Outline contract

- Coordinates are font units, x to the right and **y up**. Runika applies no
  scale. Dithra's `rasterize(path, scale, advance)` converts to pixels.
- Contours keep the font's order. Every contour starts with `MoveTo` and ends
  with an explicit `ClosePath`, replacing TrueType's implied closing.
- Quadratic curves stay quadratic. The implied on-curve point between two
  consecutive off-curve points is computed as their midpoint. A contour whose
  first point is off-curve starts at its last point when that point is
  on-curve, otherwise at the midpoint of its first and last points.
- An empty glyph (such as space) has no segments.

## Limits

| Limit | Value |
| --- | --- |
| Font file | 2 MiB |
| Tables in the directory | 1 to 128 |
| `cmap` encoding records | 64 |
| Units per em | 16 to 16384 |
| Simple glyph | 256 contours, 4096 points |
| Composite nesting | 16 levels |
| Components per composite record | 64 |
| Glyph visits per expansion | 256 |
| Expanded glyph | 8192 points, 256 contours |

Exceeding a limit returns `Fail` with a message. Composite cycles end with a
limit error; there is no unbounded recursion and no `@unsafe`. Limits are
execution bounds, not proof that every glyph graph of a font is valid: glyphs
are validated when they are requested.

## Rejected input

Signatures other than TrueType 1.0 (`OTTO`/CFF, `wOFF`, `ttcf`), truncated
directories or tables, duplicate tags, invalid `head` magic or units per em,
incoherent `hhea`/`maxp` metrics, unsorted `cmap` segments, misaligned or
out-of-array `idRangeOffset` values, descending `loca` offsets or offsets past
`glyf`, truncated flag/coordinate/instruction streams, flag repeats past the
point count, reserved flags, conflicting composite transforms or offset flags,
and composite point attachment.

## Byte storage and performance

`View` reads a complete binary tree of 32-bit words, four bytes per leaf,
big-endian. A read descends one branch per level (17 for Liberation Sans)
with a comparison, a mask and a shift, and only borrows the tree; a 16- or
32-bit field inside one word costs one descent.

Measured on Liberation Sans 2.1.5 (410,820 bytes), 2,000,000 reads of
pseudo-random aligned `u32` values (`--threads 2`, Ryzen 7 5800H):

| Storage | Per read | Build |
| --- | --- | --- |
| Byte per leaf (Runika c2b4af9) | 1.7–1.9 µs | ~30 ms with the scan and validation |
| Word per leaf (this version) | 0.20–0.26 µs | ~20 ms |
| Native `Array<U32>` of the same words | ~1 ns | ~2 ms |

Bend 2.0.35 compiles `Array<U32>` to a flat block with O(1) reads, so a flat
array would be ~200 times faster per read. It is not used because an
`Array` is affine (a `Type`): it cannot be a field of a `Data` type, and `+`
(sharing) requires `Data` (the checker rejects both). Fonts are `Data`
values that Syllo, Dithra, Chromi, Mokko and Auvia copy freely and keep in
their models; an array would make every font, every model holding one and
every text call affine (`Array.fork` can share a block, but only between
affine owners). After the Latin-1 table and the callers' caches, bytes are
read only when a font loads (~20 ms, and ~0.5 ms for the table) and when a
glyph is rasterized for the first time (~50 µs of reads per glyph).

Fonts are boxed. The compiler passes a record that is not recursive
flattened, one word per field, through every call that carries it (a
`Font` was 25 words, five of them shared trees counted on every copy), and
the widest record of a program sets the size of every call frame in the
generated C (`WL_RESW`). The integrated demo's model holds a font; its
frame was 122 words, and making it 128 slowed every closure call by about a
third (decoding the demo's PNG and SVG went from ~147 to ~198 ms, measured).
A recursive type stays behind a pointer, so `Font` has the `Alias`
constructor: a font is one word and one count per copy, and the demo's
frame is 104 words.

## Runtime boundary

All parsing happens in Bend. The official runtime implements file IO; its OS
calls are external dependencies. Runika does not execute TrueType hinting
instructions, so outlines are unhinted.
