// Small controls for the verifier installation. These are not a substitute
// for the real TalkTimerCore model, which contains strings and richer updates.
struct LapRecord {
  let duration: Int
}

//@ verify
//@ ensures \result.duration >= 0
//@ ensures duration >= 0 ==> \result.duration == duration
func clampedLap(_ duration: Int) -> LapRecord {
  return LapRecord(duration: duration >= 0 ? duration : 0)
}

enum ClockAction {
  case setTime(Int)
  case keepTime
}

//@ verify
//@ requires current >= 0
//@ ensures \result >= current
func advanceClock(_ current: Int, _ action: ClockAction) -> Int {
  switch action {
  case .setTime(let time): return time >= current ? time : current
  case .keepTime: return current
  }
}

//@ verify
//@ requires start >= 0 && start <= end
//@ ensures \result == end - start
//@ ensures \result >= 0
func lapDuration(_ start: Int, _ end: Int) -> Int {
  return end - start
}

//@ verify
//@ pure
//@ requires index >= 0 && index < values.count
//@ ensures \result.count == values.count
func setAt<T>(_ values: [T], _ index: Int, _ value: T) -> [T] {
  var result = values
  result[index] = value
  return result
}

//@ verify
//@ pure
//@ requires index >= 0 && index < values.count
//@ ensures \result.count == values.count - 1
func removeAt<T>(_ values: [T], _ index: Int) -> [T] {
  var result = values
  result.remove(at: index)
  return result
}
