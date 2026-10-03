// This is valid Swift syntax and supported translation, but nonnegative
// individual durations alone cannot prove that their sum fits Swift.Int.
//@ verify
//@ requires first >= 0 && second >= 0
//@ ensures \result >= 0
func selectedTotal(_ first: Int, _ second: Int) -> Int {
  return first + second
}
