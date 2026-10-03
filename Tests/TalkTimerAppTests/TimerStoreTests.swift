import Foundation
import XCTest
import TalkTimerCore
@testable import TalkTimerApp

final class TimerStoreTests: XCTestCase {
  func testTimeParserAcceptsWholeSecondsAndMinutesWithoutOverflow() {
    XCTAssertEqual(parseTime("0"), 0)
    XCTAssertEqual(parseTime(" 90\n"), 90_000)
    XCTAssertEqual(parseTime("01:05"), 65_000)
    XCTAssertEqual(parseTime("0:59"), 59_000)
    let maximumWholeSeconds = Int.max / 1000
    XCTAssertEqual(parseTime(String(maximumWholeSeconds)), maximumWholeSeconds * 1000)
    XCTAssertEqual(parseTime("\(maximumWholeSeconds / 60):\(maximumWholeSeconds % 60)"),
      maximumWholeSeconds * 1000)
  }

  func testTimeParserRejectsMalformedNegativeAndOverflowingValues() {
    let invalid = ["", " ", "-1", "+1", "1.5", "1:60", "1:", ":30", "1:2:3", "1: 02",
      "１２", "١٢", "NaN", "Infinity", String(Int.max), "\(Int.max):00",
      String(Int.max / 1000 + 1), "999999999999999999999999999999"]
    for text in invalid { XCTAssertNil(parseTime(text), "Unexpected accepted duration: \(text)") }
  }

  func testMarkdownParserPreservesUnicodeLabelsAndTagsAndSkipsInvalidLines() {
    let laps = parseMarkdown("""
      - [ ] 🎤 Café [démo, 日本語, , story] (01:30)
      - [X] A\u{0301} closing (00:09)
      - [ ] Total (01:39)
      - [ ] Invalid seconds (01:99)
      - [ ] Overflow (999999999999999999999:00)
      ordinary text
      """)
    XCTAssertEqual(laps.count, 2)
    guard laps.count == 2 else { return }
    XCTAssertEqual(laps[0].section, "🎤 Café")
    XCTAssertEqual(laps[0].tags, ["démo", "日本語", "story"])
    XCTAssertEqual(laps[0].duration, 90_000)
    XCTAssertEqual(Array(laps[1].section.utf8), Array("A\u{0301} closing".utf8))
    XCTAssertEqual(laps[1].duration, 9_000)
    XCTAssertTrue(laps.allSatisfy { $0.selected && $0.timestamp == 0 && $0.expectedDuration == -1 })
  }

  @MainActor
  func testFreshStoreHasNoDemoOrHistoryState() async {
    let store = TimerStore(demo: false)
    XCTAssertTrue(store.model.laps.isEmpty)
    XCTAssertTrue(store.history.past.isEmpty)
    XCTAssertTrue(store.history.future.isEmpty)
    XCTAssertEqual(store.elapsed, 0)
    XCTAssertFalse(store.running)
    XCTAssertTrue(histInv(store.history))
  }

  @MainActor
  func testLapAndTemplateConsumptionAreOneUndoableGesture() async {
    let store = TimerStore(demo: false)
    store.dispatch(.setTemplate(labels: [TemplateEntry(section: "Intro", expectedDuration: 3_000, tags: ["story"])]))
    let baseline = ModelState(store.model)
    let pastCount = store.history.past.count
    store.lap()
    XCTAssertEqual(store.history.past.count, pastCount + 1)
    XCTAssertEqual(store.model.laps.count, 1)
    XCTAssertEqual(store.model.laps.first?.section, "Intro")
    XCTAssertEqual(store.model.laps.first?.expectedDuration, 3_000)
    XCTAssertEqual(store.model.laps.first?.tags, ["story"])
    XCTAssertEqual(store.model.laps.first?.selected, true)
    XCTAssertTrue(store.model.template.isEmpty)
    let completed = ModelState(store.model)
    store.undoAction()
    XCTAssertEqual(ModelState(store.model), baseline)
    store.redoAction()
    XCTAssertEqual(ModelState(store.model), completed)
  }

  @MainActor
  func testActiveSectionRepeatAndAdvanceRespectSingleGestureUndo() async {
    let store = TimerStore(demo: false)
    store.dispatch(.setTemplate(labels: [
      TemplateEntry(section: "Intro", expectedDuration: 2_000, tags: []),
      TemplateEntry(section: "Demo", expectedDuration: 5_000, tags: ["demo"]),
    ]))
    store.activateSection(0)
    store.activateSection(0)
    XCTAssertTrue(store.repeatSection)
    let baseline = ModelState(store.model)
    let count = store.history.past.count
    store.lap()
    XCTAssertEqual(store.history.past.count, count + 1)
    XCTAssertEqual(store.model.activeSection, 0)
    XCTAssertEqual(store.model.template.count, 2)
    XCTAssertEqual(store.model.laps.first?.section, "Intro")
    store.undoAction()
    XCTAssertEqual(ModelState(store.model), baseline)
    XCTAssertFalse(store.repeatSection)
    store.lap()
    XCTAssertEqual(store.model.activeSection, -1)
    XCTAssertEqual(store.model.template.map(\.section), ["Demo"])
  }

  @MainActor
  func testResetKeepsDomainTimeMonotonicAndFirstNewLapUsesNewSessionElapsed() async throws {
    let store = TimerStore(demo: false)
    store.dispatch(.setTime(ms: 10_000))
    store.lap()
    let baseline = ModelState(store.model)
    let pastCount = store.history.past.count
    store.reset()
    XCTAssertEqual(store.history.past.count, pastCount + 1)
    XCTAssertEqual(store.model.currentTime, 10_000)
    XCTAssertEqual(store.model.lastLapTime, 10_000)
    XCTAssertEqual(store.elapsed, 0)
    XCTAssertTrue(store.running)
    XCTAssertTrue(store.model.laps.isEmpty)
    try await Task.sleep(for: .milliseconds(30))
    store.toggleTimer() // Captures the final elapsed time and freezes it for exact comparisons.
    let elapsed = store.elapsed
    XCTAssertGreaterThan(elapsed, 0)
    XCTAssertFalse(store.running)
    store.lap()
    XCTAssertEqual(store.model.laps.first?.duration, elapsed)
    XCTAssertEqual(store.model.laps.first?.timestamp, 10_000 + elapsed)
    XCTAssertEqual(store.model.currentTime, 10_000 + elapsed)
    XCTAssertTrue(histInv(store.history))
    store.undoAction() // New lap.
    store.undoAction() // Reset transaction.
    XCTAssertEqual(ModelState(store.model), baseline)
  }

  @MainActor
  func testPauseFreezesElapsedAndTickDoesNotCreateUndoEntries() async throws {
    let store = TimerStore(demo: false)
    store.toggleTimer()
    try await Task.sleep(for: .milliseconds(20))
    store.toggleTimer()
    let paused = store.elapsed
    XCTAssertGreaterThan(paused, 0)
    try await Task.sleep(for: .milliseconds(20))
    store.tick()
    XCTAssertEqual(store.elapsed, paused)
    XCTAssertTrue(store.history.past.isEmpty)
    XCTAssertEqual(store.model.currentTime, 0)
  }

  @MainActor
  func testPracticeBuildsTemplateAndResetAsOneUndoableGesture() async {
    let store = TimerStore(demo: false)
    store.dispatch(.importLaps(laps: [
      Lap(timestamp: 0, duration: 20_000, section: "Intro", selected: true, expectedDuration: -1, tags: ["story"]),
      Lap(timestamp: 0, duration: 30_000, section: "Demo", selected: false, expectedDuration: -1, tags: ["demo"]),
      Lap(timestamp: 0, duration: 15_000, section: "", selected: true, expectedDuration: -1, tags: []),
    ]))
    let baseline = ModelState(store.model)
    let pastCount = store.history.past.count
    store.startPractice()
    store.toggleTimer()
    XCTAssertEqual(store.history.past.count, pastCount + 1)
    XCTAssertTrue(store.model.laps.isEmpty)
    XCTAssertEqual(store.model.template.map(\.section), ["Intro", "Demo"])
    XCTAssertEqual(store.model.template.map(\.expectedDuration), [20_000, 30_000])
    XCTAssertEqual(store.model.template.map(\.tags), [["story"], ["demo"]])
    XCTAssertEqual(store.model.originalTemplate.map(\.section), ["Intro", "Demo"])
    XCTAssertEqual(store.model.activeSection, -1)
    store.undoAction()
    XCTAssertEqual(ModelState(store.model), baseline)
  }

  @MainActor
  func testInvalidEditLeavesAllDomainAndHistoryFieldsUnchanged() async {
    let store = TimerStore(demo: false)
    store.importMarkdown("- [ ] Original [keep] (00:10)")
    let baseline = ModelState(store.model)
    let pastCount = store.history.past.count
    XCTAssertFalse(store.saveTake(0, name: "Changed", text: "-1", tags: ["new"]))
    XCTAssertEqual(ModelState(store.model), baseline)
    XCTAssertEqual(store.history.past.count, pastCount)
    XCTAssertFalse(store.saveTake(8, name: "Changed", text: "30", tags: []))
    XCTAssertEqual(ModelState(store.model), baseline)
    XCTAssertEqual(store.history.past.count, pastCount)
    XCTAssertTrue(store.history.future.isEmpty)
  }

  @MainActor
  func testValidEditCombinesNameDurationAndTagsIntoOneUndoEntry() async {
    let store = TimerStore(demo: false)
    store.importMarkdown("- [ ] Original [remove, keep] (00:10)")
    let baseline = ModelState(store.model)
    let pastCount = store.history.past.count
    XCTAssertTrue(store.saveTake(0, name: "Edited", text: "1:30", tags: ["keep", "new", "new"]))
    XCTAssertEqual(store.history.past.count, pastCount + 1)
    XCTAssertEqual(store.model.laps.first?.section, "Edited")
    XCTAssertEqual(store.model.laps.first?.duration, 90_000)
    XCTAssertEqual(store.model.laps.first?.tags, ["keep", "new"])
    store.undoAction()
    XCTAssertEqual(ModelState(store.model), baseline)
  }

  @MainActor
  func testInvalidImportAndPracticeWithoutNamedTakesAreNoOps() async {
    let store = TimerStore(demo: false)
    store.importMarkdown("not a take")
    store.startPractice()
    XCTAssertTrue(store.model.laps.isEmpty)
    XCTAssertTrue(store.history.past.isEmpty)
    XCTAssertFalse(store.running)
    XCTAssertNotNil(store.notice)
  }

  @MainActor
  func testImportRejectsAggregateOverflowWithoutChangingHistoryOrRevision() async {
    let store = TimerStore(demo: false)
    store.importMarkdown("- [ ] Existing (00:10)")
    store.undoAction() // The refused import must preserve the redo branch as well.
    let baseline = HistoryState(store.history)
    let revision = store.revision
    let seconds = Int.max / 1000 / 2 + 1
    let text = "\(seconds / 60):\(seconds % 60)"
    XCTAssertEqual(parseTime(text), seconds * 1000, "Each duration is individually representable")
    store.importMarkdown("- [ ] Huge A (\(text))\n- [ ] Huge B (\(text))")
    XCTAssertEqual(HistoryState(store.history), baseline)
    XCTAssertEqual(store.revision, revision)
    XCTAssertEqual(store.summary.total, 0)
    XCTAssertTrue(store.notice?.contains("supported total") == true)
  }

  @MainActor
  func testOverflowingEditRejectsTheWholeNameDurationAndTagTransaction() async {
    let store = TimerStore(demo: false)
    let seconds = Int.max / 1000 / 2 + 1
    XCTAssertTrue(store.dispatch(.importLaps(laps: [
      Lap(timestamp: 0, duration: seconds * 1000, section: "Huge", selected: false,
        expectedDuration: -1, tags: []),
      Lap(timestamp: 0, duration: 1_000, section: "Small", selected: true,
        expectedDuration: -1, tags: ["keep"]),
    ])))
    let baseline = HistoryState(store.history)
    let revision = store.revision
    XCTAssertFalse(store.saveTake(1, name: "Changed", text: String(seconds), tags: ["replacement"]))
    XCTAssertEqual(HistoryState(store.history), baseline)
    XCTAssertEqual(store.revision, revision)
    XCTAssertEqual(store.summary.total, 1_000)
    XCTAssertTrue(store.notice?.contains("supported total") == true)
  }

  @MainActor
  func testRelabelingPreservesSubsecondDurationAndExplicitTimeEditChangesIt() async {
    let store = TimerStore(demo: false)
    store.dispatch(.importLaps(laps: [Lap(timestamp: 1_599, duration: 1_599, section: "Original",
      selected: true, expectedDuration: -1, tags: ["old"])]))
    let revision = store.revision
    XCTAssertEqual(formatTime(1_599), "00:01")
    XCTAssertTrue(store.saveTake(0, name: "Relabeled", text: " 00:01 ", tags: ["new"]))
    XCTAssertEqual(store.model.laps.first?.duration, 1_599)
    XCTAssertEqual(store.model.laps.first?.timestamp, 1_599)
    XCTAssertEqual(store.model.laps.first?.section, "Relabeled")
    XCTAssertEqual(store.model.laps.first?.tags, ["new"])
    XCTAssertEqual(store.summary.total, 1_599)
    XCTAssertEqual(store.revision, revision + 1)
    XCTAssertTrue(store.saveTake(0, name: "Relabeled", text: "00:02", tags: ["new"]))
    XCTAssertEqual(store.model.laps.first?.duration, 2_000)
    XCTAssertEqual(store.summary.total, 2_000)
    store.undoAction()
    XCTAssertEqual(store.model.laps.first?.duration, 1_599)
  }

  @MainActor
  func testSummaryAndRevisionFollowAcceptedEditsUndoAndRedo() async {
    let store = TimerStore(demo: false)
    XCTAssertEqual(store.revision, 0)
    store.importMarkdown("- [ ] Intro [story] (00:01)\n- [ ] Intro [story] (00:02)")
    XCTAssertEqual(store.revision, 1)
    XCTAssertEqual(store.summary.total, 3_000)
    XCTAssertEqual(store.summary.count, 2)
    XCTAssertEqual(store.summary.running, [0, 1_000])
    XCTAssertEqual(store.summary.sections.first?.total, 3_000)
    XCTAssertEqual(store.summary.sections.first?.minimum, 1_000)
    XCTAssertEqual(store.summary.sections.first?.maximum, 2_000)
    XCTAssertEqual(store.summary.tags.first?.count, 2)
    store.dispatch(.selectLap(idx: 1))
    XCTAssertEqual(store.revision, 2)
    XCTAssertEqual(store.summary.total, 1_000)
    XCTAssertEqual(store.summary.count, 1)
    store.undoAction()
    XCTAssertEqual(store.revision, 3)
    XCTAssertEqual(store.summary.total, 3_000)
    XCTAssertEqual(store.summary.tags.first?.count, 2)
    store.redoAction()
    XCTAssertEqual(store.revision, 4)
    XCTAssertEqual(store.summary.total, 1_000)
    XCTAssertEqual(store.summary.sections.first?.maximum, 1_000)
    store.tick()
    XCTAssertFalse(store.saveTake(0, name: "Bad", text: "invalid", tags: []))
    XCTAssertFalse(store.saveTake(99, name: "Bad", text: "30", tags: []))
    XCTAssertEqual(store.revision, 4)
    XCTAssertEqual(store.summary.total, 1_000)
  }

  @MainActor
  func testFollowOutlineExitsRepeatModeAndResumesPendingTemplate() async {
    let store = TimerStore(demo: false)
    store.dispatch(.setTemplate(labels: [
      TemplateEntry(section: "Intro", expectedDuration: 1_000, tags: []),
      TemplateEntry(section: "Demo", expectedDuration: 2_000, tags: []),
    ]))
    store.activateSection(1)
    store.activateSection(1)
    XCTAssertTrue(store.repeatSection)
    store.followOutline()
    XCTAssertFalse(store.repeatSection)
    XCTAssertEqual(store.model.activeSection, -1)
    store.lap()
    XCTAssertEqual(store.model.laps.first?.section, "Intro")
    XCTAssertEqual(store.model.template.map(\.section), ["Demo"])
  }
}

private struct HistoryState: Equatable {
  let past: [ModelState]
  let present: ModelState
  let future: [ModelState]
  init(_ history: History) {
    past = history.past.map(ModelState.init); present = ModelState(history.present)
    future = history.future.map(ModelState.init)
  }
}

// Compare every model field without adding test-only protocols to the core types.
private struct ModelState: Equatable {
  let currentTime: Int
  let lastLapTime: Int
  let laps: [LapState]
  let template: [EntryState]
  let originalTemplate: [EntryState]
  let activeSection: Int

  init(_ model: Model) {
    currentTime = model.currentTime; lastLapTime = model.lastLapTime
    laps = model.laps.map(LapState.init); template = model.template.map(EntryState.init)
    originalTemplate = model.originalTemplate.map(EntryState.init); activeSection = model.activeSection
  }
  struct LapState: Equatable {
    let timestamp: Int; let duration: Int; let section: String
    let selected: Bool; let expectedDuration: Int; let tags: [String]
    init(_ lap: Lap) {
      timestamp = lap.timestamp; duration = lap.duration; section = lap.section
      selected = lap.selected; expectedDuration = lap.expectedDuration; tags = lap.tags
    }
  }
  struct EntryState: Equatable {
    let section: String; let expectedDuration: Int; let tags: [String]
    init(_ entry: TemplateEntry) {
      section = entry.section; expectedDuration = entry.expectedDuration; tags = entry.tags
    }
  }
}
