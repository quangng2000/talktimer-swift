// Negative control: the datatype is inhabited, but the function does not descend.
// Do not execute this function; its intended outcome is a Dafny termination error.
indirect enum NonterminatingPlan {
  case done
  case segment(seconds: Int, remainder: NonterminatingPlan)
}

//@ verify
func neverFinish(_ plan: NonterminatingPlan) -> NonterminatingPlan {
  return neverFinish(plan)
}
