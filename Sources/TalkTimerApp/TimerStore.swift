import AppKit
import Combine
import Foundation
import TalkTimerCore

// The clock, clipboard, and presentation layer are outside the verification boundary.
// Every domain edit still goes through the same core reducer used by the case study.
@MainActor
final class TimerStore: ObservableObject {
  @Published private(set) var history = initHistory()
  @Published private(set) var elapsed = 0
  @Published private(set) var running = false
  @Published var repeatSection = false
  @Published var notice: String?
  private(set) var revision = 0
  private(set) var summary = SessionSummary(laps: [])

  private let clock = ContinuousClock()
  private var started: ContinuousClock.Instant?
  private var pausedElapsed = 0
  private var timelineOffset = 0

  var model: Model { history.present }

  init(demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo")) {
    if demo {
      let laps = [
        Lap(timestamp: 0, duration: 72000, section: "The opening", selected: true,
          expectedDuration: -1, tags: ["story"]),
        Lap(timestamp: 0, duration: 138000, section: "Why this matters", selected: true,
          expectedDuration: -1, tags: ["context"]),
        Lap(timestamp: 0, duration: 185000, section: "Show the idea", selected: true,
          expectedDuration: -1, tags: ["demo"]),
        Lap(timestamp: 0, duration: 65000, section: "Leave them with this", selected: true,
          expectedDuration: -1, tags: ["story"]),
      ]
      dispatch(.importLaps(laps: laps))
    }
  }

  @discardableResult
  func dispatch(_ action: Action) -> Bool { publish(doAction(history, action)) }

  // One user gesture is one undo step, even when it applies multiple core actions.
  @discardableResult
  private func transaction(_ actions: [Action]) -> Bool {
    let baseline = history.present
    var candidate = history
    for action in actions { candidate = preview(candidate, action) }
    return publish(commitFrom(candidate, baseline))
  }

  private func publish(_ candidate: History) -> Bool {
    // Swift aggregates use bounded Int. Admit the whole nonnegative duration
    // total so later selection, grouping, and reordering cannot overflow it.
    // This is shell input validation, not a claim that the core was proved.
    var total = 0
    for lap in candidate.present.laps {
      let sum = total.addingReportingOverflow(lap.duration)
      guard lap.duration >= 0, !sum.overflow else {
        notice = "These durations exceed the supported total. Use shorter durations or import fewer takes."
        return false
      }
      total = sum.partialValue
    }
    replaceHistory(candidate)
    return true
  }

  private func replaceHistory(_ value: History) {
    // Aggregates depend on edits, not the 100ms presentation tick.
    summary = SessionSummary(laps: value.present.laps)
    revision += 1
    history = value
  }

  func tick() {
    guard let started else { return }
    let duration = started.duration(to: clock.now).components
    let milliseconds = duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000
    elapsed = pausedElapsed + Int(milliseconds)
  }

  func toggleTimer() {
    if running {
      tick()
      pausedElapsed = elapsed
      started = nil
    } else {
      started = clock.now
    }
    running.toggle()
  }

  private var domainTime: Int { max(model.currentTime, timelineOffset + elapsed) }

  func lap() {
    tick()
    var actions: [Action] = [.setTime(ms: domainTime), .createLap]
    if model.activeSection >= 0 {
      actions.append(.applyActiveSection)
      if !repeatSection { actions.append(.advanceTemplateAfter(idx: model.activeSection)) }
    } else if !model.template.isEmpty {
      actions.append(.consumeTemplate)
    }
    transaction(actions)
  }

  func reset() {
    tick()
    if transaction([.setTime(ms: domainTime), .reset]) { resetClock() }
  }

  func startPractice() {
    let entries = model.laps.filter { !$0.section.isEmpty }.map {
      TemplateEntry(section: $0.section, expectedDuration: $0.duration, tags: $0.tags)
    }
    guard !entries.isEmpty else { return }
    tick()
    if transaction([.setTime(ms: domainTime), .reset, .setTemplate(labels: entries)]) { resetClock() }
  }

  private func resetClock() {
    // The core intentionally keeps its monotonic time across Reset. Only the
    // displayed session starts from zero; future SetTime values retain the offset.
    timelineOffset = model.currentTime
    pausedElapsed = 0
    elapsed = 0
    started = clock.now
    running = true
    repeatSection = false
  }

  func activateSection(_ index: Int) {
    if model.activeSection == index { repeatSection.toggle() }
    else {
      dispatch(.setActiveSection(idx: index))
      repeatSection = false
    }
  }

  func followOutline() {
    dispatch(.setActiveSection(idx: -1))
    repeatSection = false
  }

  func undoAction() { replaceHistory(undo(history)); repeatSection = false }
  func redoAction() { replaceHistory(redo(history)); repeatSection = false }

  func saveTake(_ index: Int, name: String, text: String, tags: [String]) -> Bool {
    guard model.laps.indices.contains(index) else { return false }
    guard let parsedDuration = parseTime(text) else {
      notice = "Enter a duration as minutes:seconds, for example 2:30, or as whole seconds."
      return false
    }
    let previous = model.laps[index].duration
    // Opening an editor displays whole seconds, but merely relabeling a take
    // must preserve the original subsecond measurement.
    let duration = text.trimmingCharacters(in: .whitespacesAndNewlines) == formatTime(previous) ? previous : parsedDuration
    var actions: [Action] = [.labelLap(idx: index, name: name), .adjustDuration(idx: index, duration: duration)]
    for tag in model.laps[index].tags where !tags.contains(tag) { actions.append(.removeTag(idx: index, tag: tag)) }
    for tag in tags { actions.append(.addTag(idx: index, tag: tag)) }
    return transaction(actions)
  }

  func copyMarkdown() {
    let lines = model.laps.filter(\.selected).map { lap in
      let title = lap.section.isEmpty ? "Untitled" : lap.section
      let tags = lap.tags.isEmpty ? "" : " [\(lap.tags.joined(separator: ", "))]"
      return "- [ ] \(title)\(tags) (\(formatTime(lap.duration)))"
    }
    let text = (lines + ["- [ ] Total (\(formatTime(summary.total)))"]).joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    notice = "Selected takes copied as Markdown."
  }

  func importMarkdown(_ text: String) {
    let laps = parseMarkdown(text)
    guard !laps.isEmpty else {
      notice = "No takes found. Use a line such as: - [ ] Introduction [story] (1:30)"
      return
    }
    if dispatch(.importLaps(laps: laps)) {
      notice = "Imported \(laps.count) \(laps.count == 1 ? "take" : "takes")."
    }
  }
}

struct SessionSummary {
  struct Section: Identifiable {
    let id: String
    let count: Int
    let total: Int
    let minimum: Int
    let maximum: Int
  }
  struct Tag: Identifiable {
    let id: String
    let count: Int
    let total: Int
  }

  let total: Int
  let count: Int
  let running: [Int]
  let sections: [Section]
  let tags: [Tag]

  init(laps: [Lap]) {
    total = selectedTotal(laps)
    count = selectedCount(laps)
    running = runningTotals(laps)
    sections = collectAllSections(laps).map { name in
      Section(id: name, count: countBySection(laps, name), total: sumBySection(laps, name),
        minimum: minBySection(laps, name), maximum: maxBySection(laps, name))
    }
    tags = collectAllTags(laps).map { name in
      Tag(id: name, count: countByTag(laps, name), total: sumByTag(laps, name))
    }
  }
}

func formatTime(_ milliseconds: Int) -> String {
  let seconds = max(0, milliseconds) / 1000
  return String(format: "%02ld:%02ld", seconds / 60, seconds % 60)
}

func parseTime(_ text: String) -> Int? {
  let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
  guard (1...2).contains(parts.count),
    parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
  let numbers = parts.compactMap { Int($0) }
  guard numbers.count == parts.count else { return nil }
  let seconds: Int
  if numbers.count == 1 { seconds = numbers[0] }
  else {
    guard numbers[1] < 60 else { return nil }
    let minutes = numbers[0].multipliedReportingOverflow(by: 60)
    guard !minutes.overflow else { return nil }
    let total = minutes.partialValue.addingReportingOverflow(numbers[1])
    guard !total.overflow else { return nil }
    seconds = total.partialValue
  }
  let result = seconds.multipliedReportingOverflow(by: 1000)
  return result.overflow ? nil : result.partialValue
}

func parseMarkdown(_ text: String) -> [Lap] {
  let linePattern = #"^\s*-\s*\[[ xX]\]\s*(.+?)\s*\(([0-9]+:[0-9]+)\)\s*$"#
  let tagPattern = #"^(.+?)\s*\[([^\]]*)\]$"#
  guard let lineRegex = try? NSRegularExpression(pattern: linePattern),
    let tagRegex = try? NSRegularExpression(pattern: tagPattern) else { return [] }
  return text.components(separatedBy: .newlines).compactMap { line in
    let fullRange = NSRange(line.startIndex..., in: line)
    guard let match = lineRegex.firstMatch(in: line, range: fullRange),
      let labelRange = Range(match.range(at: 1), in: line),
      let durationRange = Range(match.range(at: 2), in: line),
      let duration = parseTime(String(line[durationRange])) else { return nil }
    var section = String(line[labelRange]).trimmingCharacters(in: .whitespaces)
    guard section.lowercased() != "total" else { return nil }
    var tags: [String] = []
    if let match = tagRegex.firstMatch(in: section, range: NSRange(section.startIndex..., in: section)),
      let nameRange = Range(match.range(at: 1), in: section),
      let tagsRange = Range(match.range(at: 2), in: section) {
      tags = section[tagsRange].split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces)
      }.filter { !$0.isEmpty }
      section = String(section[nameRange]).trimmingCharacters(in: .whitespaces)
    }
    return Lap(timestamp: 0, duration: duration, section: section, selected: true,
      expectedDuration: -1, tags: tags)
  }
}
