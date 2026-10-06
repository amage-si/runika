import Base

type Tree is Data:
  Byte{value: U32}
  Fork{lo: Tree, hi: Tree}

type View is Data:
  View{tree: Tree, depth: Nat, start: U32, length: U32}

type Built is Data:
  Built{tree: Tree, rest: List<&2, U32>}

def require(ok: Bool, message: String) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{message}

def built_tree(r: Built) -> Tree:
  match r:
    case Built{tree, rest}:
      tree

def built_rest(r: Built) -> List<&2, U32>:
  match r:
    case Built{tree, rest}:
      rest

def build_finish(lo: Tree, r: Built) -> Built:
  match r:
    case Built{hi, tail}:
      Built{Fork{lo, hi}, tail}

def build(+d: Nat, xs: List<&2, U32>) -> Built:
  match d xs:
    case 0n Nil{}:
      Built{Byte{0}, Nil{}}
    case 0n Con{h, t}:
      Built{Byte{h}, t}
    case 1n+p _:
      +r = build(p, xs)
      build_finish(built_tree(r), build(p, built_rest(r)))

def view_build(+d: Nat, n: U32, r: Built) -> View:
  match r:
    case Built{tree, rest}:
      View{tree, d, 0, n}

def count(xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      count(t, (acc + 1 : U32))

def valid_bytes(xs: List<&2, U32>, acc: Bool) -> Bool:
  match xs:
    case Nil{}: acc
    case Con{h, t}: valid_bytes(t, Bool.and(U32.is_le(h, 255), acc))

def from_bytes(+xs: List<&2, U32>) -> Result<&2, &2, String, View>:
  do Result<&2, &2, String, View>:
    +n : U32 = count(xs, 0)
    ok : Unit <- require(U32.is_le(n, 2097152), "font input exceeds 2 MiB limit")
    ok2 : Unit <- require(valid_bytes(xs, True{}), "input contains a value outside byte range")
    +d : Nat = Bool.pick(Nat, U32.is_le(n, 1), 0n, 1n+U32.log2((n - 1 : U32)))
    return view_build(d, n, build(d, xs))

def length(v: View) -> U32:
  match v:
    case View{tree, depth, start, length}:
      length

def in_range(+len: U32, +off: U32, count: U32) -> Bool:
  Bool.and(U32.is_le(off, len), U32.is_le(count, (len - off : U32)))

def slice(v: View, +off: U32, +count: U32) -> Result<&2, &2, String, View>:
  match v:
    case View{tree, depth, start, +len}:
      do Result<&2, &2, String, View>:
        ok : Unit <- require(in_range(len, off, count), "table/record range outside buffer")
        return View{tree, depth, (start + off : U32), count}

# A node at depth 1n+p splits its bytes at 2^p. `half` carries that split
# down the tree, halved at each level, so a read costs O(depth) instead of
# computing U32.pow(2, p) (p multiplications) at every level.
def lookup.go(+d: Nat, tree: Tree, +i: U32, +half: U32) -> U32:
  match d tree:
    case _ Byte{v}:
      v
    case 0n Fork{lo, hi}:
      0
    case 1n+p Fork{lo, hi}:
      lookup.go(p, Bool.pick(Tree, U32.is_lt(i, half), lo, hi), U32.mod(i, half), (half / 2 : U32))

def lookup(+d: Nat, tree: Tree, +i: U32) -> U32:
  lookup.go(d, tree, i, U32.pow(2, Nat.sub(d, 1n)))

def byte(v: View, +off: U32) -> Result<&2, &2, String, U32>:
  match v:
    case View{tree, depth, start, len}:
      do Result<&2, &2, String, U32>:
        ok : Unit <- require(U32.is_lt(off, len), "truncated byte")
        return lookup(depth, tree, (start + off : U32))

def u16(+v: View, +off: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    a : U32 <- byte(v, off)
    b : U32 <- byte(v, (off + 1 : U32))
    return ((a * 256) + b : U32)

def u32(+v: View, +off: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    a : U32 <- u16(v, off)
    b : U32 <- u16(v, (off + 2 : U32))
    return ((a * 65536) + b : U32)

def signed(+v: U32, +modulus: U32) -> F32:
  Bool.pick(F32, U32.is_lt(v, (modulus / 2 : U32)), U32.to_f32(v),
    (U32.to_f32(v) - U32.to_f32(modulus) : F32))

def i16(v: View, off: U32) -> Result<&2, &2, String, F32>:
  do Result<&2, &2, String, F32>:
    n : U32 <- u16(v, off)
    return signed(n, 65536)

def flag(bits: U32, mask: U32) -> Bool:
  U32.is_ne(U32.and(bits, mask), 0)

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
