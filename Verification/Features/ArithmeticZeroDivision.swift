// Both models must reject the missing nonzero-divisor requirement.
//@ verify
//@ requires divisor >= 0
func unsafeDivision(_ divisor: Int) -> Int {
  return 100 / divisor
}
