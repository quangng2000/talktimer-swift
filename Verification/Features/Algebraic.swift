// Focused algebraic-value probes, not a proof of the application's reducer.
// Each selected function is translated from Swift; there are no trusted helpers.

struct PlannedLap {
  let seconds: Int
  let enabled: Bool
}

struct PlannedTalk {
  let opening: PlannedLap
  let closing: PlannedLap
}

struct TalkCopies {
  let original: PlannedTalk
  let replacement: PlannedTalk
}

// A sum whose nonempty cases contain different products.
enum PlanEvent {
  case reset
  case revised(talk: PlannedTalk, selected: Bool, revision: Int)
  case history([PlannedTalk])
}

//@ verify
//@ pure
func eventOpeningSeconds(_ event: PlanEvent) -> Int {
  switch event {
  case .reset: return 0
  case .revised(let talk, let selected, _):
    return selected ? talk.opening.seconds : 0
  case .history(let talks):
    return talks.count > 0 ? talks[0].opening.seconds : 0
  }
}

//@ verify
//@ ensures \result.opening.seconds == opening
//@ ensures \result.closing.seconds == closing
//@ ensures \result.opening.enabled
//@ ensures !\result.closing.enabled
func makePlannedTalk(_ opening: Int, _ closing: Int) -> PlannedTalk {
  PlannedTalk(
    opening: PlannedLap(seconds: opening, enabled: true),
    closing: PlannedLap(seconds: closing, enabled: false)
  )
}

// Whole-value replacement must not change the original nested product.
//@ verify
//@ ensures \result.original.opening.seconds == talk.opening.seconds
//@ ensures \result.replacement.opening.seconds == replacement
//@ ensures \result.replacement.closing.seconds == talk.closing.seconds
func copyPlannedTalk(_ talk: PlannedTalk, _ replacement: Int) -> TalkCopies {
  var copy = talk
  copy = PlannedTalk(
    opening: PlannedLap(seconds: replacement, enabled: copy.opening.enabled),
    closing: copy.closing
  )
  return TalkCopies(original: talk, replacement: copy)
}

//@ verify
//@ ensures eventOpeningSeconds(\result) == (selected ? talk.opening.seconds : 0)
func revisePlan(_ talk: PlannedTalk, _ selected: Bool, _ revision: Int) -> PlanEvent {
  .revised(talk: talk, selected: selected, revision: revision)
}

// Distinct associated values keep their declaration order and types.
//@ verify
//@ ensures \result == revision
func revisionRoundTrip(_ talk: PlannedTalk, _ selected: Bool, _ revision: Int) -> Int {
  let event = PlanEvent.revised(talk: talk, selected: selected, revision: revision)
  switch event {
  case .revised(let received, let enabled, let number):
    //@ assert received.opening.seconds == talk.opening.seconds
    //@ assert enabled == selected
    return number
  default: return 0
  }
}

//@ verify
//@ ensures \result.count == 2
//@ ensures eventOpeningSeconds(\result[0]) == 0
//@ ensures eventOpeningSeconds(\result[1]) == talk.opening.seconds
func replaceEventCopy(_ talk: PlannedTalk) -> [PlanEvent] {
  let event = PlanEvent.history([talk])
  var events = [event, event]
  events[0] = .reset
  return events
}

// Whole-enum indirection: a finite list, not a cyclic reference graph.
indirect enum SegmentPlan {
  case done
  case segment(lap: PlannedLap, remainder: SegmentPlan)
}

//@ verify
//@ pure
func planIsDone(_ plan: SegmentPlan) -> Bool {
  switch plan {
  case .done: return true
  case .segment: return false
  }
}

//@ verify
//@ ensures !planIsDone(\result)
func prependSegment(_ lap: PlannedLap, _ rest: SegmentPlan) -> SegmentPlan {
  .segment(lap: lap, remainder: rest)
}

// Dafny infers structural descent through the recursive payload.
// There is no assume, decreases axiom, or integer-sized length precondition.
//@ verify
//@ ensures planIsDone(\result)
func finishPlan(_ plan: SegmentPlan) -> SegmentPlan {
  switch plan {
  case .done: return .done
  case .segment(_, let remainder): return finishPlan(remainder)
  }
}

// Arrays provide legal recursive storage and an empty finite base value.
struct AgendaGroup {
  let lap: PlannedLap
  let children: [AgendaGroup]
}

//@ verify
//@ ensures \result.lap.seconds == seconds
//@ ensures \result.children.count == 0
func agendaLeaf(_ seconds: Int) -> AgendaGroup {
  AgendaGroup(lap: PlannedLap(seconds: seconds, enabled: true), children: [])
}

//@ verify
//@ ensures \result.children.count == 1
//@ ensures \result.children[0].lap.seconds == child.lap.seconds
//@ ensures \result.children[0].children.count == child.children.count
func agendaParent(_ child: AgendaGroup) -> AgendaGroup {
  AgendaGroup(lap: PlannedLap(seconds: 0, enabled: false), children: [child])
}

// Mutual record/enum recursion, with case-level rather than whole-enum indirect.
struct AgendaStep {
  let lap: PlannedLap
  let tail: AgendaTail
}

enum AgendaTail {
  case end
  indirect case next(AgendaStep)
}

//@ verify
//@ pure
func agendaIsDone(_ agenda: AgendaTail) -> Bool {
  switch agenda {
  case .end: return true
  case .next: return false
  }
}

//@ verify
//@ ensures !agendaIsDone(\result)
func prependAgenda(_ lap: PlannedLap, _ tail: AgendaTail) -> AgendaTail {
  .next(AgendaStep(lap: lap, tail: tail))
}

//@ verify
//@ ensures agendaIsDone(\result)
func finishAgenda(_ agenda: AgendaTail) -> AgendaTail {
  switch agenda {
  case .end: return .end
  case .next(let step): return finishAgenda(step.tail)
  }
}
