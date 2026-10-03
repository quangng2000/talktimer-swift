// The mathematical statement is true; the Swift execution can overflow.
//@ verify
//@ requires first >= 0 && second >= 0
//@ ensures \result == first + second
//@ ensures \result >= 0
func unboundedTotal(_ first: Int, _ second: Int) -> Int {
  return first + second
}
