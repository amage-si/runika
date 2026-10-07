import Base
import ./bytes.bend as B

type Table is Data:
  Table{tag: U32, bytes: B.View}

# The answers of `info` for U+0000..U+00FF (the scalars Syllo lays out),
# computed once when a font is built, as a complete binary tree indexed by
# the code's bits: a character costs eight steps instead of a cmap search
# and an hmtx read. A character the font could not answer (a malformed
# table) is Unknown and goes through the tables again, so it fails with
# the same error it would without the table.
type Latin is Data:
  Known{glyph: U32, advance: F32}
  Unknown{}
  Half{lo: Latin, hi: Latin}

# `checksum` is the head table's checkSumAdjustment: it identifies the font
# file, so caches of derived data can tell fonts apart. `latin` is derived
# from cmap and hmtx (see `with_latin`).
#
# A font travels as one pointer. The Bend 2 compiler passes a record that
# is not recursive flattened, one word per field (25 words here, five of
# them shared trees, each counted on every copy), through every call that
# carries it, and the widest record of a program sets the size of every
# call frame: a flattened font inside an app's model slows every call of
# the app. A recursive type stays boxed, so `Alias` makes Font recursive.
# Nothing builds an Alias; every function answers for the font it wraps.
type Font is Data:
  Font{upem: U32, ascender: F32, descender: F32, line_gap: F32,
    glyph_count: U32, metric_count: U32, long_loca: Bool,
    cmap: B.View, hmtx: B.View, loca: B.View, glyf: B.View,
    checksum: U32, latin: Latin}
  Alias{font: Font}

type Metric is Data:
  Metric{advance: F32, bearing: F32}

# A character's glyph (0 when the font has none) and, for a present glyph,
# its advance in font units.
type Info is Data:
  Info{glyph: U32, advance: F32}

def table_find(ts: List<&2, Table>, +tag: U32) -> Result<&2, &2, String, B.View>:
  match ts:
    case Nil{}:
      Fail{"required TrueType table missing"}
    case Con{Table{key, data}, rest}:
      Bool.pick(Result<&2, &2, String, B.View>, U32.is_eq(key, tag), Done{data}, table_find(rest, tag))

def has_table(ts: List<&2, Table>, +tag: U32) -> Bool:
  match ts:
    case Nil{}: False{}
    case Con{Table{key, data}, rest}: Bool.or(U32.is_eq(key, tag), has_table(rest, tag))

def table_records(n: Nat, +v: B.View, +pos: U32) -> Result<&2, &2, String, List<&2, Table>>:
  match n:
    case 0n:
      Done{Nil{}}
    case 1n+p:
      do Result<&2, &2, String, List<&2, Table>>:
        +tag : U32 <- B.u32(v, pos)
        off : U32 <- B.u32(v, (pos + 8 : U32))
        len : U32 <- B.u32(v, (pos + 12 : U32))
        data : B.View <- B.slice(v, off, len)
        +rest : List<&2, Table> <- table_records(p, v, (pos + 16 : U32))
        ok : Unit <- B.require(Bool.not(has_table(rest, tag)), "duplicate sfnt table tag")
        return Con{Table{tag, data}, rest}

def cmap_candidate(ok: Bool, +v: B.View, +off: U32) -> Result<&2, &2, String, Maybe<&2, B.View>>:
  match ok:
    case False{}:
      Done{None{}}
    case True{}:
      do Result<&2, &2, String, Maybe<&2, B.View>>:
        fmt : U32 <- B.u16(v, off)
        len : U32 <- B.u16(v, (off + 2 : U32))
        sub : B.View <- B.slice(v, off, len)
        return Bool.pick(Maybe<&2, B.View>, U32.is_eq(fmt, 4), Some{sub}, None{})

def cmap_choose(a: Maybe<&2, B.View>, b: Maybe<&2, B.View>) -> Maybe<&2, B.View>:
  match a:
    case Some{x}:
      Some{x}
    case None{}:
      b

def cmap_validate(n: Nat, +v: B.View, +count: U32, +i: U32, +previous: U32) -> Result<&2, &2, String, Unit>:
  match n:
    case 0n:
      B.require(U32.is_eq(previous, 65535), "cmap format 4 missing terminal segment")
    case 1n+p:
      do Result<&2, &2, String, Unit>:
        +end : U32 <- B.u16(v, (14 + (i * 2) : U32))
        +start : U32 <- B.u16(v, (16 + (count * 2) + (i * 2) : U32))
        +at : U32 = (16 + (count * 6) + (i * 2) : U32)
        +range : U32 <- B.u16(v, at)
        ok : Unit <- B.require(Bool.and(U32.is_le(start, end), Bool.or(U32.is_eq(i, 0), U32.is_gt(start, previous))), "unordered or overlapping cmap segments")
        ok2 : Unit <- B.require(U32.is_eq(U32.mod(range, 2), 0), "unaligned cmap glyph array offset")
        +array_start : U32 = (16 + (count * 8) : U32)
        ok3 : Unit <- B.require(Bool.or(U32.is_eq(range, 0), Bool.and(U32.is_ge((at + range : U32), array_start), B.in_range(B.length(v), (at + range : U32), (((end - start + 1) * 2) : U32)))), "cmap glyph array outside subtable")
        cmap_validate(p, v, count, (i + 1 : U32), end)

def cmap_records(n: Nat, +v: B.View, +pos: U32) -> Result<&2, &2, String, Maybe<&2, B.View>>:
  match n:
    case 0n:
      Done{None{}}
    case 1n+p:
      do Result<&2, &2, String, Maybe<&2, B.View>>:
        +platform : U32 <- B.u16(v, pos)
        encoding : U32 <- B.u16(v, (pos + 2 : U32))
        off : U32 <- B.u32(v, (pos + 4 : U32))
        here : Maybe<&2, B.View> <- cmap_candidate(Bool.or(U32.is_eq(platform, 0),
          Bool.and(U32.is_eq(platform, 3), U32.is_eq(encoding, 1))), v, off)
        rest : Maybe<&2, B.View> <- cmap_records(p, v, (pos + 8 : U32))
        return cmap_choose(here, rest)

def cmap_selected(sub: Maybe<&2, B.View>) -> Result<&2, &2, String, B.View>:
  match sub:
    case None{}:
      Fail{"unsupported cmap: Unicode format 4 required"}
    case Some{+v}:
      do Result<&2, &2, String, B.View>:
        +count2 : U32 <- B.u16(v, 6)
        ok : Unit <- B.require(Bool.and(U32.is_gt(count2, 0), U32.is_eq(U32.mod(count2, 2), 0)), "invalid cmap segment count")
        ok2 : Unit <- B.require(B.in_range(B.length(v), 16, (count2 * 4 : U32)), "truncated cmap segments")
        pad : U32 <- B.u16(v, (14 + count2 : U32))
        ok3 : Unit <- B.require(U32.is_eq(pad, 0), "nonzero cmap reserved pad")
        ok4 : Unit <- cmap_validate(U32.to_nat((count2 / 2 : U32)), v, (count2 / 2 : U32), 0, 0)
        return v

def cmap_parse(+v: B.View) -> Result<&2, &2, String, B.View>:
  do Result<&2, &2, String, B.View>:
    ver : U32 <- B.u16(v, 0)
    +n : U32 <- B.u16(v, 2)
    ok : Unit <- B.require(Bool.and(U32.is_eq(ver, 0), U32.is_le(n, 64)), "invalid cmap directory")
    sub : Maybe<&2, B.View> <- cmap_records(U32.to_nat(n), v, 4)
    cmap_selected(sub)

def cmap_glyph(direct: Bool, +v: B.View, +code: U32, start: U32, delta: U32, range: U32, at: U32) -> Result<&2, &2, String, U32>:
  match direct:
    case True{}:
      Done{U32.and((code + delta : U32), 65535)}
    case False{}:
      do Result<&2, &2, String, U32>:
        +raw : U32 <- B.u16(v, (at + range + ((code - start) * 2) : U32))
        return Bool.pick(U32, U32.is_eq(raw, 0), 0, U32.and((raw + delta : U32), 65535))

def cmap_hit(hit: Bool, +v: B.View, code: U32, start: U32, delta: U32, +range: U32, at: U32, tail: U32) -> Result<&2, &2, String, U32>:
  match hit:
    case False{}:
      Done{tail}
    case True{}:
      cmap_glyph(U32.is_eq(range, 0), v, code, start, delta, range, at)

# The glyph of `code` in segment i, or 0 when the segment starts after it
# (code falls between segments).
def cmap_segment(+v: B.View, +count: U32, +i: U32, +code: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +start : U32 <- B.u16(v, (16 + (count * 2) + (i * 2) : U32))
    delta : U32 <- B.u16(v, (16 + (count * 4) + (i * 2) : U32))
    +at : U32 = (16 + (count * 6) + (i * 2) : U32)
    range : U32 <- B.u16(v, at)
    cmap_hit(U32.is_le(start, code), v, code, start, delta, range, at, 0)

def cmap_next(here: Bool, found: Unit -> Result<&2, &2, String, U32>,
  later: Unit -> Result<&2, &2, String, U32>) -> Result<&2, &2, String, U32>:
  match here:
    case True{}:
      found(Unit{})
    case False{}:
      later(Unit{})

# Segments are sorted by end and do not overlap (cmap_validate checks it
# when the font is loaded), so the segment for `code` is the first one that
# ends at or after it: stop there instead of reading every segment.
def cmap_scan(n: Nat, +v: B.View, +count: U32, +i: U32, +code: U32) -> Result<&2, &2, String, U32>:
  match n:
    case 0n:
      Done{0}
    case 1n+p:
      do Result<&2, &2, String, U32>:
        end : U32 <- B.u16(v, (14 + (i * 2) : U32))
        cmap_next(U32.is_ge(end, code), u => cmap_segment(v, count, i, code),
          u => cmap_scan(p, v, count, (i + 1 : U32), code))

# The glyph of `code` read from the cmap (not from the Latin-1 table).
def glyph_id.read(font: Font, +code: U32) -> Result<&2, &2, String, U32>:
  match font:
    case Font{upem, asc, desc, gap, count, metrics, long, +cmap, hmtx, loca, glyf, sum, latin}:
      do Result<&2, &2, String, U32>:
        ok : Unit <- B.require(Bool.and(U32.is_le(code, 65535), Bool.not(Bool.and(U32.is_ge(code, 55296), U32.is_le(code, 57343)))), "cmap4 supports Unicode BMP scalar values only")
        seg2 : U32 <- B.u16(cmap, 6)
        +segs : U32 = (seg2 / 2 : U32)
        +gid : U32 <- cmap_scan(U32.to_nat(segs), cmap, segs, 0, code)
        ok2 : Unit <- B.require(U32.is_lt(gid, count), "cmap glyph id outside maxp")
        return gid
    case Alias{f}:
      glyph_id.read(f, code)

def metric(font: Font, +gid: U32) -> Result<&2, &2, String, Metric>:
  match font:
    case Font{upem, asc, desc, gap, count, +metrics, long, cmap, +hmtx, loca, glyf, sum, latin}:
      do Result<&2, &2, String, Metric>:
        ok : Unit <- B.require(U32.is_lt(gid, count), "glyph id outside maxp")
        adv : U32 <- B.u16(hmtx, (U32.min(gid, (metrics - 1 : U32)) * 4 : U32))
        lsb : F32 <- B.i16(hmtx, Bool.pick(U32, U32.is_lt(gid, metrics), ((gid * 4) + 2 : U32), ((metrics * 4) + ((gid - metrics) * 2) : U32)))
        return Metric{U32.to_f32(adv), lsb}
    case Alias{f}:
      metric(f, gid)

def loca_offset(long: Bool, v: B.View, gid: U32) -> Result<&2, &2, String, U32>:
  match long:
    case True{}:
      B.u32(v, (gid * 4 : U32))
    case False{}:
      do Result<&2, &2, String, U32>:
        n : U32 <- B.u16(v, (gid * 2 : U32))
        return (n * 2 : U32)

def glyph_data(font: Font, +gid: U32) -> Result<&2, &2, String, B.View>:
  match font:
    case Font{upem, asc, desc, gap, count, metrics, +long, cmap, hmtx, +loca, glyf, sum, latin}:
      do Result<&2, &2, String, B.View>:
        ok : Unit <- B.require(U32.is_lt(gid, count), "glyph id outside maxp")
        +a : U32 <- loca_offset(long, loca, gid)
        +b : U32 <- loca_offset(long, loca, (gid + 1 : U32))
        ok2 : Unit <- B.require(U32.is_le(a, b), "descending loca offsets")
        B.slice(glyf, a, (b - a : U32))
    case Alias{f}:
      glyph_data(f, gid)

# The Latin-1 table
# -----------------

def info.metric(r: Result<&2, &2, String, Metric>, +gid: U32) -> Result<&2, &2, String, Info>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{Metric{advance, bearing}}:
      Done{Info{gid, advance}}

def info.glyph(present: Bool, +font: Font, +gid: U32) -> Result<&2, &2, String, Info>:
  match present:
    case False{}:
      Done{Info{0, 0.0}}
    case True{}:
      info.metric(metric(font, gid), gid)

def info.of(r: Result<&2, &2, String, U32>, +font: Font) -> Result<&2, &2, String, Info>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+gid}:
      info.glyph(U32.is_ne(gid, 0), font, gid)

# `code`'s glyph and advance read from the cmap and hmtx tables.
def info.read(+font: Font, +code: U32) -> Result<&2, &2, String, Info>:
  info.of(glyph_id.read(font, code), font)

def latin.leaf(r: Result<&2, &2, String, Info>) -> Latin:
  match r:
    case Fail{e}:
      Unknown{}
    case Done{Info{glyph, advance}}:
      Known{glyph, advance}

# The table for codes start .. start + size - 1 (size = 2^d).
def latin.build(+d: Nat, +start: U32, +size: U32, +font: Font) -> Latin:
  match d:
    case 0n:
      latin.leaf(info.read(font, start))
    case 1n+p:
      +h = (size >> 1n : U32)
      Half{latin.build(p, start, h, font), latin.build(p, (start + h : U32), h, font)}

def latin.set(f: Font, t: Latin) -> Font:
  match f:
    case Font{upem, asc, desc, gap, count, metrics, long, cmap, hmtx, loca, glyf, sum, old}:
      Font{upem, asc, desc, gap, count, metrics, long, cmap, hmtx, loca, glyf, sum, t}
    case Alias{inner}:
      latin.set(inner, t)

# The font with its Latin-1 table computed from its own cmap and hmtx.
# Every font built from tables goes through here; a font whose cmap or
# hmtx is replaced must as well, or its table would answer for the old
# ones.
def with_latin(+font: Font) -> Font:
  latin.set(font, latin.build(8n, 0, 256, font))

# One step down the table: `left` says which side holds i.
def latin.go(n: Nat, left: Bool, lo: Latin, hi: Latin, +i: U32, +half: U32) -> Maybe<&2, Info>:
  match n left lo hi:
    case 0n _ _ _:
      None{}
    case 1n+p True{} Known{g, a} _:
      Some{Info{g, a}}
    case 1n+p True{} Unknown{} _:
      None{}
    case 1n+p True{} Half{x, y} _:
      latin.go(p, U32.is_lt(i, half), x, y, (i .&. (half - 1) : U32), (half >> 1n : U32))
    case 1n+p False{} _ Known{g, a}:
      Some{Info{g, a}}
    case 1n+p False{} _ Unknown{}:
      None{}
    case 1n+p False{} _ Half{x, y}:
      latin.go(p, U32.is_lt(i, half), x, y, (i .&. (half - 1) : U32), (half >> 1n : U32))

def latin.at(t: Latin, +code: U32) -> Maybe<&2, Info>:
  match t:
    case Known{g, a}:
      Some{Info{g, a}}
    case Unknown{}:
      None{}
    case Half{x, y}:
      latin.go(16n, U32.is_lt(code, 128), x, y, (code .&. 127 : U32), 64)

def parse_tables(+ts: List<&2, Table>) -> Result<&2, &2, String, Font>:
  do Result<&2, &2, String, Font>:
    +head : B.View <- table_find(ts, 1751474532)
    +maxp : B.View <- table_find(ts, 1835104368)
    +hhea : B.View <- table_find(ts, 1751672161)
    +hmtx : B.View <- table_find(ts, 1752003704)
    +loca : B.View <- table_find(ts, 1819239265)
    glyf : B.View <- table_find(ts, 1735162214)
    cmap0 : B.View <- table_find(ts, 1668112752)
    cmap : B.View <- cmap_parse(cmap0)
    adjust : U32 <- B.u32(head, 8)
    magic : U32 <- B.u32(head, 12)
    +upem : U32 <- B.u16(head, 18)
    +format : U32 <- B.u16(head, 50)
    glyph_format : U32 <- B.u16(head, 52)
    +asc : F32 <- B.i16(hhea, 4)
    +desc : F32 <- B.i16(hhea, 6)
    +gap : F32 <- B.i16(hhea, 8)
    +metrics : U32 <- B.u16(hhea, 34)
    maxp_version : U32 <- B.u32(maxp, 0)
    +glyphs : U32 <- B.u16(maxp, 4)
    sizes : Unit <- B.require(U32.is_ge(B.length(maxp), 32), "truncated maxp version 1.0")
    lines : Unit <- B.require(F32.is_gt((asc - desc + gap : F32), 0.0), "invalid hhea line metrics")
    ok : Unit <- B.require(Bool.and(U32.is_eq(magic, 1594834165), Bool.and(U32.is_ge(upem, 16), U32.is_le(upem, 16384))), "invalid head magic/unitsPerEm")
    ok2 : Unit <- B.require(Bool.and(U32.is_le(format, 1), U32.is_eq(glyph_format, 0)), "unsupported loca/glyph format")
    ok3 : Unit <- B.require(Bool.and(U32.is_eq(maxp_version, 65536), Bool.and(U32.is_gt(glyphs, 0), Bool.and(U32.is_gt(metrics, 0), U32.is_le(metrics, glyphs)))), "invalid maxp/hhea metrics")
    ok4 : Unit <- B.require(U32.is_ge(B.length(hmtx), ((metrics * 4) + ((glyphs - metrics) * 2) : U32)), "truncated hmtx")
    ok5 : Unit <- B.require(U32.is_ge(B.length(loca), ((glyphs + 1) * Bool.pick(U32, U32.is_eq(format, 1), 4, 2) : U32)), "truncated loca")
    return with_latin(Font{upem, asc, desc, gap, glyphs, metrics, U32.is_eq(format, 1), cmap, hmtx, loca, glyf,
      adjust, Unknown{}})

def parse(+v: B.View) -> Result<&2, &2, String, Font>:
  do Result<&2, &2, String, Font>:
    signature : U32 <- B.u32(v, 0)
    +count : U32 <- B.u16(v, 4)
    ok : Unit <- B.require(U32.is_eq(signature, 65536), "unsupported font: TrueType sfnt 1.0 required (no CFF/WOFF/TTC)")
    ok2 : Unit <- B.require(Bool.and(U32.is_gt(count, 0), U32.is_le(count, 128)), "invalid sfnt table count")
    ts : List<&2, Table> <- table_records(U32.to_nat(count), v, 12)
    parse_tables(ts)

def load_result(r: Result<&2, &2, String, B.View>) -> Result<&2, &2, String, Font>:
  do Result<&2, &2, String, Font>:
    v : B.View <- r
    parse(v)

def load(path: String) -> IO(Result<&2, &2, String, Font>):
  do IO<Result<&2, &2, String, Font>>:
    r : Result<&2, &2, String, B.View> <- B.load(path)
    return load_result(r)

# Characters
# ----------

# The table's answer for `code` (None above U+00FF or when Unknown).
def known.pick(inside: Bool, t: Latin, +code: U32) -> Maybe<&2, Info>:
  match inside:
    case True{}:
      latin.at(t, code)
    case False{}:
      None{}

def known(font: Font, +code: U32) -> Maybe<&2, Info>:
  match font:
    case Font{upem, asc, desc, gap, count, metrics, long, cmap, hmtx, loca, glyf, sum, latin}:
      known.pick(U32.is_lt(code, 256), latin, code)
    case Alias{f}:
      known(f, code)

def info.known(m: Maybe<&2, Info>, +font: Font, +code: U32) -> Result<&2, &2, String, Info>:
  match m:
    case Some{i}:
      Done{i}
    case None{}:
      info.read(font, code)

# `code`'s glyph (0 when the font has none) and, when present, its advance
# in font units: from the Latin-1 table when it knows the answer, else from
# the cmap and hmtx tables (same results and errors either way).
def info(+font: Font, +code: U32) -> Result<&2, &2, String, Info>:
  info.known(known(font, code), font, code)

def glyph_id.known(m: Maybe<&2, Info>, +font: Font, +code: U32) -> Result<&2, &2, String, U32>:
  match m:
    case Some{Info{g, a}}:
      Done{g}
    case None{}:
      glyph_id.read(font, code)

# The glyph of `code` (0 when the font has none).
def glyph_id(+font: Font, +code: U32) -> Result<&2, &2, String, U32>:
  glyph_id.known(known(font, code), font, code)

# Accessors
# ---------

def units(font: Font) -> U32:
  match font:
    case Font{upem, asc, desc, gap, count, metrics, long, cmap, hmtx, loca, glyf, sum, latin}:
      upem
    case Alias{f}:
      units(f)

def ascender(font: Font) -> F32:
  match font:
    case Font{upem, asc, desc, gap, count, metrics, long, cmap, hmtx, loca, glyf, sum, latin}:
      asc
    case Alias{f}:
      ascender(f)

def descender(font: Font) -> F32:
  match font:
    case Font{upem, asc, desc, gap, count, metrics, long, cmap, hmtx, loca, glyf, sum, latin}:
      desc
    case Alias{f}:
      descender(f)

def line_gap(font: Font) -> F32:
  match font:
    case Font{upem, asc, desc, gap, count, metrics, long, cmap, hmtx, loca, glyf, sum, latin}:
      gap
    case Alias{f}:
      line_gap(f)

def checksum(font: Font) -> U32:
  match font:
    case Font{upem, asc, desc, gap, count, metrics, long, cmap, hmtx, loca, glyf, sum, latin}:
      sum
    case Alias{f}:
      checksum(f)
