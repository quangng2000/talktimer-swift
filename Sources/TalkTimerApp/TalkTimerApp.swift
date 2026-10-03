import AppKit
import SwiftUI
import TalkTimerCore

private let ink = Color(red: 0.18, green: 0.16, blue: 0.28)
private let accent = Color(red: 0.42, green: 0.34, blue: 0.72)
private let teal = Color(red: 0.14, green: 0.48, blue: 0.47)
private let canvas = Color(red: 0.965, green: 0.959, blue: 0.976)

@main
@MainActor
struct TalkTimerApp: App {
  @StateObject private var store = TimerStore()

  var body: some Scene {
    WindowGroup("Talk Timer") {
      TimerView(store: store)
        .frame(minWidth: 930, minHeight: 640)
        .preferredColorScheme(.light)
        .onAppear {
          NSApplication.shared.setActivationPolicy(.regular)
          NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    .defaultSize(width: 1120, height: 790)
    .commands {
      CommandGroup(replacing: .undoRedo) {
        Button("Undo", action: store.undoAction).keyboardShortcut("z").disabled(store.history.past.isEmpty)
        Button("Redo", action: store.redoAction).keyboardShortcut("z", modifiers: [.command, .shift])
          .disabled(store.history.future.isEmpty)
      }
    }
  }
}

private struct TimerView: View {
  @ObservedObject var store: TimerStore
  @State private var importing = false
  @State private var importText = ""
  @State private var confirmingReset = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().opacity(0.4)
      HStack(alignment: .top, spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            stopwatch
            takes
          }.padding(30)
        }
        Divider().opacity(0.4)
        ScrollView { sidebar.padding(24) }.frame(width: 300)
          .background(Color.white.opacity(0.65))
      }
      footer
    }
    .foregroundStyle(ink)
    .background(canvas)
    .tint(accent)
    .task {
      while !Task.isCancelled {
        store.tick()
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
    .sheet(isPresented: $importing) { importSheet }
    .alert("Reset this session?", isPresented: $confirmingReset) {
      Button("Cancel", role: .cancel) { }
      Button("Reset", role: .destructive) { store.reset() }
    } message: {
      Text(store.model.originalTemplate.isEmpty
        ? "This clears the takes and starts a fresh clock. Undo restores the takes; the clock continues."
        : "This restores your original practice outline and starts a fresh clock. Undo restores the takes; the clock continues.")
    }
    .alert("Talk Timer", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
      Button("OK") { store.notice = nil }
    } message: { Text(store.notice ?? "") }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "waveform.path").font(.system(size: 20, weight: .semibold))
        .foregroundStyle(accent).frame(width: 38, height: 38)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 3) {
        Text("Talk Timer").font(.system(size: 17, weight: .semibold))
        Text("Find the rhythm of your next talk.").font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer()
      Button { importText = NSPasteboard.general.string(forType: .string) ?? ""; importing = true } label: {
        Label("Import outline", systemImage: "square.and.arrow.down")
      }.buttonStyle(.bordered).controlSize(.large)
      Menu {
        Button("Undo", action: store.undoAction).disabled(store.history.past.isEmpty)
        Button("Redo", action: store.redoAction).disabled(store.history.future.isEmpty)
        Divider()
        Button("Reset session…", role: .destructive) { confirmingReset = true }
      } label: { Image(systemName: "ellipsis").frame(width: 22) }
        .menuStyle(.borderlessButton).frame(width: 32)
    }.padding(.horizontal, 30).padding(.vertical, 19)
  }

  private var stopwatch: some View {
    VStack(spacing: 14) {
      HStack(spacing: 6) {
        Circle().fill(store.running ? teal : accent.opacity(0.5)).frame(width: 6, height: 6)
        Text(store.running ? "SESSION IN PROGRESS" : "READY WHEN YOU ARE")
          .font(.system(size: 10, weight: .semibold)).tracking(1.8)
          .foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(formatTime(store.elapsed)).font(.system(size: 76, weight: .light, design: .rounded))
          .monospacedDigit().tracking(-3)
        Text(String(format: ".%01d", (store.elapsed % 1000) / 100))
          .font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit()
          .foregroundStyle(accent.opacity(0.55))
      }.accessibilityElement(children: .ignore).accessibilityLabel("Elapsed time \(formatTime(store.elapsed))")
      HStack(spacing: 12) {
        Button(action: store.toggleTimer) {
          Label(store.running ? "Pause" : (store.elapsed == 0 ? "Start timer" : "Resume"),
            systemImage: store.running ? "pause.fill" : "play.fill")
            .frame(width: 115, height: 24)
        }.buttonStyle(.bordered).controlSize(.large)
        Button(action: store.lap) {
          Label("Mark a take", systemImage: "flag.fill").frame(width: 130, height: 24)
        }.buttonStyle(.borderedProminent).controlSize(.large)
          .keyboardShortcut("l", modifiers: .command)
      }
      Text("⌘L to mark a take · the clock keeps running")
        .font(.system(size: 10)).foregroundStyle(.tertiary)
    }.frame(maxWidth: .infinity).padding(.vertical, 25)
      .background(.white, in: RoundedRectangle(cornerRadius: 22))
      .overlay(RoundedRectangle(cornerRadius: 22).stroke(accent.opacity(0.06)))
  }

  private var takes: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Your takes").font(.system(size: 19, weight: .semibold))
        Text("\(store.model.laps.count)").font(.system(size: 11, weight: .medium))
          .padding(.horizontal, 7).padding(.vertical, 3)
          .background(accent.opacity(0.08), in: Capsule())
        Spacer()
        Button(action: store.undoAction) { Image(systemName: "arrow.uturn.backward") }
          .disabled(store.history.past.isEmpty).help("Undo (⌘Z)")
        Button(action: store.redoAction) { Image(systemName: "arrow.uturn.forward") }
          .disabled(store.history.future.isEmpty).help("Redo (⇧⌘Z)")
      }.buttonStyle(.borderless)
      if store.model.laps.isEmpty {
        VStack(spacing: 10) {
          Image(systemName: "text.badge.plus").font(.system(size: 28, weight: .light)).foregroundStyle(accent.opacity(0.55))
          Text("Every good talk starts here.").font(.system(size: 14, weight: .medium))
          Text("Start the clock and mark your first take,\nor import an outline to rehearse.")
            .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 55)
      } else {
        let totals = store.summary.running
        VStack(spacing: 8) {
          ForEach(store.model.laps.indices, id: \.self) { index in
            LapRow(store: store, index: index, lap: store.model.laps[index], cumulative: totals[index])
          }
        }
      }
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 26) {
      VStack(alignment: .leading, spacing: 12) {
        eyebrow("THE BIG PICTURE")
        Text(formatTime(store.summary.total))
          .font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit()
        Text("\(store.summary.count) selected takes · your planned running time")
          .font(.system(size: 11)).foregroundStyle(.secondary)
        Button(action: store.copyMarkdown) { Label("Copy as Markdown", systemImage: "doc.on.doc") }
          .buttonStyle(.bordered).controlSize(.large).disabled(store.summary.count == 0)
      }
      Divider()
      practicePanel
      Divider()
      sectionPanel
      if !store.summary.tags.isEmpty { Divider(); tagPanel }
    }
  }

  private var practicePanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      eyebrow("PRACTICE WITH PURPOSE")
      if store.model.originalTemplate.isEmpty {
        Text("Turn your takes into a rehearsal outline.")
          .font(.system(size: 13, weight: .medium))
        Text("Name your sections, then practice against their timings. Tags travel with each section.")
          .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
        Button(action: store.startPractice) { Label("Start practice", systemImage: "repeat") }
          .buttonStyle(.borderedProminent).controlSize(.large)
          .disabled(!store.model.laps.contains { !$0.section.isEmpty })
      } else {
        Text("Your rehearsal outline").font(.system(size: 13, weight: .medium))
        Text("Choose a section to jump. Choose it again to repeat.")
          .font(.system(size: 11)).foregroundStyle(.secondary)
        Button(action: store.followOutline) {
          Label("Follow outline", systemImage: "list.bullet")
        }.buttonStyle(.bordered).controlSize(.small)
          .disabled(store.model.activeSection < 0)
        ForEach(store.model.originalTemplate.indices, id: \.self) { index in
          let entry = store.model.originalTemplate[index]
          let active = store.model.activeSection == index
          let next = store.model.activeSection < 0 && !store.model.template.isEmpty
            && index == store.model.originalTemplate.count - store.model.template.count
          Button { store.activateSection(index) } label: {
            HStack(spacing: 8) {
              Image(systemName: active && store.repeatSection ? "repeat" : (active || next ? "play.fill" : "circle"))
                .font(.system(size: 9)).frame(width: 12)
              Text(entry.section).lineLimit(2)
              Spacer(minLength: 2)
              Text(formatTime(entry.expectedDuration)).font(.system(size: 10, design: .monospaced))
            }.font(.system(size: 11, weight: active || next ? .semibold : .regular))
              .padding(10).background((active || next ? accent.opacity(0.10) : Color.clear), in: RoundedRectangle(cornerRadius: 8))
          }.buttonStyle(.plain)
        }
      }
    }
  }

  private var sectionPanel: some View {
    VStack(alignment: .leading, spacing: 13) {
      eyebrow("BY SECTION")
      let sections = store.summary.sections
      if sections.isEmpty {
        Text("Section statistics appear as you name and select takes.")
          .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
      }
      ForEach(sections) { section in
        let count = section.count
        let total = section.total
        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Text(section.id).font(.system(size: 11, weight: .medium)).lineLimit(2)
            Spacer()
            Text(formatTime(total)).font(.system(size: 11, weight: .medium, design: .monospaced))
          }
          Text(count > 1
            ? "\(count) takes · avg \(formatTime(total / count)) · best \(formatTime(section.minimum)) · max \(formatTime(section.maximum))"
            : "\(count) selected take")
            .font(.system(size: 9)).foregroundStyle(.secondary)
        }
      }
    }
  }

  private var tagPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      eyebrow("BY TAG")
      ForEach(store.summary.tags) { tag in
        HStack {
          Text(tag.id).font(.system(size: 10, weight: .medium)).foregroundStyle(teal)
            .padding(.horizontal, 8).padding(.vertical, 4).background(teal.opacity(0.08), in: Capsule())
          Spacer()
          Text("\(tag.count) ×").font(.system(size: 10)).foregroundStyle(.tertiary)
          Text(formatTime(tag.total)).font(.system(size: 11, design: .monospaced))
        }
      }
    }
  }

  private var footer: some View {
    HStack {
      Text("A little practice. A clearer story.")
      Spacer()
      Text("Swift case study · see Verification/RESULTS.md")
    }.font(.system(size: 10)).foregroundStyle(.secondary)
      .padding(.horizontal, 30).padding(.vertical, 11)
      .background(accent.opacity(0.035))
  }

  private var importSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Bring your outline").font(.system(size: 22, weight: .semibold))
      Text("Paste Markdown takes below. Existing takes stay in your session.")
        .font(.system(size: 12)).foregroundStyle(.secondary)
      Text("- [ ] Introduction [story] (1:30)")
        .font(.system(size: 11, design: .monospaced)).foregroundStyle(accent)
      TextEditor(text: $importText).font(.system(size: 12, design: .monospaced))
        .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
      HStack {
        Spacer()
        Button("Cancel") { importing = false }.keyboardShortcut(.cancelAction)
        Button("Import takes") { store.importMarkdown(importText); importing = false }
          .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(importText.isEmpty)
      }
    }.padding(26).frame(width: 570, height: 380)
  }

  private func eyebrow(_ text: String) -> some View {
    Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
  }
}

private struct LapRow: View {
  @ObservedObject var store: TimerStore
  let index: Int
  let lap: Lap
  let cumulative: Int
  @State private var editing = false
  @State private var name = ""
  @State private var duration = ""
  @State private var tag = ""
  @State private var draftTags: [String] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 11) {
        Button { store.dispatch(.selectLap(idx: index)) } label: {
          Image(systemName: lap.selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 19)).foregroundStyle(lap.selected ? teal : Color.secondary.opacity(0.4))
        }.buttonStyle(.plain).help(lap.selected ? "Exclude from total" : "Include in total")
        Text(String(format: "%02d", index + 1)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
        VStack(alignment: .leading, spacing: 4) {
          Text(lap.section.isEmpty ? "Untitled take" : lap.section)
            .font(.system(size: 13, weight: .medium)).lineLimit(1)
          if lap.expectedDuration >= 0 {
            let delta = lap.duration - lap.expectedDuration
            Text("Target \(formatTime(lap.expectedDuration)) · \(delta >= 0 ? "+" : "−")\(formatTime(abs(delta)))")
              .font(.system(size: 9)).foregroundStyle(delta > 0 ? .orange : teal)
          } else {
            Text(lap.selected ? "Running total \(formatTime(cumulative))" : "Not included in total")
              .font(.system(size: 9)).foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 4)
        Text(formatTime(lap.duration)).font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
        Button {
          name = lap.section; duration = formatTime(lap.duration); draftTags = lap.tags; tag = ""; editing = true
        } label: { Image(systemName: "pencil").font(.system(size: 11)) }.help("Edit take")
        Menu {
          Button("Move up") { store.dispatch(.moveUp(idx: index)) }.disabled(index == 0)
          Button("Move down") { store.dispatch(.moveDown(idx: index)) }.disabled(index + 1 == store.model.laps.count)
          Divider()
          Button("Delete take", role: .destructive) { store.dispatch(.deleteLap(idx: index)) }
        } label: { Image(systemName: "ellipsis").font(.system(size: 12)) }
          .menuStyle(.borderlessButton).frame(width: 18)
      }.buttonStyle(.borderless)
      if !lap.tags.isEmpty {
        HStack(spacing: 5) {
          ForEach(Array(lap.tags.enumerated()), id: \.offset) { _, tag in
            Text(tag).font(.system(size: 9, weight: .medium)).foregroundStyle(teal)
              .padding(.horizontal, 7).padding(.vertical, 3).background(teal.opacity(0.075), in: Capsule())
          }
        }.padding(.leading, 47)
      }
    }.padding(15).background(.white.opacity(lap.selected ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 13))
      .overlay(RoundedRectangle(cornerRadius: 13).stroke(lap.selected ? teal.opacity(0.15) : .clear))
      .popover(isPresented: $editing, arrowEdge: .trailing) { editor }
      .onChange(of: store.revision) { _, _ in editing = false }
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 13) {
      Text("Edit take \(index + 1)").font(.headline)
      TextField("Section name", text: $name).textFieldStyle(.roundedBorder)
      HStack { Text("Duration").font(.caption); TextField("1:30", text: $duration).textFieldStyle(.roundedBorder) }
      if !draftTags.isEmpty {
        ForEach(Array(draftTags.enumerated()), id: \.offset) { _, value in
          HStack {
            Text(value).font(.caption)
            Spacer()
            Button { draftTags.removeAll { $0 == value } } label: { Image(systemName: "xmark.circle.fill") }
              .buttonStyle(.plain).foregroundStyle(.secondary)
          }
        }
      }
      HStack {
        TextField("Add tag", text: $tag).textFieldStyle(.roundedBorder)
          .onSubmit(addDraftTag)
        Button(action: addDraftTag) { Image(systemName: "plus") }
      }
      HStack {
        Button("Cancel") { editing = false }
        Spacer()
        Button("Save") {
          addDraftTag()
          if store.saveTake(index, name: name, text: duration, tags: draftTags) { editing = false }
        }.buttonStyle(.borderedProminent)
      }
    }.padding(20).frame(width: 290)
  }

  private func addDraftTag() {
    let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty && !draftTags.contains(value) { draftTags.append(value) }
    tag = ""
  }
}
