// The natural Swift equivalent of TypeScript {...m, currentTime: time}.
struct Clock {
  var currentTime: Int
}

//@ verify
//@ ensures \result.currentTime == time
func setTime(_ clock: Clock, _ time: Int) -> Clock {
  var next = clock
  next.currentTime = time
  return next
}
