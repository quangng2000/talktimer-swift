// The TypeScript reference uses s.slice(1) throughout its recursive helpers.
//@ verify
//@ requires values.count > 0
//@ ensures \result.count == values.count - 1
func remaining(_ values: [Int]) -> [Int] {
  return Array(values.dropFirst())
}
