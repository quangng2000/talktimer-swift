// Negative control: Swift accepts this source, but the value may be absent.
// Expected outcome: translation succeeds and Dafny rejects the unwrap safety
// obligation. Do not add a non-nil precondition; the failure is the experiment.

//@ verify
//@ ensures \result == (elapsed ?? 0)
func unsafeRequiredElapsed(_ elapsed: Int?) -> Int {
  return elapsed!
}
