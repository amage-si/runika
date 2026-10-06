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
     cmap: View, hmtx: View, loca: View, glyf: View}
Metric{advance: F32, bearing: F32}
RawPoint{x: F32, y: F32, on: Bool}
```

`Font` keeps the validated header values (`hhea` ascender, descender, and line
gap; `maxp` glyph count; `hhea` number of long metrics) and views of the
validated tables. Obtain it with `load` or `parse`; building it by hand is only
meant for internal tests. All values are in font units.

`View` (`bytes.bend`) is an immutable, bounds-checked byte buffer. Reads return
`Fail` past the end, and `slice` checks `offset <= length` and
`count <= length - offset` before adding.

## Entry points

| Function | Contract |
| --- | --- |
| `F.load(path: String)` | `IO(Result<&2,&2,String,Font>)`. Reads at most 2 MiB plus one byte; a missing file is a `Fail`, not a process abort. |
| `F.parse(bytes: View)` | Validates the sfnt directory and the `head`, `maxp`, `hhea`, `hmtx`, `loca`, and `cmap` tables. |
| `F.glyph_id(font, scalar: U32)` | `cmap` format 4 lookup. Returns `0` for an unmapped scalar. Fails for scalars above U+FFFF and for surrogates. |
| `F.metric(font, glyph: U32)` | `Metric` from `hmtx`. Fails for a glyph id outside `maxp`. |
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

## Runtime boundary

All parsing happens in Bend. The official runtime implements file IO; its OS
calls are external dependencies. Runika does not execute TrueType hinting
instructions, so outlines are unhinted.
