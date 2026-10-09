# Changelog

All notable changes to Runika are recorded here. Runika follows
[semantic versioning](https://semver.org) in its 0.x form: while the API is
experimental, a minor version (0.2.0) may change it in breaking ways and a
patch version (0.1.1) only fixes. Runika is built from source together with its
sibling AMAGE libraries; the set of versions tested together is listed in
[eco-build's releases](https://github.com/amage-si/eco-build/tree/main/releases).

## [0.1.0] - 2026-10-09

First tagged release, tested with Bend 2.0.35 on Linux (X11/XWayland) as part
of AMAGE Eco 0.1.0.

### Included

- TrueType 1.0 tables (`head`, `maxp`, `hhea`, `hmtx`, `loca`, `glyf`)
  validated on load.
- `cmap` format 4 with a Latin-1 fast table and a binary search for the rest
  of the BMP.
- Simple and composite glyph outlines as Splina paths.
- Font identity for caches of derived data.
- 60 native checks; outlines match fontTools on all 4908 points of Latin-1 in
  Liberation Sans.

[0.1.0]: https://github.com/amage-si/runika/releases/tag/v0.1.0
