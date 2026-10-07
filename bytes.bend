import Base

# Font bytes as a complete binary tree of 32-bit words, four bytes per
# leaf, big-endian (byte k of a word is bits 31-8k down to 24-8k), so the
# tree has a quarter of the nodes one byte per leaf would need. A read
# descends one branch per level with a comparison, a mask and a shift; it
# only borrows the tree (no reference counting), and a 16- or 32-bit field
# that sits inside one word costs a single descent.
#
# Why not a flat array: Bend 2.0.35 compiles `Array<U32>` to a native
# block with O(1) reads, but an Array is affine (a `Type`): it cannot be a
# field of a `Data` type, and `+` (sharing) needs `Data`. Fonts are `Data`
# values that the siblings copy freely and keep in their models, so a flat
# array would make every font, model and text call affine. See
# docs/api.md for the measurements behind this choice.

type Tree is Data:
  Word{value: U32}
  Fork{lo: Tree, hi: Tree}

# A window [start, start + length) over the bytes of `tree`. The root of
# `tree` splits its word indices at `half` (a power of two; 0 when the tree
# is a single word).
type View is Data:
  View{tree: Tree, half: U32, start: U32, length: U32}

def require(ok: Bool, message: String) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{message}

# Building
# --------
#
# One pass consumes the byte list (it is never shared, so each cell is freed
# as it is read): the bytes become word leaves, in order, ending with their
# count and whether each was a byte; then each level pairs neighbours,
# padding an odd end with a zero subtree, until one tree remains. The tree
# is the complete tree of 2^d words a top-down build would make.

def word4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  ((a << 24n) .|. (b << 16n) .|. (c << 8n) .|. d : U32)

type Leaves is Data:
  More{leaf: Tree, rest: Leaves}
  End{count: U32, bytes: Bool}

def is_byte(+b: U32) -> Bool:
  U32.is_le(b, 255)

def leaves(xs: List<&2, U32>, +count: U32, +ok: Bool) -> Leaves:
  match xs:
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}:
      More{Word{word4(a, b, c, d)}, leaves(rest, (count + 4 : U32),
        ok && is_byte(a) && is_byte(b) && is_byte(c) && is_byte(d))}
    case Con{+a, Con{+b, Con{+c, Nil{}}}}:
      More{Word{word4(a, b, c, 0)}, End{(count + 3 : U32), ok && is_byte(a) && is_byte(b) && is_byte(c)}}
    case Con{+a, Con{+b, Nil{}}}:
      More{Word{word4(a, b, 0, 0)}, End{(count + 2 : U32), ok && is_byte(a) && is_byte(b)}}
    case Con{+a, Nil{}}:
      More{Word{word4(a, 0, 0, 0)}, End{(count + 1 : U32), ok && is_byte(a)}}
    case Nil{}:
      End{count, ok}

# One level up: neighbours become forks; an odd last tree gets `zero`.
def pairs(ls: Leaves, +zero: Tree) -> Leaves:
  match ls:
    case More{a, More{b, rest}}:
      More{Fork{a, b}, pairs(rest, zero)}
    case More{a, End{n, ok}}:
      More{Fork{a, zero}, End{n, ok}}
    case End{n, ok}:
      End{n, ok}

type Built is Data:
  Built{tree: Tree, half: U32, count: U32, bytes: Bool}

# Pairs levels until one tree remains; `zero` is a zero subtree as tall as
# this level's trees, and `half` the split of a tree one level up (so a
# lone tree at this level splits at half / 2).
def levels(n: Nat, ls: Leaves, +zero: Tree, +half: U32) -> Built:
  match n ls:
    case _ End{count, ok}:
      Built{Word{0}, 0, count, ok}
    case _ More{t, End{count, ok}}:
      Built{t, (half >> 1n : U32), count, ok}
    case 0n More{a, More{b, rest}}:
      Built{Word{0}, 0, 0, False{}}
    case 1n+p More{a, More{b, rest}}:
      levels(p, pairs(More{a, More{b, rest}}, zero), Fork{zero, zero}, (half << 1n : U32))

def checked(r: Built) -> Result<&2, &2, String, View>:
  match r:
    case Built{tree, +half, +n, ok}:
      do Result<&2, &2, String, View>:
        size : Unit <- require(U32.is_le(n, 2097152), "font input exceeds 2 MiB limit")
        bytes : Unit <- require(ok, "input contains a value outside byte range")
        return View{tree, half, 0, n}

def from_bytes(xs: List<&2, U32>) -> Result<&2, &2, String, View>:
  checked(levels(64n, leaves(xs, 0, True{}), Word{0}, 1))

# Reading
# -------

def length(v: View) -> U32:
  match v:
    case View{tree, half, start, length}:
      length

def in_range(+len: U32, +off: U32, count: U32) -> Bool:
  Bool.and(U32.is_le(off, len), U32.is_le(count, (len - off : U32)))

def slice.checked(ok: Bool, t: Tree, +half: U32, +start: U32, +count: U32) -> Result<&2, &2, String, View>:
  match ok:
    case True{}:
      Done{View{t, half, start, count}}
    case False{}:
      Fail{"table/record range outside buffer"}

def slice(v: View, +off: U32, +count: U32) -> Result<&2, &2, String, View>:
  match v:
    case View{tree, half, start, +len}:
      slice.checked(in_range(len, off, count), tree, half, (start + off : U32), count)

# One step down: `left` says which side of the fork holds word i; `half`
# splits the chosen side. Both sides are only borrowed.
def word.go(n: Nat, left: Bool, lo: Tree, hi: Tree, +i: U32, +half: U32) -> U32:
  match n left lo hi:
    case 0n _ _ _:
      0
    case 1n+p True{} Word{v} _:
      v
    case 1n+p True{} Fork{a, b} _:
      word.go(p, U32.is_lt(i, half), a, b, (i .&. (half - 1) : U32), (half >> 1n : U32))
    case 1n+p False{} _ Word{v}:
      v
    case 1n+p False{} _ Fork{a, b}:
      word.go(p, U32.is_lt(i, half), a, b, (i .&. (half - 1) : U32), (half >> 1n : U32))

# Word i of a tree whose root splits at `half`.
def word(t: Tree, +half: U32, +i: U32) -> U32:
  match t:
    case Word{v}:
      v
    case Fork{a, b}:
      word.go(32n, U32.is_lt(i, half), a, b, (i .&. (half - 1) : U32), (half >> 1n : U32))

# Byte a (absolute) of the tree.
def byte_at(t: Tree, +half: U32, +a: U32) -> U32:
  ((word(t, half, (a >> 2n : U32)) >> U32.to_nat(((3 - (a .&. 3)) * 8 : U32))) .&. 255 : U32)

def u16.split(inside: Bool, +t: Tree, +half: U32, +a: U32) -> U32:
  match inside:
    case True{}:
      ((word(t, half, (a >> 2n : U32)) >> U32.to_nat(((2 - (a .&. 3)) * 8 : U32))) .&. 65535 : U32)
    case False{}:
      (((word(t, half, (a >> 2n : U32)) .&. 255) << 8n) .|. (word(t, half, ((a >> 2n) + 1 : U32)) >> 24n) : U32)

# Bytes a and a + 1 (absolute) as a big-endian 16-bit value.
def u16_at(t: Tree, +half: U32, +a: U32) -> U32:
  u16.split(U32.is_ne((a .&. 3 : U32), 3), t, half, a)

def u32.split(aligned: Bool, +t: Tree, +half: U32, +a: U32) -> U32:
  match aligned:
    case True{}:
      word(t, half, (a >> 2n : U32))
    case False{}:
      +s = ((a .&. 3) * 8 : U32)
      ((word(t, half, (a >> 2n : U32)) << U32.to_nat(s)) .|.
        (word(t, half, ((a >> 2n) + 1 : U32)) >> U32.to_nat((32 - s : U32))) : U32)

# Bytes a .. a + 3 (absolute) as a big-endian 32-bit value.
def u32_at(t: Tree, +half: U32, +a: U32) -> U32:
  u32.split(U32.is_eq((a .&. 3 : U32), 0), t, half, a)

def byte.read(ok: Bool, t: Tree, +half: U32, +a: U32) -> Result<&2, &2, String, U32>:
  match ok:
    case True{}:
      Done{byte_at(t, half, a)}
    case False{}:
      Fail{"truncated byte"}

def byte(v: View, +off: U32) -> Result<&2, &2, String, U32>:
  match v:
    case View{tree, half, start, len}:
      byte.read(U32.is_lt(off, len), tree, half, (start + off : U32))

def u16.read(ok: Bool, t: Tree, +half: U32, +a: U32) -> Result<&2, &2, String, U32>:
  match ok:
    case True{}:
      Done{u16_at(t, half, a)}
    case False{}:
      Fail{"truncated byte"}

# Every in-range offset of a view is below 2 MiB, so off + 1 and off + 3
# cannot wrap once off is in range.
def u16(v: View, +off: U32) -> Result<&2, &2, String, U32>:
  match v:
    case View{tree, half, start, +len}:
      u16.read(U32.is_lt(off, len) && U32.is_lt((off + 1 : U32), len), tree, half, (start + off : U32))

def u32.read(ok: Bool, t: Tree, +half: U32, +a: U32) -> Result<&2, &2, String, U32>:
  match ok:
    case True{}:
      Done{u32_at(t, half, a)}
    case False{}:
      Fail{"truncated byte"}

def u32(v: View, +off: U32) -> Result<&2, &2, String, U32>:
  match v:
    case View{tree, half, start, +len}:
      u32.read(U32.is_lt(off, len) && U32.is_lt((off + 3 : U32), len), tree, half, (start + off : U32))

def signed(+v: U32, +modulus: U32) -> F32:
  Bool.pick(F32, U32.is_lt(v, (modulus / 2 : U32)), U32.to_f32(v),
    (U32.to_f32(v) - U32.to_f32(modulus) : F32))

def i16.of(r: Result<&2, &2, String, U32>) -> Result<&2, &2, String, F32>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+n}:
      Done{signed(n, 65536)}

def i16(v: View, off: U32) -> Result<&2, &2, String, F32>:
  i16.of(u16(v, off))

def flag(bits: U32, mask: U32) -> Bool:
  U32.is_ne(U32.and(bits, mask), 0)

# Loading
# -------

def read_result(r: Result<&1, &1, U32 & String, List<&2, U32>>) -> Result<&2, &2, String, View>:
  match r:
    case Fail{Tuple{code, message}}: Fail{message}
    case Done{xs}: from_bytes(xs)

def load_finish(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Result<&2, &2, String, View>):
  (file, result) = r
  do IO<Result<&2, &2, String, View>>:
    File.close(file)
    return read_result(result)

def load_open(r: Result<&1, &1, U32 & String, File>) -> IO(Result<&2, &2, String, View>):
  match r:
    case Fail{Tuple{code, message}}:
      IO.pure(Result<&2, &2, String, View>, Fail{message})
    case Done{file}:
      do IO<Result<&2, &2, String, View>>:
        read : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 2097153)
        load_finish(read)

def load(path: String) -> IO(Result<&2, &2, String, View>):
  do IO<Result<&2, &2, String, View>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    load_open(opened)
