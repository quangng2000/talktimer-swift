// Translation-boundary probe: Optional.map is explicitly unsupported by the
// pinned toolchain. Swift should typecheck this; LemmaSwift should refuse it
// before verification. Keep the ordinary Swift implementation intact.

//@ verify
//@ ensures \result == elapsed
func mappedElapsed(_ elapsed: Int?) -> Int? {
  return elapsed.map { seconds in seconds }
}
