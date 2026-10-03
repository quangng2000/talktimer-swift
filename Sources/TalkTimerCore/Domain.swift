// Swift port of talktimer-lemmascript/src/domain.ts.
// Durations and timestamps are integral milliseconds. Inputs and aggregate sums
// must fit Swift.Int (and JavaScript's safe-integer range for cross-language
// comparisons). This port does not claim equivalent behavior for fractional
// numbers, NaN, infinity, overflow, or canonically equivalent Unicode spellings:
// Swift String equality follows canonical equivalence, unlike JavaScript.
// Verification annotations state the reference contracts; an annotation alone
// is not evidence that LemmaSwift can translate or prove the whole domain.

public struct Lap {
  public var timestamp: Int
  public var duration: Int
  public var section: String
  public var selected: Bool
  public var expectedDuration: Int
  public var tags: [String]

  public init(timestamp: Int, duration: Int, section: String, selected: Bool,
    expectedDuration: Int, tags: [String]) {
    self.timestamp = timestamp
    self.duration = duration
    self.section = section
    self.selected = selected
    self.expectedDuration = expectedDuration
    self.tags = tags
  }
}

public struct TemplateEntry {
  public var section: String
  public var expectedDuration: Int
  public var tags: [String]

  public init(section: String, expectedDuration: Int, tags: [String]) {
    self.section = section
    self.expectedDuration = expectedDuration
    self.tags = tags
  }
}

public struct Model {
  public var currentTime: Int
  public var lastLapTime: Int
  public var laps: [Lap]
  public var template: [TemplateEntry]
  public var originalTemplate: [TemplateEntry]
  public var activeSection: Int

  public init(currentTime: Int, lastLapTime: Int, laps: [Lap],
    template: [TemplateEntry], originalTemplate: [TemplateEntry], activeSection: Int) {
    self.currentTime = currentTime
    self.lastLapTime = lastLapTime
    self.laps = laps
    self.template = template
    self.originalTemplate = originalTemplate
    self.activeSection = activeSection
  }
}

public enum Action {
  case setTime(ms: Int)
  case createLap
  case labelLap(idx: Int, name: String)
  case selectLap(idx: Int)
  case deleteLap(idx: Int)
  case adjustDuration(idx: Int, duration: Int)
  case moveUp(idx: Int)
  case moveDown(idx: Int)
  case addTag(idx: Int, tag: String)
  case removeTag(idx: Int, tag: String)
  case setTemplate(labels: [TemplateEntry])
  case consumeTemplate
  case setActiveSection(idx: Int)
  case applyActiveSection
  case advanceTemplateAfter(idx: Int)
  case importLaps(laps: [Lap])
  case reset
}

public struct History {
  public var past: [Model]
  public var present: Model
  public var future: [Model]

  public init(past: [Model], present: Model, future: [Model]) {
    self.past = past
    self.present = present
    self.future = future
  }
}

// MARK: - Tags and validation

//@ verify
//@ pure
public func addTagToSeq(_ tags: [String], _ tag: String) -> [String] {
  //@ ensures \result.contains(tag)
  if tags.contains(tag) { return tags }
  return tags + [tag]
}

//@ verify
//@ pure
public func removeTagFromSeq(_ tags: [String], _ tag: String) -> [String] {
  //@ decreases tags.count
  //@ ensures !\result.contains(tag)
  if tags.isEmpty { return [] }
  let rest = removeTagFromSeq(Array(tags.dropFirst()), tag)
  if tags[0] == tag { return rest }
  return [tags[0]] + rest
}

//@ verify
//@ pure
public func lapValid(_ lap: Lap) -> Bool {
  return lap.timestamp >= 0 && lap.duration >= 0 && lap.expectedDuration >= -1
}

//@ verify
//@ pure
public func lapsValid(_ laps: [Lap]) -> Bool {
  return laps.allSatisfy(lapValid)
}

//@ verify
//@ pure
public func clampLap(_ lap: Lap) -> Lap {
  //@ ensures \result.timestamp >= 0
  //@ ensures \result.duration >= 0
  //@ ensures \result.expectedDuration >= -1
  return Lap(timestamp: lap.timestamp >= 0 ? lap.timestamp : 0,
    duration: lap.duration >= 0 ? lap.duration : 0,
    section: lap.section, selected: lap.selected,
    expectedDuration: lap.expectedDuration >= -1 ? lap.expectedDuration : -1,
    tags: lap.tags)
}

//@ verify
//@ pure
public func clampLaps(_ laps: [Lap]) -> [Lap] {
  //@ decreases laps.count
  //@ ensures \result.count == laps.count
  //@ ensures lapsValid(\result)
  if laps.isEmpty { return [] }
  return [clampLap(laps[0])] + clampLaps(Array(laps.dropFirst()))
}

//@ verify
//@ pure
public func templateEntryToLap(_ entry: TemplateEntry) -> Lap {
  //@ ensures \result.timestamp >= 0
  //@ ensures \result.duration >= 0
  //@ ensures \result.expectedDuration == -1
  return Lap(timestamp: 0,
    duration: entry.expectedDuration >= 0 ? entry.expectedDuration : 0,
    section: entry.section, selected: true, expectedDuration: -1, tags: entry.tags)
}

//@ verify
//@ pure
public func templateToLaps(_ template: [TemplateEntry]) -> [Lap] {
  //@ decreases template.count
  //@ ensures \result.count == template.count
  //@ ensures lapsValid(\result)
  if template.isEmpty { return [] }
  return [templateEntryToLap(template[0])] + templateToLaps(Array(template.dropFirst()))
}

//@ verify
//@ pure
public func inv(_ model: Model) -> Bool {
  return model.currentTime >= 0
    && model.lastLapTime >= 0
    && model.lastLapTime <= model.currentTime
    && lapsValid(model.laps)
    && model.activeSection >= -1
    && (model.activeSection < 0 || model.activeSection < model.originalTemplate.count)
}

//@ verify
public func initialModel() -> Model {
  //@ ensures inv(\result)
  return Model(currentTime: 0, lastLapTime: 0, laps: [], template: [],
    originalTemplate: [], activeSection: -1)
}

// MARK: - Value-preserving collection updates

//@ verify
//@ pure
public func setAt<T>(_ values: [T], _ index: Int, _ value: T) -> [T] {
  //@ requires index >= 0 && index < values.count
  //@ ensures \result.count == values.count
  var result = values
  result[index] = value
  return result
}

//@ verify
//@ pure
public func removeAt<T>(_ values: [T], _ index: Int) -> [T] {
  //@ requires index >= 0 && index < values.count
  //@ ensures \result.count == values.count - 1
  var result = values
  result.remove(at: index)
  return result
}

// MARK: - The seventeen action handlers

//@ verify
public func applySetTime(_ model: Model, _ ms: Int) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if ms >= model.currentTime {
    var result = model
    result.currentTime = ms
    return result
  }
  return model
}

//@ verify
public func applyCreateLap(_ model: Model) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  let duration = model.currentTime - model.lastLapTime
  let lap = Lap(timestamp: model.currentTime, duration: duration, section: "",
    selected: false, expectedDuration: -1, tags: [])
  var result = model
  result.lastLapTime = model.currentTime
  result.laps = model.laps + [lap]
  return result
}

//@ verify
public func applyLabelLap(_ model: Model, _ index: Int, _ name: String) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if index < 0 || index >= model.laps.count { return model }
  var lap = model.laps[index]
  lap.section = name
  var result = model
  result.laps = setAt(model.laps, index, lap)
  return result
}

//@ verify
public func applySelectLap(_ model: Model, _ index: Int) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if index < 0 || index >= model.laps.count { return model }
  var lap = model.laps[index]
  lap.selected = !lap.selected
  var result = model
  result.laps = setAt(model.laps, index, lap)
  return result
}

//@ verify
public func applyDeleteLap(_ model: Model, _ index: Int) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if index < 0 || index >= model.laps.count { return model }
  var result = model
  result.laps = removeAt(model.laps, index)
  return result
}

//@ verify
public func applyAdjustDuration(_ model: Model, _ index: Int, _ duration: Int) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if index < 0 || index >= model.laps.count { return model }
  if duration < 0 { return model }
  var lap = model.laps[index]
  lap.duration = duration
  var result = model
  result.laps = setAt(model.laps, index, lap)
  return result
}

//@ verify
public func applyMoveUp(_ model: Model, _ index: Int) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if index < 1 || index >= model.laps.count { return model }
  let a = model.laps[index - 1]
  let b = model.laps[index]
  var result = model
  result.laps = setAt(setAt(model.laps, index - 1, b), index, a)
  return result
}

//@ verify
public func applyMoveDown(_ model: Model, _ index: Int) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if index < 0 || index >= model.laps.count - 1 { return model }
  let a = model.laps[index]
  let b = model.laps[index + 1]
  var result = model
  result.laps = setAt(setAt(model.laps, index, b), index + 1, a)
  return result
}

//@ verify
public func applyAddTag(_ model: Model, _ index: Int, _ tag: String) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if index < 0 || index >= model.laps.count { return model }
  var lap = model.laps[index]
  lap.tags = addTagToSeq(lap.tags, tag)
  var result = model
  result.laps = setAt(model.laps, index, lap)
  return result
}

//@ verify
public func applyRemoveTag(_ model: Model, _ index: Int, _ tag: String) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if index < 0 || index >= model.laps.count { return model }
  var lap = model.laps[index]
  lap.tags = removeTagFromSeq(lap.tags, tag)
  var result = model
  result.laps = setAt(model.laps, index, lap)
  return result
}

//@ verify
public func applySetTemplate(_ model: Model, _ labels: [TemplateEntry]) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  var result = model
  result.template = labels
  result.originalTemplate = labels
  result.activeSection = -1
  return result
}

//@ verify
public func applyConsumeTemplate(_ model: Model) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if model.template.isEmpty || model.laps.isEmpty { return model }
  let index = model.laps.count - 1
  let entry = model.template[0]
  var lap = model.laps[index]
  lap.section = entry.section
  lap.selected = true
  lap.expectedDuration = entry.expectedDuration >= 0 ? entry.expectedDuration : -1
  lap.tags = entry.tags
  var result = model
  result.laps = setAt(model.laps, index, lap)
  result.template = Array(model.template.dropFirst())
  return result
}

//@ verify
public func applySetActiveSection(_ model: Model, _ index: Int) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if index < -1 { return model }
  if index >= 0 && index >= model.originalTemplate.count { return model }
  var result = model
  result.activeSection = index
  return result
}

//@ verify
public func applyApplyActiveSection(_ model: Model) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if model.activeSection < 0 || model.activeSection >= model.originalTemplate.count {
    return model
  }
  if model.laps.isEmpty { return model }
  let index = model.laps.count - 1
  let entry = model.originalTemplate[model.activeSection]
  var lap = model.laps[index]
  lap.section = entry.section
  lap.selected = true
  lap.expectedDuration = entry.expectedDuration >= 0 ? entry.expectedDuration : -1
  lap.tags = entry.tags
  var result = model
  result.laps = setAt(model.laps, index, lap)
  return result
}

//@ verify
public func applyAdvanceTemplateAfter(_ model: Model, _ index: Int) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  if index < 0 || index >= model.originalTemplate.count { return model }
  var result = model
  result.template = Array(model.originalTemplate.dropFirst(index + 1))
  result.activeSection = -1
  return result
}

//@ verify
public func applyImportLaps(_ model: Model, _ laps: [Lap]) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  var result = model
  result.laps = model.laps + clampLaps(laps)
  return result
}

//@ verify
public func applyReset(_ model: Model) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  return Model(currentTime: model.currentTime, lastLapTime: model.currentTime,
    laps: templateToLaps(model.originalTemplate), template: [], originalTemplate: [],
    activeSection: -1)
}

//@ verify
public func apply(_ model: Model, _ action: Action) -> Model {
  //@ requires inv(model)
  //@ ensures inv(\result)
  switch action {
  case .setTime(let ms): return applySetTime(model, ms)
  case .createLap: return applyCreateLap(model)
  case .labelLap(let index, let name): return applyLabelLap(model, index, name)
  case .selectLap(let index): return applySelectLap(model, index)
  case .deleteLap(let index): return applyDeleteLap(model, index)
  case .adjustDuration(let index, let duration): return applyAdjustDuration(model, index, duration)
  case .moveUp(let index): return applyMoveUp(model, index)
  case .moveDown(let index): return applyMoveDown(model, index)
  case .addTag(let index, let tag): return applyAddTag(model, index, tag)
  case .removeTag(let index, let tag): return applyRemoveTag(model, index, tag)
  case .setTemplate(let labels): return applySetTemplate(model, labels)
  case .consumeTemplate: return applyConsumeTemplate(model)
  case .setActiveSection(let index): return applySetActiveSection(model, index)
  case .applyActiveSection: return applyApplyActiveSection(model)
  case .advanceTemplateAfter(let index): return applyAdvanceTemplateAfter(model, index)
  case .importLaps(let laps): return applyImportLaps(model, laps)
  case .reset: return applyReset(model)
  }
}

// MARK: - Selected, tag, and section aggregates

//@ verify
//@ pure
public func sumFrom(_ values: [Int], _ index: Int) -> Int {
  //@ type index nat
  //@ requires index <= values.count
  //@ decreases values.count - index
  if index >= values.count { return 0 }
  return values[index] + sumFrom(values, index + 1)
}

//@ verify
//@ pure
public func selectedDurations(_ laps: [Lap]) -> [Int] {
  //@ decreases laps.count
  if laps.isEmpty { return [] }
  let rest = selectedDurations(Array(laps.dropFirst()))
  if laps[0].selected { return [laps[0].duration] + rest }
  return rest
}

//@ verify
public func selectedTotal(_ laps: [Lap]) -> Int {
  return sumFrom(selectedDurations(laps), 0)
}

//@ verify
public func selectedCount(_ laps: [Lap]) -> Int {
  //@ ensures \result >= 0
  return selectedDurations(laps).count
}

//@ verify
//@ pure
public func lapHasTag(_ lap: Lap, _ tag: String) -> Bool {
  return lap.tags.contains(tag)
}

//@ verify
//@ pure
public func sumByTag(_ laps: [Lap], _ tag: String) -> Int {
  //@ decreases laps.count
  if laps.isEmpty { return 0 }
  let rest = sumByTag(Array(laps.dropFirst()), tag)
  if laps[0].selected && lapHasTag(laps[0], tag) { return laps[0].duration + rest }
  return rest
}

//@ verify
//@ pure
public func countByTag(_ laps: [Lap], _ tag: String) -> Int {
  //@ decreases laps.count
  //@ ensures \result >= 0
  if laps.isEmpty { return 0 }
  let rest = countByTag(Array(laps.dropFirst()), tag)
  if laps[0].selected && lapHasTag(laps[0], tag) { return 1 + rest }
  return rest
}

//@ verify
//@ pure
public func addUniqueTags(_ seen: [String], _ tags: [String]) -> [String] {
  //@ decreases tags.count
  if tags.isEmpty { return seen }
  if seen.contains(tags[0]) { return addUniqueTags(seen, Array(tags.dropFirst())) }
  return addUniqueTags(seen + [tags[0]], Array(tags.dropFirst()))
}

//@ verify
//@ pure
public func collectAllTagsHelper(_ laps: [Lap], _ seen: [String]) -> [String] {
  //@ decreases laps.count
  if laps.isEmpty { return seen }
  let newTags = laps[0].selected ? laps[0].tags : []
  let updatedSeen = addUniqueTags(seen, newTags)
  return collectAllTagsHelper(Array(laps.dropFirst()), updatedSeen)
}

//@ verify
public func collectAllTags(_ laps: [Lap]) -> [String] {
  return collectAllTagsHelper(laps, [])
}

//@ verify
//@ pure
public func sumBySection(_ laps: [Lap], _ section: String) -> Int {
  //@ decreases laps.count
  if laps.isEmpty { return 0 }
  let rest = sumBySection(Array(laps.dropFirst()), section)
  if laps[0].selected && laps[0].section == section { return laps[0].duration + rest }
  return rest
}

//@ verify
//@ pure
public func countBySection(_ laps: [Lap], _ section: String) -> Int {
  //@ decreases laps.count
  //@ ensures \result >= 0
  if laps.isEmpty { return 0 }
  let rest = countBySection(Array(laps.dropFirst()), section)
  if laps[0].selected && laps[0].section == section { return 1 + rest }
  return rest
}

//@ verify
//@ pure
public func minBySectionHelper(_ laps: [Lap], _ section: String, _ currentMin: Int) -> Int {
  //@ decreases laps.count
  //@ requires lapsValid(laps)
  //@ requires currentMin >= -1
  //@ ensures \result >= -1
  if laps.isEmpty { return currentMin }
  if laps[0].selected && laps[0].section == section {
    let newMin = currentMin == -1 ? laps[0].duration
      : (laps[0].duration < currentMin ? laps[0].duration : currentMin)
    return minBySectionHelper(Array(laps.dropFirst()), section, newMin)
  }
  return minBySectionHelper(Array(laps.dropFirst()), section, currentMin)
}

//@ verify
public func minBySection(_ laps: [Lap], _ section: String) -> Int {
  //@ requires lapsValid(laps)
  //@ ensures \result >= -1
  return minBySectionHelper(laps, section, -1)
}

//@ verify
//@ pure
public func maxBySectionHelper(_ laps: [Lap], _ section: String, _ currentMax: Int) -> Int {
  //@ decreases laps.count
  //@ requires lapsValid(laps)
  //@ requires currentMax >= -1
  //@ ensures \result >= -1
  if laps.isEmpty { return currentMax }
  if laps[0].selected && laps[0].section == section {
    let newMax = laps[0].duration > currentMax ? laps[0].duration : currentMax
    return maxBySectionHelper(Array(laps.dropFirst()), section, newMax)
  }
  return maxBySectionHelper(Array(laps.dropFirst()), section, currentMax)
}

//@ verify
public func maxBySection(_ laps: [Lap], _ section: String) -> Int {
  //@ requires lapsValid(laps)
  //@ ensures \result >= -1
  return maxBySectionHelper(laps, section, -1)
}

//@ verify
//@ pure
public func collectAllSectionsHelper(_ laps: [Lap], _ seen: [String]) -> [String] {
  //@ decreases laps.count
  if laps.isEmpty { return seen }
  if laps[0].selected && laps[0].section != "" {
    let section = laps[0].section
    let updatedSeen = seen.contains(section) ? seen : seen + [section]
    return collectAllSectionsHelper(Array(laps.dropFirst()), updatedSeen)
  }
  return collectAllSectionsHelper(Array(laps.dropFirst()), seen)
}

//@ verify
public func collectAllSections(_ laps: [Lap]) -> [String] {
  return collectAllSectionsHelper(laps, [])
}

//@ verify
//@ pure
public func runningTotalsHelper(_ laps: [Lap], _ accumulated: Int) -> [Int] {
  //@ decreases laps.count
  //@ ensures \result.count == laps.count
  if laps.isEmpty { return [] }
  let next = laps[0].selected ? accumulated + laps[0].duration : accumulated
  return [accumulated] + runningTotalsHelper(Array(laps.dropFirst()), next)
}

//@ verify
public func runningTotals(_ laps: [Lap]) -> [Int] {
  //@ ensures \result.count == laps.count
  return runningTotalsHelper(laps, 0)
}

// MARK: - Undo and redo history

//@ verify
//@ pure
public func histInv(_ history: History) -> Bool {
  return history.past.allSatisfy(inv) && inv(history.present) && history.future.allSatisfy(inv)
}

//@ verify
public func initHistory() -> History {
  //@ ensures histInv(\result)
  return History(past: [], present: initialModel(), future: [])
}

//@ verify
public func doAction(_ history: History, _ action: Action) -> History {
  //@ requires histInv(history)
  //@ ensures histInv(\result)
  return History(past: history.past + [history.present],
    present: apply(history.present, action), future: [])
}

//@ verify
public func preview(_ history: History, _ action: Action) -> History {
  //@ requires histInv(history)
  //@ ensures histInv(\result)
  return History(past: history.past, present: apply(history.present, action), future: history.future)
}

//@ verify
public func commitFrom(_ history: History, _ baseline: Model) -> History {
  //@ requires histInv(history)
  //@ requires inv(baseline)
  //@ ensures histInv(\result)
  return History(past: history.past + [baseline], present: history.present, future: [])
}

//@ verify
public func undo(_ history: History) -> History {
  //@ requires histInv(history)
  //@ ensures histInv(\result)
  if history.past.isEmpty { return history }
  let index = history.past.count - 1
  return History(past: Array(history.past.dropLast()), present: history.past[index],
    future: [history.present] + history.future)
}

//@ verify
public func redo(_ history: History) -> History {
  //@ requires histInv(history)
  //@ ensures histInv(\result)
  if history.future.isEmpty { return history }
  return History(past: history.past + [history.present], present: history.future[0],
    future: Array(history.future.dropFirst()))
}
