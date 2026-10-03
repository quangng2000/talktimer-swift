// Bounds avoid overflow; the postcondition itself is deliberately false.
//@ verify
//@ requires first >= 0 && first <= 1000000
//@ requires second >= 0 && second <= 1000000
//@ ensures \result == first - second
func wrongTotal(_ first: Int, _ second: Int) -> Int {
  return first + second
}
