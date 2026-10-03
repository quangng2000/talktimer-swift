// Reference lapsValid/histInv use Array.every; Swift uses allSatisfy.
//@ verify
//@ pure
func nonnegative(_ value: Int) -> Bool { return value >= 0 }

//@ verify
//@ ensures \result == forall(i, 0 <= i && i < values.count ==> values[i] >= 0)
func validDurations(_ values: [Int]) -> Bool {
  return values.allSatisfy(nonnegative)
}
