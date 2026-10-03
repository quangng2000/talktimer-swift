// The TypeScript reference appends using [...a, ...b].
//@ verify
//@ requires first.count < 1000 && second.count < 1000
//@ ensures \result.count == first.count + second.count
func appendLaps(_ first: [Int], _ second: [Int]) -> [Int] {
  return first + second
}
