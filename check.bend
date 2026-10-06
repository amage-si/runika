import Base

def expect(ok: Bool, +label: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("PASS " ++ label)
    case False{}: IO.die(Unit, 1, "FAIL " ++ label)

def is_fail(-A: Data, r: Result<&2, &2, String, A>) -> Bool:
  match r:
    case Fail{e}: True{}
    case Done{v}: False{}

def is_done(-A: Data, r: Result<&2, &2, String, A>) -> Bool:
  Bool.not(is_fail(A, r))

def unwrap(-A: Data, r: Result<&2, &2, String, A>) -> IO(A):
  match r:
    case Fail{e}: IO.die(A, 1, e)
    case Done{v}: IO.pure(A, v)

def near(a: F32, b: F32) -> Bool:
  F32.is_lt(F32.abs((a - b : F32)), 0.0001)
