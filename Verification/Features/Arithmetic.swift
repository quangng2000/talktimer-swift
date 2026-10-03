// Run this unchanged source under both integer models.

//@ verify
//@ requires first >= 0 && first <= 1000000
//@ requires second >= 0 && second <= 1000000
//@ ensures \result == first + second
//@ ensures \result >= 0
func boundedTotal(_ first: Int, _ second: Int) -> Int {
  return first + second
}

// Swift division truncates toward zero, including in mathematical mode.
//@ verify
//@ ensures \result == -2
func negativeQuotient() -> Int {
  return -7 / 3
}

//@ verify
//@ ensures \result == -1
func negativeRemainder() -> Int {
  return -7 % 3
}

// Contract arithmetic is mathematical even with checked execution. Nothing
// executes `value + 1` here; this contract also covers the runtime Int.max.
//@ verify
//@ ensures \result == value
//@ ensures \result < value + 1
func specificationArithmetic(_ value: Int) -> Int {
  return value
}
