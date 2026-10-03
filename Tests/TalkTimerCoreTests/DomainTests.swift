import XCTest
@testable import TalkTimerCore

final class DomainTests: XCTestCase {
  private func lap(_ duration: Int, section: String = "", selected: Bool = true,
    timestamp: Int = 0, expected: Int = -1, tags: [String] = []) -> Lap {
    Lap(timestamp: timestamp, duration: duration, section: section, selected: selected,
      expectedDuration: expected, tags: tags)
  }
  private let template = [
    TemplateEntry(section: "Intro", expectedDuration: 20, tags: ["opening"]),
    TemplateEntry(section: "Demo", expectedDuration: -8, tags: ["demo"]),
    TemplateEntry(section: "Closing", expectedDuration: 10, tags: []),
  ]
  private func model(_ laps: [Lap]) -> Model {
    apply(initialModel(), .importLaps(laps: laps))
  }

  func testInitialModelAndHistoryAreValid() {
    let value = initialModel()
    XCTAssertTrue(inv(value)); XCTAssertEqual(value.currentTime, 0); XCTAssertEqual(value.lastLapTime, 0)
    XCTAssertTrue(value.laps.isEmpty); XCTAssertTrue(value.template.isEmpty)
    XCTAssertTrue(value.originalTemplate.isEmpty); XCTAssertEqual(value.activeSection, -1)
    let history = initHistory()
    XCTAssertTrue(histInv(history)); XCTAssertTrue(history.past.isEmpty); XCTAssertTrue(history.future.isEmpty)
    XCTAssertEqual(ModelSnapshot(history.present), ModelSnapshot(value))
  }

  func testTimeIsMonotonicAndLapsCaptureElapsedIntervals() {
    var value = apply(initialModel(), .setTime(ms: 100))
    XCTAssertEqual(apply(value, .setTime(ms: 99)).currentTime, 100)
    XCTAssertEqual(apply(value, .setTime(ms: -1)).currentTime, 100)
    value = apply(value, .createLap)
    value = apply(value, .setTime(ms: 175))
    value = apply(value, .createLap)
    value = apply(value, .createLap)
    XCTAssertEqual(value.laps.map(\.duration), [100, 75, 0])
    XCTAssertEqual(value.laps.map(\.timestamp), [100, 175, 175])
    XCTAssertEqual(value.lastLapTime, 175)
    XCTAssertTrue(value.laps.allSatisfy { !$0.selected && $0.section.isEmpty && $0.expectedDuration == -1 && $0.tags.isEmpty })
    XCTAssertTrue(inv(value))
  }

  func testLapEditingPreservesUntouchedFieldsAndOtherLaps() {
    let original = model([lap(10, section: "old", timestamp: 15, expected: 12, tags: ["keep"]), lap(20)])
    var value = apply(original, .labelLap(idx: 0, name: "new"))
    value = apply(value, .selectLap(idx: 0))
    value = apply(value, .adjustDuration(idx: 0, duration: 30))
    XCTAssertEqual(LapSnapshot(value.laps[0]), LapSnapshot(lap(30, section: "new", selected: false,
      timestamp: 15, expected: 12, tags: ["keep"])))
    XCTAssertEqual(LapSnapshot(value.laps[1]), LapSnapshot(original.laps[1]))
    XCTAssertEqual(value.currentTime, original.currentTime); XCTAssertEqual(value.lastLapTime, original.lastLapTime)
    XCTAssertEqual(ModelSnapshot(apply(value, .adjustDuration(idx: 0, duration: -1))), ModelSnapshot(value))
  }

  func testInvalidIndicesAreNoOps() {
    let value = apply(model([lap(10)]), .setTemplate(labels: template))
    let actions: [Action] = [
      .labelLap(idx: -1, name: "bad"), .labelLap(idx: 1, name: "bad"),
      .selectLap(idx: -1), .selectLap(idx: 1), .deleteLap(idx: -1), .deleteLap(idx: 1),
      .adjustDuration(idx: -1, duration: 5), .adjustDuration(idx: 1, duration: 5),
      .moveUp(idx: 0), .moveUp(idx: 1), .moveDown(idx: -1), .moveDown(idx: 0),
      .addTag(idx: -1, tag: "bad"), .addTag(idx: 1, tag: "bad"),
      .removeTag(idx: -1, tag: "bad"), .removeTag(idx: 1, tag: "bad"),
      .setActiveSection(idx: -2), .setActiveSection(idx: 3),
      .advanceTemplateAfter(idx: -1), .advanceTemplateAfter(idx: 3),
    ]
    for action in actions { XCTAssertEqual(ModelSnapshot(apply(value, action)), ModelSnapshot(value)) }
  }

  func testReorderingAndDeletionOperateOnWholeRecords() {
    let value = model([lap(10, section: "A"), lap(20, section: "B"), lap(30, section: "C")])
    let moved = apply(value, .moveUp(idx: 2))
    XCTAssertEqual(moved.laps.map(\.section), ["A", "C", "B"])
    XCTAssertEqual(moved.laps.map(\.duration), [10, 30, 20])
    XCTAssertEqual(ModelSnapshot(apply(moved, .moveDown(idx: 1))), ModelSnapshot(value))
    XCTAssertEqual(apply(value, .deleteLap(idx: 1)).laps.map(\.section), ["A", "C"])
  }

  func testTagsAreIdempotentAndRemovalDropsEveryDuplicate() {
    XCTAssertEqual(addTagToSeq(["a", "b"], "a"), ["a", "b"])
    XCTAssertEqual(addTagToSeq(["a"], "b"), ["a", "b"])
    XCTAssertEqual(removeTagFromSeq(["a", "b", "a", "c"], "a"), ["b", "c"])
    var value = model([lap(4, tags: ["a", "a", "b"])])
    value = apply(value, .addTag(idx: 0, tag: "c"))
    value = apply(value, .removeTag(idx: 0, tag: "a"))
    XCTAssertEqual(value.laps[0].tags, ["b", "c"])
    XCTAssertEqual(value.laps[0].duration, 4)
  }

  func testConsumeTemplateLabelsOnlyLastLapAndConsumesOneEntry() {
    let value = apply(model([lap(5), lap(8, selected: false)]), .setTemplate(labels: template))
    let consumed = apply(value, .consumeTemplate)
    XCTAssertEqual(LapSnapshot(consumed.laps[0]), LapSnapshot(value.laps[0]))
    XCTAssertEqual(consumed.laps[1].section, "Intro"); XCTAssertEqual(consumed.laps[1].duration, 8)
    XCTAssertTrue(consumed.laps[1].selected); XCTAssertEqual(consumed.laps[1].expectedDuration, 20)
    XCTAssertEqual(consumed.laps[1].tags, ["opening"]); XCTAssertEqual(consumed.template.count, 2)
    XCTAssertEqual(consumed.originalTemplate.map(TemplateSnapshot.init), template.map(TemplateSnapshot.init))
    let again = apply(consumed, .consumeTemplate)
    XCTAssertEqual(again.laps[1].expectedDuration, -1)
    XCTAssertEqual(again.laps[1].section, "Demo")
    let noLaps = apply(initialModel(), .setTemplate(labels: template))
    XCTAssertEqual(ModelSnapshot(apply(noLaps, .consumeTemplate)), ModelSnapshot(noLaps))
  }

  func testActiveSectionAndAdvanceUseOriginalTemplate() {
    var value = apply(model([lap(9)]), .setTemplate(labels: template))
    value = apply(value, .setActiveSection(idx: 1))
    let applied = apply(value, .applyActiveSection)
    XCTAssertEqual(applied.laps[0].section, "Demo"); XCTAssertEqual(applied.laps[0].expectedDuration, -1)
    XCTAssertEqual(applied.template.count, 3); XCTAssertEqual(applied.activeSection, 1)
    let advanced = apply(applied, .advanceTemplateAfter(idx: 1))
    XCTAssertEqual(advanced.template.map(\.section), ["Closing"]); XCTAssertEqual(advanced.activeSection, -1)
    XCTAssertEqual(advanced.originalTemplate.count, 3)
    XCTAssertEqual(ModelSnapshot(apply(advanced, .applyActiveSection)), ModelSnapshot(advanced))
  }

  func testImportClampsNumericValidityAndPreservesContent() {
    let imported = lap(-7, section: "Imported", selected: false, timestamp: -9, expected: -8, tags: ["x", "x"])
    let value = apply(model([lap(4)]), .importLaps(laps: [imported]))
    XCTAssertEqual(value.laps.count, 2)
    XCTAssertEqual(LapSnapshot(value.laps[1]), LapSnapshot(lap(0, section: "Imported", selected: false,
      timestamp: 0, expected: -1, tags: ["x", "x"])))
    XCTAssertEqual(value.currentTime, 0); XCTAssertEqual(value.lastLapTime, 0); XCTAssertTrue(inv(value))
  }

  func testResetCreatesPracticeRowsOnceAndKeepsClockBaseline() {
    var value = apply(initialModel(), .setTime(ms: 500))
    value = apply(value, .setTemplate(labels: template))
    value = apply(value, .reset)
    XCTAssertEqual(value.currentTime, 500); XCTAssertEqual(value.lastLapTime, 500)
    XCTAssertEqual(value.laps.map(\.duration), [20, 0, 10])
    XCTAssertEqual(value.laps.map(\.section), ["Intro", "Demo", "Closing"])
    XCTAssertTrue(value.laps.allSatisfy { $0.selected && $0.timestamp == 0 && $0.expectedDuration == -1 })
    XCTAssertTrue(value.template.isEmpty); XCTAssertTrue(value.originalTemplate.isEmpty); XCTAssertEqual(value.activeSection, -1)
    value = apply(value, .reset)
    XCTAssertTrue(value.laps.isEmpty); XCTAssertEqual(value.lastLapTime, 500)
  }

  func testAggregatesUseSelectedLapsAndKeepEncounterOrder() {
    let laps = [lap(5, section: "Intro", tags: ["b", "a", "b"]),
      lap(100, section: "Hidden", selected: false, tags: ["hidden"]),
      lap(9, section: "Intro", tags: ["a", "c"]), lap(3, section: "", tags: [])]
    XCTAssertEqual(selectedDurations(laps), [5, 9, 3]); XCTAssertEqual(selectedTotal(laps), 17)
    XCTAssertEqual(selectedCount(laps), 3); XCTAssertEqual(runningTotals(laps), [0, 5, 5, 14])
    XCTAssertEqual(collectAllTags(laps), ["b", "a", "c"]); XCTAssertEqual(collectAllSections(laps), ["Intro"])
    XCTAssertEqual(sumByTag(laps, "a"), 14); XCTAssertEqual(countByTag(laps, "b"), 1)
    XCTAssertEqual(sumBySection(laps, "Intro"), 14); XCTAssertEqual(countBySection(laps, "Intro"), 2)
    XCTAssertEqual(minBySection(laps, "Intro"), 5); XCTAssertEqual(maxBySection(laps, "Intro"), 9)
    XCTAssertEqual(minBySection(laps, "missing"), -1); XCTAssertEqual(maxBySection([], "missing"), -1)
    XCTAssertEqual(sumFrom([2, 4, 6], 1), 10); XCTAssertEqual(sumFrom([], 0), 0)
  }

  func testUndoRedoRoundTripAndNewActionClearsFuture() {
    let empty = initHistory()
    XCTAssertEqual(HistorySnapshot(undo(empty)), HistorySnapshot(empty))
    XCTAssertEqual(HistorySnapshot(redo(empty)), HistorySnapshot(empty))
    var history = doAction(empty, .setTime(ms: 5))
    history = doAction(history, .createLap)
    XCTAssertEqual(HistorySnapshot(redo(undo(history))), HistorySnapshot(history))
    let undone = undo(history)
    XCTAssertEqual(undone.future.count, 1); XCTAssertEqual(undone.present.laps.count, 0)
    let branched = doAction(undone, .setTime(ms: 10))
    XCTAssertTrue(branched.future.isEmpty); XCTAssertEqual(branched.present.currentTime, 10)
    XCTAssertTrue(histInv(branched))
  }

  func testPreviewAndCommitUseExplicitBaseline() {
    let baseline = apply(initialModel(), .setTime(ms: 30))
    let history = doAction(initHistory(), .setTime(ms: 30))
    let edited = preview(preview(history, .createLap), .labelLap(idx: 0, name: "preview"))
    XCTAssertEqual(edited.past.count, history.past.count)
    XCTAssertEqual(edited.future.map(ModelSnapshot.init), history.future.map(ModelSnapshot.init))
    let committed = commitFrom(edited, baseline)
    XCTAssertEqual(committed.past.count, history.past.count + 1)
    XCTAssertEqual(ModelSnapshot(undo(committed).present), ModelSnapshot(baseline))
    XCTAssertEqual(ModelSnapshot(redo(undo(committed)).present), ModelSnapshot(edited.present))
  }

  func testNoOpActionsStillCreateUndoEntriesInReferenceSemantics() {
    let history = doAction(initHistory(), .deleteLap(idx: 0))
    XCTAssertEqual(history.past.count, 1)
    XCTAssertEqual(ModelSnapshot(history.present), ModelSnapshot(initialModel()))
  }
}
