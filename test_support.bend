import Base
import ./bytes.bend as B
import ./font.bend as F
import ./glyf.bend as G

def view(xs: List<&2, U32>) -> B.View:
  Result.default(&2, &2, String, B.View, B.from_bytes(xs), B.View{B.Byte{0}, 0n, 0, 0})

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
