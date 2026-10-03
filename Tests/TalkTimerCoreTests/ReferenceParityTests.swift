import Foundation
import XCTest
@testable import TalkTimerCore

final class ReferenceParityTests: XCTestCase {
  func testEveryReferenceSnapshotAndQueryMatchesSwift() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [ProcessInfo.processInfo.environment["NODE_EXECUTABLE"] ?? "node",
      root.appendingPathComponent("parity/generate.mjs").path]
    let output = Pipe()
    process.standardOutput = output
    // Inherit stderr so Node failures are visible without risking a full error pipe.
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, "Node 22.18+ is required for the TypeScript oracle")
    guard process.terminationStatus == 0 else { return }
    let trace = try JSONDecoder().decode(ReferenceTrace.self, from: bytes)
    XCTAssertEqual(trace.referenceCommit, "2b50d690c64c644698f7ab46f071d8c5d7cd17b2")
    XCTAssertEqual(trace.referenceSHA256, "e13f45a6c8a79f1b7a2b0b1dd0fa18c3edde60b66f80f716f980d95f422fa8c8")
    XCTAssertEqual(trace.scenarios.count, 5)
    var actionTypes = Set<String>()
    var comparedSteps = 0
    for scenario in trace.scenarios {
      var history = initHistory()
      for (index, step) in scenario.steps.enumerated() {
        let location = "\(scenario.name), command \(index): \(step.command.op)"
        if let action = step.command.action { actionTypes.insert(action.type) }
        history = try step.command.apply(to: history)
        XCTAssertTrue(histInv(history), location)
        XCTAssertEqual(HistorySnapshot(history), step.history, location)
        XCTAssertEqual(Queries(history.present.laps), step.queries, location)
        comparedSteps += 1
      }
    }
    XCTAssertEqual(actionTypes.count, 17)
    XCTAssertEqual(comparedSteps, 550)
  }
}

private struct ReferenceTrace: Decodable {
  let referenceCommit: String
  let referenceSHA256: String
  let scenarios: [Scenario]
  struct Scenario: Decodable {
    let name: String
    let steps: [Step]
  }
  struct Step: Decodable {
    let command: Command
    let history: HistorySnapshot
    let queries: Queries
  }
}

private struct Command: Decodable {
  let op: String
  let action: JSONAction?
  let baseline: ModelSnapshot?

  func apply(to history: History) throws -> History {
    switch op {
    case "doAction": return doAction(history, try XCTUnwrap(action).swift())
    case "preview": return preview(history, try XCTUnwrap(action).swift())
    case "commitFrom": return commitFrom(history, try XCTUnwrap(baseline).swift())
    case "undo": return undo(history)
    case "redo": return redo(history)
    default: throw TraceError.unknownCommand(op)
    }
  }
}

private enum TraceError: Error { case unknownCommand(String), unknownAction(String) }

private struct JSONAction: Decodable {
  let type: String
  let ms: Int?
  let idx: Int?
  let name: String?
  let duration: Int?
  let tag: String?
  let labels: [TemplateSnapshot]?
  let laps: [LapSnapshot]?

  func swift() throws -> Action {
    switch type {
    case "SetTime": return .setTime(ms: try XCTUnwrap(ms))
    case "CreateLap": return .createLap
    case "LabelLap": return .labelLap(idx: try XCTUnwrap(idx), name: try XCTUnwrap(name))
    case "SelectLap": return .selectLap(idx: try XCTUnwrap(idx))
    case "DeleteLap": return .deleteLap(idx: try XCTUnwrap(idx))
    case "AdjustDuration": return .adjustDuration(idx: try XCTUnwrap(idx), duration: try XCTUnwrap(duration))
    case "MoveUp": return .moveUp(idx: try XCTUnwrap(idx))
    case "MoveDown": return .moveDown(idx: try XCTUnwrap(idx))
    case "AddTag": return .addTag(idx: try XCTUnwrap(idx), tag: try XCTUnwrap(tag))
    case "RemoveTag": return .removeTag(idx: try XCTUnwrap(idx), tag: try XCTUnwrap(tag))
    case "SetTemplate": return .setTemplate(labels: try XCTUnwrap(labels).map { $0.swift() })
    case "ConsumeTemplate": return .consumeTemplate
    case "SetActiveSection": return .setActiveSection(idx: try XCTUnwrap(idx))
    case "ApplyActiveSection": return .applyActiveSection
    case "AdvanceTemplateAfter": return .advanceTemplateAfter(idx: try XCTUnwrap(idx))
    case "ImportLaps": return .importLaps(laps: try XCTUnwrap(laps).map { $0.swift() })
    case "Reset": return .reset
    default: throw TraceError.unknownAction(type)
    }
  }
}

struct LapSnapshot: Decodable, Equatable {
  let timestamp: Int
  let duration: Int
  let section: String
  let selected: Bool
  let expectedDuration: Int
  let tags: [String]
  init(_ lap: Lap) {
    timestamp = lap.timestamp; duration = lap.duration; section = lap.section
    selected = lap.selected; expectedDuration = lap.expectedDuration; tags = lap.tags
  }
  func swift() -> Lap {
    Lap(timestamp: timestamp, duration: duration, section: section, selected: selected,
      expectedDuration: expectedDuration, tags: tags)
  }
}

struct TemplateSnapshot: Decodable, Equatable {
  let section: String
  let expectedDuration: Int
  let tags: [String]
  init(_ entry: TemplateEntry) {
    section = entry.section; expectedDuration = entry.expectedDuration; tags = entry.tags
  }
  func swift() -> TemplateEntry {
    TemplateEntry(section: section, expectedDuration: expectedDuration, tags: tags)
  }
}

struct ModelSnapshot: Decodable, Equatable {
  let currentTime: Int
  let lastLapTime: Int
  let laps: [LapSnapshot]
  let template: [TemplateSnapshot]
  let originalTemplate: [TemplateSnapshot]
  let activeSection: Int
  init(_ model: Model) {
    currentTime = model.currentTime; lastLapTime = model.lastLapTime
    laps = model.laps.map(LapSnapshot.init); template = model.template.map(TemplateSnapshot.init)
    originalTemplate = model.originalTemplate.map(TemplateSnapshot.init); activeSection = model.activeSection
  }
  func swift() -> Model {
    Model(currentTime: currentTime, lastLapTime: lastLapTime, laps: laps.map { $0.swift() },
      template: template.map { $0.swift() }, originalTemplate: originalTemplate.map { $0.swift() }, activeSection: activeSection)
  }
}

struct HistorySnapshot: Decodable, Equatable {
  let past: [ModelSnapshot]
  let present: ModelSnapshot
  let future: [ModelSnapshot]
  init(_ history: History) {
    past = history.past.map(ModelSnapshot.init); present = ModelSnapshot(history.present)
    future = history.future.map(ModelSnapshot.init)
  }
}

private struct Queries: Decodable, Equatable {
  let selectedDurations: [Int]
  let selectedTotal: Int
  let selectedCount: Int
  let allTags: [String]
  let allSections: [String]
  let runningTotals: [Int]
  let tagQueries: [TagQuery]
  let sectionQueries: [SectionQuery]
  struct TagQuery: Decodable, Equatable { let tag: String; let sum: Int; let count: Int }
  struct SectionQuery: Decodable, Equatable {
    let section: String; let sum: Int; let count: Int; let min: Int; let max: Int
  }
  init(_ laps: [Lap]) {
    selectedDurations = TalkTimerCore.selectedDurations(laps)
    selectedTotal = TalkTimerCore.selectedTotal(laps); selectedCount = TalkTimerCore.selectedCount(laps)
    allTags = collectAllTags(laps); allSections = collectAllSections(laps)
    runningTotals = TalkTimerCore.runningTotals(laps)
    tagQueries = ["", "opening", "demo", "repeat", "missing"].map {
      TagQuery(tag: $0, sum: sumByTag(laps, $0), count: countByTag(laps, $0))
    }
    sectionQueries = ["", "Intro", "Demo", "Closing", "missing"].map {
      SectionQuery(section: $0, sum: sumBySection(laps, $0), count: countBySection(laps, $0),
        min: minBySection(laps, $0), max: maxBySection(laps, $0))
    }
  }
}
