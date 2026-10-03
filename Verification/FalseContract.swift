// The case-study runner must see Dafny reject this false postcondition.
//@ verify
//@ ensures \result == 99
func incorrectDuration(_ duration: Int) -> Int {
  return duration
}
