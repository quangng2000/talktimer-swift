// The real Lap has section: String and tags: [String]. Even reading its Int
// duration needs a model for every stored field of that reachable record.
struct Lap {
  let duration: Int
  let section: String
}

//@ verify
//@ ensures \result == lap.duration
func readDuration(_ lap: Lap) -> Int {
  return lap.duration
}
