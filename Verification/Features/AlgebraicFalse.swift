// Negative control: valid Swift and valid translation, but a false contract.
// Any .recorded(seconds: 5, enabled: true) is a counterexample.
enum ClaimedLap {
  case reset
  case recorded(seconds: Int, enabled: Bool)
}

//@ verify
//@ ensures \result == 0
func incorrectlyEraseLap(_ lap: ClaimedLap) -> Int {
  switch lap {
  case .reset: return 0
  case .recorded(let seconds, let enabled): return enabled ? seconds : 0
  }
}
