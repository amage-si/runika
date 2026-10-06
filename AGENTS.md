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
