import Base
import ../font.bend as F
import ../glyf.bend as G
import ../check.bend as C

def point(p: G.RawPoint) -> String:
  match p:
    case G.RawPoint{x, y, on}:
      "[" ++ F32.show(x) ++ "," ++ F32.show(y) ++ "," ++ U32.show(Bool.to_u32(on)) ++ "]"

def points(ps: List<&2, G.RawPoint>, +sep: String) -> String:
  match ps:
    case Nil{}: ""
    case Con{p, rest}: sep ++ point(p) ++ points(rest, ",")

def contours(cs: List<&2, List<&2, G.RawPoint>>, +sep: String) -> String:
  match cs:
    case Nil{}: ""
    case Con{h, t}: sep ++ "[" ++ points(h, "") ++ "]" ++ contours(t, ",")

def record(cp: U32, gid: U32, m: F.Metric, raw: List<&2, List<&2, G.RawPoint>>) -> String:
  match m:
    case F.Metric{advance, bearing}:
      "[" ++ U32.show(cp) ++ "," ++ U32.show(gid) ++ "," ++ F32.show(advance) ++ "," ++ F32.show(bearing) ++ ",[" ++ contours(raw, "") ++ "]]"

def dump(n: Nat, +font: F.Font, +cp: U32) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        +gid : U32 <- C.unwrap(U32, F.glyph_id(font, cp))
        m : F.Metric <- C.unwrap(F.Metric, F.metric(font, gid))
        raw : List<&2, List<&2, G.RawPoint>> <- C.unwrap(List<&2, List<&2, G.RawPoint>>, G.raw(font, gid))
        IO.print(record(cp, gid, m, raw))
        dump(p, font, (cp + 1 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    fr : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- C.unwrap(F.Font, fr)
    dump(95n, font, 32)
    dump(96n, font, 160)
