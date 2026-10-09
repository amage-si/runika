# Runika: instructions for contributors and agents

Runika is the font-reading layer of the AMAGE UI ecosystem, implemented in
**Bend 2**: font formats, character maps, metrics, glyph outlines, and the
tables that text processing needs. Read the README for current capabilities and
limits; a roadmap item is not implemented merely because it appears in the
project scope.

## Implementation

- Implement library logic in Bend 2, rather than wrapping an existing font
  engine (FreeType, HarfBuzz, Skia, ...) or embedding pre-converted glyph data.
- Treat every font as untrusted input. Check every read against its table,
  validate offsets before adding them, bound loops and recursion, and return
  errors instead of aborting.
- Keep font units and the font's y-up orientation. Conversions to screen space
  belong to Dithra; shared outline types belong to Splina.
- The official Bend compiler/runtime, OS APIs, and drivers remain external
  dependencies. Keep any future native bridge minimal, explicit, and separate.
- Before writing Bend, run `bend version` and read `bend guide` from the installed
  toolchain. Verify available syntax/effects instead of assuming old examples work.
- Keep source, comments, documentation, and commit messages in English.

## Writing fast Bend

Correct Bend is not fast Bend by default. Measured rules (Bend 2.0.35):

- Indexed, large or hot data (bytes, pixels, coverage, quads) lives in an
  `Array<U32>` (native flat block, ~1 ns/read), not a `List`. Lists are fine
  when tiny, built once and consumed in order. Arrays are affine and cannot be
  fields of `Data` types: keep them local and convert once at the boundary.
- No `do Result`/`do Maybe` binds or callbacks per byte, pixel or glyph: each
  bind is a closure (45% of a measured profile). Thread state through one
  recursive def that matches on the result.
- `||`, `&&` and `Bool.pick` evaluate both sides; use `match` to stop early.
- Never `Array.clone` or append (`List.append`) in a loop; build with a
  reversed accumulator or a tail parameter.
- A parameter that a def only matches or passes to itself is borrowed (no
  refcount); descend trees with the selector as a parameter.
- Keep non-recursive records small (they are passed flattened; the widest one
  widens every call frame). Box big ones with an `Alias{x: T}` constructor.
- Split independent, balanced work of tens of µs or more with a parallel call
  (`a b = f(l) g(r)`); never parallelize tiny or IO-bound work.
- Measure before and after on the same input; print a result before the next
  `IO.now()`.

Here: font bytes are read through the word tree with borrowed reads and
characters through the Latin-1 table; keep both. Outline parsing in
`glyf.bend` still binds per point and appends per contour: known debt on the
glyph-miss path, do not extend it.

## Linux first

The initial goal is excellent behavior on Ian's actual Linux development machine:
correct results with the fonts installed there, stability, measured performance,
and a finished user experience. Inspect the effective environment before
choosing integrations.

Build compatibility layers as the project progresses, after visible, well-made
Linux results. Do not let speculative Windows or macOS abstractions delay local
quality. Introduce abstractions from concrete needs.

## Working practice

- Preserve existing work and keep the library's boundary clear. Syllo, Dithra,
  Mokko, and Auvia import Runika by relative path; coordinate API changes with them.
- Favor simple, maintainable code. Pursue fast, polished behavior with evidence.
- Run the native checks after changes. When parsing changes, compare against an
  independent reference (see `tools/`) on real fonts, not only synthetic data.
- Compilation is not proof of correctness. Tests and reference comparisons are
  evidence for the declared subset. State partial support and unverified
  behavior explicitly.
- Build sequentially. Do not impose virtual-address limits on the Bend runtime
  or suppress crash reporting. Investigate failures before retrying.
- Keep generated binaries, logs, crash dumps, credentials, font files, and
  machine-specific evidence out of Git. Stage explicit paths and preserve
  concurrent changes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for validation commands.
