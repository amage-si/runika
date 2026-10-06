import Base
import ./bytes.bend as B
import ./font.bend as F
import ./glyf.bend as G
import ./check.bend as C
import ./test_support.bend as T
import ../Splina/path.bend as P

def font_metrics(f: F.Font) -> Bool:
  match f:
    case F.Font{upem, asc, desc, gap, count, metrics, long, cmap, hmtx, loca, glyf}:
      Bool.and(U32.is_eq(upem, 2048), Bool.and(C.near(asc, 1854.0), Bool.and(C.near(desc, F32.neg(434.0)), Bool.and(C.near(gap, 67.0), U32.is_eq(count, 2620)))))

def metric_matches(m: F.Metric, a: F32, b: F32) -> Bool:
  match m:
    case F.Metric{adv, lsb}: Bool.and(C.near(adv, a), C.near(lsb, b))

def transformed(cs: List<&2,List<&2,G.RawPoint>>) -> Bool:
  match cs:
    case Con{Con{G.RawPoint{x0,y0,True{}},Con{G.RawPoint{x1,y1,True{}},Con{G.RawPoint{x2,y2,True{}},Nil{}}}},Nil{}}:
      Bool.and(C.near(x0,3.0),Bool.and(C.near(y0,F32.neg(2.0)),Bool.and(C.near(x1,8.0),Bool.and(C.near(y1,F32.neg(2.0)),Bool.and(C.near(x2,3.0),C.near(y2,3.0))))))
    case _: False{}

def real_test(+font: F.Font, +cp: U32, +expected: U32, contours: U32, points: U32, adv: F32, lsb: F32) -> IO(Unit):
  do IO<Unit>:
    +gid : U32 <- C.unwrap(U32, F.glyph_id(font, cp))
    C.expect(U32.is_eq(gid, expected), "reference cmap " ++ U32.show(cp))
    metric : F.Metric <- C.unwrap(F.Metric, F.metric(font, gid))
    C.expect(metric_matches(metric, adv, lsb), "reference metrics " ++ U32.show(cp))
    +raw : List<&2, List<&2, G.RawPoint>> <- C.unwrap(List<&2, List<&2, G.RawPoint>>, G.raw(font, gid))
    C.expect(Bool.and(U32.is_eq(T.contour_count(raw), contours), U32.is_eq(T.point_count(raw), points)), "reference contours/points " ++ U32.show(cp))

def main() -> IO(Unit):
  do IO<Unit>:
    C.expect(C.is_fail(B.View, B.from_bytes([256])), "non-byte input rejected")
    C.expect(C.is_fail(U32, B.u16(T.view([1]), 0)), "truncated u16")
    C.expect(C.is_fail(U32, B.u32(T.view([1,2,3]), 0)), "truncated u32")
    C.expect(C.is_fail(U32, B.byte(T.view([1]), 4294967295)), "huge byte offset")
    C.expect(C.is_fail(B.View, B.slice(T.view([1,2]), 4294967295, 8)), "overflowing slice")
    C.expect(C.is_done(B.View, B.slice(T.view([1,2]), 2, 0)), "empty slice at end")
    C.expect(C.is_fail(F.Font, F.parse(T.view(Nil{}))), "empty font")
    C.expect(C.is_fail(F.Font, F.parse(T.view([79,84,84,79,0,0,0,0,0,0,0,0]))), "CFF signature rejected")
    C.expect(C.is_fail(F.Font, F.parse(T.view([0,1,0,0,0,129,0,0,0,0,0,0]))), "oversized directory")
    C.expect(C.is_fail(F.Font, F.parse(T.view([0,1,0,0,0,1,0,0,0,0,0,0]))), "truncated directory")
    C.expect(C.is_fail(F.Font, F.parse(T.view([0,1,0,0,0,1,0,0,0,0,0,0, 104,101,97,100,0,0,0,0, 255,255,255,255,0,0,0,54]))), "table offset outside file")
    C.expect(C.is_done(G.Glyph, T.raw_glyph(T.triangle())), "simple triangle glyph")
    C.expect(C.is_done(G.Glyph, T.raw_glyph([0,1,0,0,0,0,0,0,0,0,0,2,0,0,57,2])), "valid repeated flags with zero coordinate deltas")
    C.expect(C.is_fail(G.Glyph, T.raw_glyph(List.take(&2, U32, T.triangle(), 28n))), "truncated coordinate stream")
    C.expect(C.is_fail(G.Glyph, T.raw_glyph([0,1,0,0,0,0,0,1,0,1,0,2,0,0,9,3])), "repeat exceeds point count")
    C.expect(C.is_fail(G.Glyph, T.raw_glyph([0,1,0,0,0,0,0,1,0,1,0,2,0,10])), "truncated instruction stream")
    C.expect(C.is_fail(G.Glyph, T.raw_glyph([255,255,0,0,0,0,0,1,0,1,0,0,0,0,0,0])), "composite point attachment unsupported")
    C.expect(C.is_fail(G.Glyph, T.raw_glyph([255,255,0,0,0,0,0,1,0,1,0,74,0,0,0,0])), "conflicting composite transforms")
    +cycle : F.Font = T.synthetic(T.view([255,255,0,0,0,0,0,1,0,1,0,2,0,0,0,0]), T.view([0,0,0,0,0,0,0,16,0,0,0,16]))
    C.expect(C.is_fail(List<&2, List<&2, G.RawPoint>>, G.raw(cycle, 0)), "composite cycle terminates with error")
    C.expect(C.is_fail(B.View, F.glyph_data(T.synthetic(T.view(T.triangle()), T.view([0,0,0,8,0,0,0,1,0,0,0,29])), 0)), "descending loca rejected")
    C.expect(C.is_fail(B.View, F.glyph_data(T.synthetic(T.view(T.triangle()), T.view([0,0,0,0,0,0,1,0,0,0,1,0])), 0)), "loca beyond glyf rejected")
    +transfont : F.Font = T.synthetic(T.view(T.append(T.triangle(),[255,255,0,0,255,254,0,10,0,10,16,10,0,0,3,254,32,0])), T.view([0,0,0,0,0,0,0,29,0,0,0,47]))
    transformed_raw : List<&2,List<&2,G.RawPoint>> <- C.unwrap(List<&2,List<&2,G.RawPoint>>,G.raw(transfont,1))
    C.expect(transformed(transformed_raw), "composite signed byte translation and F2Dot14 scale")
    C.expect(C.is_done(B.View,F.cmap_selected(Some{T.cmap4(4,6)})), "cmap glyph array valid")
    C.expect(C.is_fail(B.View,F.cmap_selected(Some{T.cmap4(3,6)})), "cmap glyph array odd offset rejected")
    C.expect(C.is_fail(B.View,F.cmap_selected(Some{T.cmap4(2,6)})), "cmap glyph array before array start rejected")
    C.expect(C.is_fail(B.View,F.cmap_selected(Some{T.cmap4(100,6)})), "cmap glyph array out of bounds rejected")
    missing : Result<&2, &2, String, F.Font> <- F.load("missing/does-not-exist.ttf")
    C.expect(C.is_fail(F.Font, missing), "missing file returns error without process abort")
    fr : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- C.unwrap(F.Font, fr)
    C.expect(font_metrics(font), "fontTools header reference")
    idrange : U32 <- C.unwrap(U32,F.glyph_id(T.with_cmap(font,T.cmap4(4,6)),65))
    C.expect(U32.is_eq(idrange,7), "cmap idRangeOffset applies delta to nonzero glyph")
    absent : U32 <- C.unwrap(U32,F.glyph_id(T.with_cmap(font,T.cmap4(4,0)),65))
    C.expect(U32.is_eq(absent,0), "cmap idRangeOffset preserves missing glyph zero")
    real_test(font, 32, 3, 0, 0, 569.0, 0.0)
    real_test(font, 65, 36, 2, 17, 1366.0, 4.0)
    real_test(font, 227, 165, 3, 73, 1139.0, 87.0)
    real_test(font, 231, 169, 2, 45, 1024.0, 87.0)
    real_test(font, 233, 171, 3, 32, 1139.0, 87.0)
    real_test(font, 250, 188, 2, 33, 1139.0, 139.0)
    C.expect(C.is_fail(F.Metric, F.metric(font, 2620)), "glyph id upper bound")
    C.expect(C.is_fail(U32, F.glyph_id(font, 128512)), "non-BMP format4 unsupported")
    C.expect(C.is_fail(U32, F.glyph_id(font, 55296)), "surrogate scalar rejected")
    IO.print("Runika tests complete")
