import Base
import ../font.bend as F
import ../glyf.bend as G
import ../../Splina/path.bend as P

def describe_outline(o: P.Path) -> U32:
  match o:
    case P.Path{cs, rule}:
      U32.from_nat(List.length(&2, P.Segment, cs))

def probe(+f: F.Font) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +gid : U32 <- F.glyph_id(f, 227)
    o : P.Path <- G.outline(f, gid)
    return "U+00E3 glyph=" ++ U32.show(gid) ++ " path_commands=" ++ U32.show(describe_outline(o))

def report(r: Result<&2, &2, String, String>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{s}:
      IO.print(s)

def loaded(r: Result<&2, &2, String, F.Font>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{f}:
      report(probe(f))

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    loaded(r)
