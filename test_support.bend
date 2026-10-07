import Base
import ./bytes.bend as B
import ./font.bend as F
import ./glyf.bend as G

def view(xs: List<&2, U32>) -> B.View:
  Result.default(&2, &2, String, B.View, B.from_bytes(xs), B.View{B.Word{0}, 0, 0, 0})

def be16(+n: U32) -> List<&2, U32>:
  [(n / 256 : U32), U32.mod(n, 256)]

def be32(+n: U32) -> List<&2, U32>:
  [U32.mod((n / 16777216 : U32), 256), U32.mod((n / 65536 : U32), 256), U32.mod((n / 256 : U32), 256), U32.mod(n, 256)]

def append(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, a, b)

def triangle() -> List<&2, U32>:
  [0,1, 0,0, 0,0, 0,10, 0,10, 0,2, 0,0, 1,1,1,
   0,0, 0,10, 255,246, 0,0, 0,0, 0,10]

def synthetic(+data: B.View, loca: B.View) -> F.Font:
  F.Font{1000, 800.0, F32.neg(200.0), 0.0, 2, 2, True{},
    data, view([1,244,0,0, 1,244,0,0]), loca, data}

def raw_glyph(bytes: List<&2, U32>) -> Result<&2, &2, String, G.Glyph>:
  +v = view(bytes)
  G.parse(U32.is_eq(B.length(v), 0), v)

def contour_count(cs: List<&2, List<&2, G.RawPoint>>) -> U32:
  U32.from_nat(List.length(&2, List<&2, G.RawPoint>, cs))

def point_count(cs: List<&2, List<&2, G.RawPoint>>) -> U32:
  match cs:
    case Nil{}: 0
    case Con{h, t}: (U32.from_nat(List.length(&2, G.RawPoint, h)) + point_count(t) : U32)

def cmap4(+range: U32, glyph: U32) -> B.View:
  view(append([0,4,0,34,0,0,0,4,0,4,0,1,0,0,
    0,65,255,255,0,0,0,65,255,255,0,1,0,1],append(be16(range),append([0,0],be16(glyph)))))

def with_cmap(font: F.Font, cmap: B.View) -> F.Font:
  match font:
    case F.Font{upem,asc,desc,gap,count,metrics,long,old,hmtx,loca,glyf}:
      F.Font{upem,asc,desc,gap,count,metrics,long,cmap,hmtx,loca,glyf}

# Byte reads at every offset of a buffer of n bytes 0, 37, 74, ... (mod
# 256) agree with the values they should read.
def pattern(n: Nat, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      U32.mod((i * 37 + 11 : U32), 256) <> pattern(p, (i + 1 : U32))

def at(+i: U32) -> U32:
  U32.mod((i * 37 + 11 : U32), 256)

def ok_byte(r: Result<&2, &2, String, U32>, +v: U32) -> Bool:
  match r:
    case Fail{e}:
      False{}
    case Done{x}:
      U32.is_eq(x, v)

def failed(r: Result<&2, &2, String, U32>) -> Bool:
  match r:
    case Fail{e}:
      True{}
    case Done{x}:
      False{}

# Every byte, u16 and u32 read of a view of n bytes (offset 0 .. n + 1):
# in range they read the pattern, past the end they fail.
def reads(k: Nat, +v: B.View, +n: U32, +i: U32) -> Bool:
  match k:
    case 0n:
      True{}
    case 1n+p:
      +b = Bool.pick(Bool, U32.is_lt(i, n), ok_byte(B.byte(v, i), at(i)), failed(B.byte(v, i)))
      +h = Bool.pick(Bool, U32.is_lt((i + 1 : U32), n), ok_byte(B.u16(v, i), (at(i) * 256 + at((i + 1 : U32)) : U32)),
        failed(B.u16(v, i)))
      +w = Bool.pick(Bool, U32.is_lt((i + 3 : U32), n),
        ok_byte(B.u32(v, i), (((at(i) * 256 + at((i + 1 : U32))) * 256 + at((i + 2 : U32))) * 256 + at((i + 3 : U32)) : U32)),
        failed(B.u32(v, i)))
      b && h && w && reads(p, v, n, (i + 1 : U32))

def all_reads(k: Nat, +n: U32) -> Bool:
  match k:
    case 0n:
      True{}
    case 1n+p:
      reads(U32.to_nat((n + 2 : U32)), view(pattern(U32.to_nat(n), 0)), n, 0) && all_reads(p, (n + 1 : U32))

# Reads inside a slice start at the slice and stop at its end.
def slice_reads(r: Result<&2, &2, String, B.View>) -> Bool:
  match r:
    case Fail{e}:
      False{}
    case Done{+v}:
      ok_byte(B.u32(v, 0), (((at(5) * 256 + at(6)) * 256 + at(7)) * 256 + at(8) : U32)) &&
        ok_byte(B.u16(v, 5), (at(10) * 256 + at(11) : U32)) && failed(B.u16(v, 6)) && failed(B.byte(v, 7))

# Table checksums (the sum of a table's big-endian words, the bytes past its
# end counting as zero; head without its checkSumAdjustment) against the
# directory: every word of every table read through the byte tree.
def tail_word(+v: B.View, +off: U32, +left: U32) -> U32:
  +b0 = Result.default(&2, &2, String, U32, B.byte(v, off), 0)
  +b1 = Bool.pick(U32, U32.is_gt(left, 1), Result.default(&2, &2, String, U32, B.byte(v, (off + 1 : U32)), 0), 0)
  +b2 = Bool.pick(U32, U32.is_gt(left, 2), Result.default(&2, &2, String, U32, B.byte(v, (off + 2 : U32)), 0), 0)
  (((b0 * 256 + b1) * 256 + b2) * 256 : U32)

def words_sum(n: Nat, +v: B.View, +off: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      words_sum(p, v, (off + 4 : U32), (acc + Result.default(&2, &2, String, U32, B.u32(v, off), 0) : U32))

def table_sum(+v: B.View, +tag: U32, +off: U32, +len: U32) -> U32:
  +full = (len / 4 : U32)
  +rest = (len - full * 4 : U32)
  +sum = words_sum(U32.to_nat(full), v, off, 0)
  +tail = Bool.pick(U32, U32.is_eq(rest, 0), 0, tail_word(v, (off + full * 4 : U32), rest))
  +adjust = Bool.pick(U32, U32.is_eq(tag, 1751474532), Result.default(&2, &2, String, U32, B.u32(v, (off + 8 : U32)), 0), 0)
  (sum + tail - adjust : U32)

def checksums(n: Nat, +v: B.View, +i: U32) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      +at = (12 + i * 16 : U32)
      +tag = Result.default(&2, &2, String, U32, B.u32(v, at), 0)
      +want = Result.default(&2, &2, String, U32, B.u32(v, (at + 4 : U32)), 1)
      +off = Result.default(&2, &2, String, U32, B.u32(v, (at + 8 : U32)), 0)
      +len = Result.default(&2, &2, String, U32, B.u32(v, (at + 12 : U32)), 0)
      U32.is_eq(table_sum(v, tag, off, len), want) && checksums(p, v, (i + 1 : U32))

def all_checksums(r: Result<&2, &2, String, B.View>) -> Bool:
  match r:
    case Fail{e}:
      False{}
    case Done{+v}:
      +n = Result.default(&2, &2, String, U32, B.u16(v, 4), 0)
      U32.is_gt(n, 0) && checksums(U32.to_nat(n), v, 0)
