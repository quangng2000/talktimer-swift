// Optional timer state, isolated from TalkTimer's unsupported String fields.
// Every selected function has an explicit behavioral contract. No assumptions
// or skipped proof obligations are used. Int bounds are selected by the runner.

struct OptionalTimerSnapshot {
  let elapsedSeconds: Int
  let targetSeconds: Int?
}

struct OptionalTimerSession {
  let snapshot: OptionalTimerSnapshot?
}

// A returned Int is implicitly promoted to a present Optional<Int>.
//@ verify
//@ ensures \result != nil
//@ ensures (\result ?? 0) == seconds
func optionalElapsed(_ seconds: Int) -> Int? {
  return seconds
}

// The standard initializer is a second construction route.
//@ verify
//@ ensures \result != nil
//@ ensures (\result ?? 0) == seconds
func initializedElapsed(_ seconds: Int) -> Int? {
  return Optional(seconds)
}

// No saved preference (nil) differs from a saved "no target" (Some(nil)).
//@ verify
//@ ensures \result == nil
func missingSavedTarget() -> Int?? {
  return nil
}

//@ verify
//@ ensures \result != nil
//@ ensures (\result ?? nil) == nil
func savedUnlimitedTarget() -> Int?? {
  return .some(nil)
}

// Wrapping an optional adds a level, including when the inner value is nil.
//@ verify
//@ ensures \result != nil
//@ ensures (\result ?? nil) == target
func saveTargetChoice(_ target: Int?) -> Int?? {
  return Optional(target)
}

//@ verify
//@ ensures \result == (target ?? defaultSeconds)
func targetFromBinding(_ target: Int?, _ defaultSeconds: Int) -> Int {
  if let target {
    return target
  }
  return defaultSeconds
}

//@ verify
//@ ensures \result == (elapsed ?? 0)
func elapsedFromGuard(_ elapsed: Int?) -> Int {
  guard let elapsed else { return 0 }
  return elapsed
}

// The denominator is deliberately unrestricted: a present target must prevent
// evaluation of the fallback, even when the fallback would divide by zero.
//@ verify
//@ ensures \result == 60
func presentTargetSkipsFallback(_ divisor: Int) -> Int {
  let target: Int? = 60
  return target ?? (120 / divisor)
}

//@ verify
//@ ensures \result == (snapshot == nil ? nil : snapshot!.elapsedSeconds)
func chainedElapsed(_ snapshot: OptionalTimerSnapshot?) -> Int? {
  return snapshot?.elapsedSeconds
}

// The optional field is flattened in the usual Swift chaining sense: a
// missing snapshot and a snapshot with no target both give an absent Int.
//@ verify
//@ ensures \result == (snapshot == nil ? nil : snapshot!.targetSeconds)
func chainedTarget(_ snapshot: OptionalTimerSnapshot?) -> Int? {
  return snapshot?.targetSeconds
}

//@ verify
//@ ensures (session == nil) ==> \result == nil
//@ ensures (session != nil && session!.snapshot == nil) ==> \result == nil
//@ ensures (session != nil && session!.snapshot != nil) ==> \result == session!.snapshot!.elapsedSeconds
func chainedSessionElapsed(_ session: OptionalTimerSession?) -> Int? {
  return session?.snapshot?.elapsedSeconds
}

//@ verify
//@ ensures \result == (elapsed ?? 0)
func elapsedFromOptionalPattern(_ elapsed: Int?) -> Int {
  switch elapsed {
  case let seconds?: return seconds
  case nil: return 0
  }
}

// Presence is an explicit caller premise; it is not a runtime check inserted
// into this function. OptionalUnsafe.swift deliberately omits the premise.
//@ verify
//@ requires elapsed != nil
//@ ensures \result == (elapsed ?? 0)
func requiredElapsed(_ elapsed: Int?) -> Int {
  return elapsed!
}

// IUO remains optional for the nil test, then unwraps when Int is required.
//@ verify
//@ ensures \result == (elapsed ?? 0)
func implicitlyUnwrappedElapsed(_ elapsed: Int?) -> Int {
  let cached: Int! = elapsed
  if cached == nil { return 0 }
  let seconds: Int = cached
  return seconds
}

// while-let binds afresh each iteration. The positive condition makes the
// decrement safe, while the variant proves termination for idealized integers.
//@ verify
//@ requires (remaining ?? 0) >= 0
//@ ensures \result == 0
func drainOptionalCountdown(_ remaining: Int?) -> Int {
  var current = remaining
  //@ invariant (current ?? 0) >= 0
  //@ decreases current ?? 0
  while let seconds = current, seconds > 0 {
    current = seconds - 1
  }
  return current ?? 0
}
