import Base
import ./bytes.bend as B
import ./font.bend as F
import ../Splina/path.bend as P

type RawPoint is Data:
  RawPoint{x: F32, y: F32, on: Bool}

type FlagStep is Data:
  FlagStep{flag: U32, position: U32, repeat: U32}

type Flags is Data:
  Flags{values: List<&2, U32>, position: U32}

type Delta is Data:
  Delta{value: F32, position: U32}

type Axis is Data:
  Axis{values: List<&2, F32>, position: U32}

type Component is Data:
  Component{glyph: U32, dx: F32, dy: F32, xx: F32, xy: F32, yx: F32, yy: F32}

type Glyph is Data:
  Simple{contours: List<&2, List<&2, RawPoint>>}
  Composite{components: List<&2, Component>}

def end_points(n: Nat, +v: B.View, +i: U32, +previous: U32) -> Result<&2, &2, String, List<&2, U32>>:
  match n:
    case 0n:
      Done{Nil{}}
    case 1n+p:
      do Result<&2, &2, String, List<&2, U32>>:
        +end : U32 <- B.u16(v, (10 + (i * 2) : U32))
        ok : Unit <- B.require(Bool.and(U32.is_lt(end, 4096), Bool.or(U32.is_eq(i, 0), U32.is_gt(end, previous))), "invalid or oversized contour endpoints")
        rest : List<&2, U32> <- end_points(p, v, (i + 1 : U32), end)
        return Con{end, rest}

def last_count(xs: List<&2, U32>, default: U32) -> U32:
  match xs:
    case Nil{}:
      default
    case Con{h, t}:
      last_count(t, (h + 1 : U32))

def repeat_byte(repeated: Bool, v: B.View, pos: U32) -> Result<&2, &2, String, U32>:
  match repeated:
    case False{}:
      Done{0}
    case True{}:
      B.byte(v, pos)

def read_flag(reuse: Bool, +v: B.View, +pos: U32, remaining: U32, last: U32) -> Result<&2, &2, String, FlagStep>:
  match reuse:
    case True{}:
      Done{FlagStep{last, pos, (remaining - 1 : U32)}}
    case False{}:
      do Result<&2, &2, String, FlagStep>:
        +flag : U32 <- B.byte(v, pos)
        ok : Unit <- B.require(Bool.not(B.flag(flag, 128)), "reserved simple glyph flag")
        +repeated : Bool = B.flag(flag, 8)
        count : U32 <- repeat_byte(repeated, v, (pos + 1 : U32))
        return FlagStep{flag, (pos + 1 + Bool.to_u32(repeated) : U32), count}

def flag_value(s: FlagStep) -> U32:
  match s:
    case FlagStep{f, p, r}:
      f

def flag_position(s: FlagStep) -> U32:
  match s:
    case FlagStep{f, p, r}:
      p

def flag_repeat(s: FlagStep) -> U32:
  match s:
    case FlagStep{f, p, r}:
      r

def flags_prepend(f: U32, r: Flags) -> Flags:
  match r:
    case Flags{xs, pos}:
      Flags{Con{f, xs}, pos}

def read_flags(n: Nat, +v: B.View, +pos: U32, +remaining: U32, last: U32) -> Result<&2, &2, String, Flags>:
  match n:
    case 0n:
      do Result<&2, &2, String, Flags>:
        ok : Unit <- B.require(U32.is_eq(remaining, 0), "flag repeat exceeds point count")
        return Flags{Nil{}, pos}
    case 1n+p:
      do Result<&2, &2, String, Flags>:
        +step : FlagStep <- read_flag(U32.is_gt(remaining, 0), v, pos, remaining, last)
        tail : Flags <- read_flags(p, v, flag_position(step), flag_repeat(step), flag_value(step))
        return flags_prepend(flag_value(step), tail)

def coordinate(short: Bool, +same: Bool, +v: B.View, +pos: U32) -> Result<&2, &2, String, Delta>:
  match short same:
    case True{} _:
      do Result<&2, &2, String, Delta>:
        +n : U32 <- B.byte(v, pos)
        return Delta{Bool.pick(F32, same, U32.to_f32(n), F32.neg(U32.to_f32(n))), (pos + 1 : U32)}
    case False{} True{}:
      Done{Delta{0.0, pos}}
    case False{} False{}:
      do Result<&2, &2, String, Delta>:
        n : F32 <- B.i16(v, pos)
        return Delta{n, (pos + 2 : U32)}

def delta_value(d: Delta) -> F32:
  match d:
    case Delta{x, p}:
      x

def delta_position(d: Delta) -> U32:
  match d:
    case Delta{x, p}:
      p

def axis_prepend(x: F32, r: Axis) -> Axis:
  match r:
    case Axis{xs, pos}:
      Axis{Con{x, xs}, pos}

def read_axis(flags: List<&2, U32>, +v: B.View, pos: U32, prev: F32, +short_mask: U32, +same_mask: U32) -> Result<&2, &2, String, Axis>:
  match flags:
    case Nil{}:
      Done{Axis{Nil{}, pos}}
    case Con{+f, rest}:
      do Result<&2, &2, String, Axis>:
        +d : Delta <- coordinate(B.flag(f, short_mask), B.flag(f, same_mask), v, pos)
        +x : F32 = (prev + delta_value(d) : F32)
        ok : Unit <- B.require(Bool.and(F32.is_ge(x, F32.neg(32768.0)), F32.is_le(x, 32767.0)), "glyph coordinate overflow")
        tail : Axis <- read_axis(rest, v, delta_position(d), x, short_mask, same_mask)
        return axis_prepend(x, tail)

def axis_values(a: Axis) -> List<&2, F32>:
  match a:
    case Axis{xs, pos}:
      xs

def axis_position(a: Axis) -> U32:
  match a:
    case Axis{xs, pos}:
      pos

def points(flags: List<&2, U32>, xs: List<&2, F32>, ys: List<&2, F32>) -> List<&2, RawPoint>:
  match flags xs ys:
    case Con{f, fs} Con{x, xt} Con{y, yt}:
      Con{RawPoint{x, y, B.flag(f, 1)}, points(fs, xt, yt)}
    case _ _ _:
      Nil{}

def split_contours(ends: List<&2, U32>, +pts: List<&2, RawPoint>, previous: U32) -> List<&2, List<&2, RawPoint>>:
  match ends:
    case Nil{}:
      Nil{}
    case Con{+end, tail}:
      +count = U32.to_nat((end + 1 - previous : U32))
      Con{List.take(&2, RawPoint, pts, count), split_contours(tail, List.drop(&2, RawPoint, pts, count), (end + 1 : U32))}

def simple_axes(+v: B.View, ends: List<&2, U32>, f: Flags) -> Result<&2, &2, String, Glyph>:
  match f:
    case Flags{+flags, pos}:
      do Result<&2, &2, String, Glyph>:
        +x : Axis <- read_axis(flags, v, pos, 0.0, 2, 16)
        y : Axis <- read_axis(flags, v, axis_position(x), 0.0, 4, 32)
        return Simple{split_contours(ends, points(flags, axis_values(x), axis_values(y)), 0)}

def simple(nonempty: Bool, +v: B.View, +count: U32) -> Result<&2, &2, String, Glyph>:
  match nonempty:
    case False{}:
      Done{Simple{Nil{}}}
    case True{}:
      do Result<&2, &2, String, Glyph>:
        ok : Unit <- B.require(U32.is_le(count, 256), "glyph exceeds 256 contour limit")
        +ends : List<&2, U32> <- end_points(U32.to_nat(count), v, 0, 0)
        +ip : U32 = (10 + (count * 2) : U32)
        +ilen : U32 <- B.u16(v, ip)
        instructions : B.View <- B.slice(v, (ip + 2 : U32), ilen)
        f : Flags <- read_flags(U32.to_nat(last_count(ends, 0)), v, (ip + 2 + ilen : U32), 0, 0)
        simple_axes(v, ends, f)

def arg(words: Bool, v: B.View, pos: U32) -> Result<&2, &2, String, F32>:
  match words:
    case True{}:
      B.i16(v, pos)
    case False{}:
      do Result<&2, &2, String, F32>:
        x : U32 <- B.byte(v, pos)
        return B.signed(x, 256)

type Matrix is Data:
  Matrix{xx: F32, xy: F32, yx: F32, yy: F32, position: U32}

def f2dot14(v: B.View, p: U32) -> Result<&2, &2, String, F32>:
  do Result<&2, &2, String, F32>:
    x : F32 <- B.i16(v, p)
    return (x / 16384.0 : F32)

def matrix(scale: Bool, xy: Bool, full: Bool, +v: B.View, +pos: U32) -> Result<&2, &2, String, Matrix>:
  match scale xy full:
    case False{} False{} False{}:
      Done{Matrix{1.0, 0.0, 0.0, 1.0, pos}}
    case True{} False{} False{}:
      do Result<&2, &2, String, Matrix>:
        +s : F32 <- f2dot14(v, pos)
        return Matrix{s, 0.0, 0.0, s, (pos + 2 : U32)}
    case False{} True{} False{}:
      do Result<&2, &2, String, Matrix>:
        x : F32 <- f2dot14(v, pos)
        y : F32 <- f2dot14(v, (pos + 2 : U32))
        return Matrix{x, 0.0, 0.0, y, (pos + 4 : U32)}
    case False{} False{} True{}:
      do Result<&2, &2, String, Matrix>:
        xx : F32 <- f2dot14(v, pos)
        yx : F32 <- f2dot14(v, (pos + 2 : U32))
        xy : F32 <- f2dot14(v, (pos + 4 : U32))
        yy : F32 <- f2dot14(v, (pos + 6 : U32))
        return Matrix{xx, xy, yx, yy, (pos + 8 : U32)}
    case _ _ _:
      Fail{"conflicting composite transform flags"}

def matrix_position(m: Matrix) -> U32:
  match m:
    case Matrix{xx, xy, yx, yy, pos}:
      pos

def component(gid: U32, +dx: F32, +dy: F32, +scaled: Bool, m: Matrix) -> Component:
  match m:
    case Matrix{+xx, +xy, +yx, +yy, pos}:
      Component{gid, Bool.pick(F32, scaled, ((xx * dx) + (xy * dy) : F32), dx),
        Bool.pick(F32, scaled, ((yx * dx) + (yy * dy) : F32), dy), xx, xy, yx, yy}

def instruction_tail(present: Bool, +v: B.View, +pos: U32) -> Result<&2, &2, String, Unit>:
  match present:
    case False{}:
      Done{Unit{}}
    case True{}:
      do Result<&2, &2, String, Unit>:
        n : U32 <- B.u16(v, pos)
        bytes : B.View <- B.slice(v, (pos + 2 : U32), n)
        return Unit{}

def components(fuel: Nat, more: Bool, +v: B.View, +pos: U32, +instructions: Bool) -> Result<&2, &2, String, List<&2, Component>>:
  match fuel more:
    case _ False{}:
      do Result<&2, &2, String, List<&2, Component>>:
        ok : Unit <- instruction_tail(instructions, v, pos)
        return Nil{}
    case 0n True{}:
      Fail{"glyph exceeds 64 component limit"}
    case 1n+p True{}:
      do Result<&2, &2, String, List<&2, Component>>:
        +flags : U32 <- B.u16(v, pos)
        gid : U32 <- B.u16(v, (pos + 2 : U32))
        ok : Unit <- B.require(B.flag(flags, 2), "unsupported composite point attachment (XY arguments required)")
        ok2 : Unit <- B.require(U32.is_eq(U32.and(flags, 57360), 0), "reserved composite flags")
        ok3 : Unit <- B.require(Bool.not(Bool.and(B.flag(flags, 2048), B.flag(flags, 4096))), "conflicting component offset flags")
        +words : Bool = B.flag(flags, 1)
        +stride : U32 = Bool.pick(U32, words, 2, 1)
        dx : F32 <- arg(words, v, (pos + 4 : U32))
        dy : F32 <- arg(words, v, (pos + 4 + stride : U32))
        +m : Matrix <- matrix(B.flag(flags, 8), B.flag(flags, 64), B.flag(flags, 128), v, (pos + 4 + (stride * 2) : U32))
        tail : List<&2, Component> <- components(p, B.flag(flags, 32), v, matrix_position(m), Bool.or(instructions, B.flag(flags, 256)))
        return Con{component(gid, dx, dy, B.flag(flags, 2048), m), tail}

def parse_body(composite: Bool, +v: B.View, +count: U32) -> Result<&2, &2, String, Glyph>:
  match composite:
    case False{}:
      simple(U32.is_gt(count, 0), v, count)
    case True{}:
      do Result<&2, &2, String, Glyph>:
        cs : List<&2, Component> <- components(64n, True{}, v, 10, False{})
        return Composite{cs}

def parse(empty: Bool, +v: B.View) -> Result<&2, &2, String, Glyph>:
  match empty:
    case True{}:
      Done{Simple{Nil{}}}
    case False{}:
      do Result<&2, &2, String, Glyph>:
        +count : U32 <- B.u16(v, 0)
        xmin : F32 <- B.i16(v, 2)
        ymin : F32 <- B.i16(v, 4)
        xmax : F32 <- B.i16(v, 6)
        ymax : F32 <- B.i16(v, 8)
        ok : Unit <- B.require(Bool.and(F32.is_le(xmin, xmax), F32.is_le(ymin, ymax)), "invalid glyph bounding box")
        parse_body(U32.is_ge(count, 32768), v, count)

def transform_point(c: Component, pt: RawPoint) -> RawPoint:
  match c pt:
    case Component{gid, dx, dy, xx, xy, yx, yy} RawPoint{+x, +y, on}:
      RawPoint{((xx * x) + (xy * y) + dx : F32), ((yx * x) + (yy * y) + dy : F32), on}

def transform_points(pts: List<&2, RawPoint>, +c: Component) -> List<&2, RawPoint>:
  match pts:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{transform_point(c, h), transform_points(t, c)}

def transform_contours(cs: List<&2, List<&2, RawPoint>>, +c: Component) -> List<&2, List<&2, RawPoint>>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{transform_points(h, c), transform_contours(t, c)}

# A single recursive tree walk avoids mutual recursion. Work items include
# their accumulated transform. Both work length and depth are bounded by fuel.
type Work is Data:
  Work{glyph: U32, depth: U32, transform: Component}

def compose(a: Component, b: Component) -> Component:
  match a b:
    case Component{ga, +ax, +ay, +axx, +axy, +ayx, +ayy} Component{gb, +bx, +by, +bxx, +bxy, +byx, +byy}:
      Component{gb, ((axx * bx) + (axy * by) + ax : F32), ((ayx * bx) + (ayy * by) + ay : F32),
        ((axx * bxx) + (axy * byx) : F32), ((axx * bxy) + (axy * byy) : F32),
        ((ayx * bxx) + (ayy * byx) : F32), ((ayx * bxy) + (ayy * byy) : F32)}

def component_id(c: Component) -> U32:
  match c:
    case Component{gid, dx, dy, xx, xy, yx, yy}:
      gid

def add_work(cs: List<&2, Component>, +depth: U32, +parent: Component, rest: List<&2, Work>) -> List<&2, Work>:
  match cs:
    case Nil{}:
      rest
    case Con{+c, t}:
      Con{Work{component_id(c), depth, compose(parent, c)}, add_work(t, depth, parent, rest)}

type Expanded is Data:
  Expanded{work: List<&2, Work>, contours: List<&2, List<&2, RawPoint>>}

def expand_step(g: Glyph, depth: U32, +transform: Component, work: List<&2, Work>, acc: List<&2, List<&2, RawPoint>>) -> Expanded:
  match g:
    case Simple{cs}:
      Expanded{work, List.append(&2, List<&2, RawPoint>, acc, transform_contours(cs, transform))}
    case Composite{cs}:
      Expanded{add_work(cs, (depth + 1 : U32), transform, work), acc}

def expand_work(e: Expanded) -> List<&2, Work>:
  match e:
    case Expanded{w, cs}:
      w

def expand_contours(e: Expanded) -> List<&2, List<&2, RawPoint>>:
  match e:
    case Expanded{w, cs}:
      cs

def total_points(cs: List<&2, List<&2, RawPoint>>, acc: U32) -> U32:
  match cs:
    case Nil{}: acc
    case Con{h, t}: total_points(t, (acc + U32.from_nat(List.length(&2, RawPoint, h)) : U32))

def expansion_budget(+cs: List<&2, List<&2, RawPoint>>) -> Bool:
  Bool.and(U32.is_le(total_points(cs, 0), 8192), U32.is_le(U32.from_nat(List.length(&2, List<&2, RawPoint>, cs)), 256))

def expand(fuel: Nat, work: List<&2, Work>, +font: F.Font, acc: List<&2, List<&2, RawPoint>>) -> Result<&2, &2, String, List<&2, List<&2, RawPoint>>>:
  match fuel work:
    case _ Nil{}:
      Done{acc}
    case 0n Con{h, t}:
      Fail{"composite expansion exceeds 256 glyph visits (cycle or complexity limit)"}
    case 1n+p Con{Work{gid, +depth, transform}, rest}:
      do Result<&2, &2, String, List<&2, List<&2, RawPoint>>>:
        ok : Unit <- B.require(U32.is_le(depth, 16), "composite nesting exceeds 16 (cycle or depth limit)")
        +data : B.View <- F.glyph_data(font, gid)
        g : Glyph <- parse(U32.is_eq(B.length(data), 0), data)
        +e : Expanded = expand_step(g, depth, transform, rest, acc)
        budget : Unit <- B.require(expansion_budget(expand_contours(e)), "expanded glyph exceeds 8192 points or 256 contours")
        expand(p, expand_work(e), font, expand_contours(e))

def raw(font: F.Font, +gid: U32) -> Result<&2, &2, String, List<&2, List<&2, RawPoint>>>:
  expand(256n, Con{Work{gid, 0, Component{gid, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0}}, Nil{}}, font, Nil{})

def position(p: RawPoint) -> P.Point:
  match p:
    case RawPoint{x, y, on}:
      P.Point{x, y}

type Start is Data:
  Start{point: P.Point, rest: List<&2, RawPoint>}

def last_point(xs: List<&2, RawPoint>, last: RawPoint) -> RawPoint:
  match xs:
    case Nil{}:
      last
    case Con{h, t}:
      last_point(t, h)

def start_pick(first: RawPoint, last: RawPoint, +all: List<&2, RawPoint>, tail: List<&2, RawPoint>) -> Start:
  match first last:
    case RawPoint{x, y, True{}} _:
      Start{P.Point{x, y}, tail}
    case RawPoint{x, y, False{}} RawPoint{lx, ly, True{}}:
      Start{P.Point{lx, ly}, List.take(&2, RawPoint, all, U32.to_nat((U32.from_nat(List.length(&2, RawPoint, all)) - 1 : U32)))}
    case RawPoint{x, y, False{}} RawPoint{lx, ly, False{}}:
      Start{P.midpoint(P.Point{x, y}, P.Point{lx, ly}), all}

def start(xs: List<&2, RawPoint>) -> Start:
  match xs:
    case Nil{}:
      Start{P.Point{0.0, 0.0}, Nil{}}
    case Con{+h, +t}:
      start_pick(h, last_point(t, h), Con{h, t}, t)

def edge(pending: Maybe<&2, P.Point>, pt: RawPoint) -> List<&2, P.Segment>:
  match pending pt:
    case None{} RawPoint{x, y, True{}}:
      [P.Line{P.Point{x, y}}]
    case None{} RawPoint{x, y, False{}}:
      Nil{}
    case Some{c} RawPoint{x, y, True{}}:
      [P.Quad{c, P.Point{x, y}}]
    case Some{+c} RawPoint{x, y, False{}}:
      [P.Quad{c, P.midpoint(c, P.Point{x, y})}]

def pending_next(pt: RawPoint) -> Maybe<&2, P.Point>:
  match pt:
    case RawPoint{x, y, True{}}:
      None{}
    case RawPoint{x, y, False{}}:
      Some{P.Point{x, y}}

def close_segment(pending: Maybe<&2, P.Point>, first: P.Point) -> List<&2, P.Segment>:
  match pending:
    case None{}:
      Nil{}
    case Some{c}:
      [P.Quad{c, first}]

def segments(xs: List<&2, RawPoint>, +first: P.Point, pending: Maybe<&2, P.Point>) -> List<&2, P.Segment>:
  match xs:
    case Nil{}:
      close_segment(pending, first)
    case Con{+h, t}:
      List.append(&2, P.Segment, edge(pending, h), segments(t, first, pending_next(h)))

def contour(s: Start) -> List<&2, P.Segment>:
  match s:
    case Start{+point, rest}:
      Con{P.MoveTo{point}, List.append(&2, P.Segment, segments(rest, point, None{}), [P.ClosePath{}])}

def outlines(cs: List<&2, List<&2, RawPoint>>) -> List<&2, P.Segment>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      List.append(&2, P.Segment, contour(start(h)), outlines(t))

# Font design units, y up. Dithra's glyph entry point flips the y axis.
def outline(font: F.Font, gid: U32) -> Result<&2, &2, String, P.Path>:
  do Result<&2, &2, String, P.Path>:
    cs : List<&2, List<&2, RawPoint>> <- raw(font, gid)
    return P.Path{outlines(cs), P.NonZero{}}
