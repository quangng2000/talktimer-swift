# Talk Timer in Swift

## 1. The product

A native macOS rehearsal timer based on
[Talk Timer for LemmaScript](https://github.com/midspiral/talktimer-lemmascript).
Record takes, label them by section, select a final assembly, compare durations,
practice a template, and undo or redo edits. The app is also a case study for
the actual Swift-to-Dafny features a stateful application needs.

## 2. The promise and verification boundary

The intended core guarantees mirror the reference:

1. Time and lap durations are nonnegative. Reducer actions do not decrease
   `currentTime`; undo can restore an earlier snapshot and its earlier time.
2. All 17 actions preserve the model invariant.
3. Lap edits change the intended fields while preserving the others.
4. Practice actions preserve measured duration and timestamp.
5. Import clamps invalid numeric fields and preserves existing laps.
6. Undo/redo preserve valid snapshots and restore the appropriate states.
7. Selected, tag, and section queries describe the selected takes accurately.

These are proof targets for the Swift port. A `//@` comment is a specification,
not evidence that its function has been verified. Current measured support and
failures are recorded in `LS_ISSUES.md` and `Verification/RESULTS.md`.

The SwiftUI interface, clock readings, text parsing/formatting, clipboard,
and application lifecycle are outside the formal proof boundary. Runtime tests
and differential tests against the TypeScript reference provide additional
evidence; they do not transfer the reference's Dafny proofs to Swift.

## 3. The key design insight

The timer model is a value. Each action takes one snapshot and returns another.
History is a sequence of those same snapshots, so undo/redo do not need an
inverse implementation of every edit. Labels and tags remain real Swift
strings, actions remain associated-value enums, and snapshots remain structs.
The case study measures those representations directly.

## 4. Data model

`Sources/TalkTimerCore/Domain.swift` owns the complete data model:

```swift
struct Lap {
  var timestamp: Int
  var duration: Int
  var section: String
  var selected: Bool
  var expectedDuration: Int
  var tags: [String]
}

struct TemplateEntry {
  var section: String
  var expectedDuration: Int
  var tags: [String]
}

struct Model {
  var currentTime: Int
  var lastLapTime: Int
  var laps: [Lap]
  var template: [TemplateEntry]
  var originalTemplate: [TemplateEntry]
  var activeSection: Int
}

struct History {
  var past: [Model]
  var present: Model
  var future: [Model]
}
```

Durations and timestamps are integer milliseconds. `expectedDuration == -1`
means unspecified. `activeSection == -1` selects sequential practice. The
remaining template and original template are separate: consumption advances
the queue, while reset restores all original entries. Array indices identify
takes, following the reference.

The invariant `inv(model)` requires:

- A1: `currentTime >= 0`.
- A2: `0 <= lastLapTime <= currentTime`.
- A3: Every lap has `timestamp >= 0`, `duration >= 0`, and
  `expectedDuration >= -1`.
- A4: `activeSection == -1`, or it is a valid original-template index.

`histInv(history)` requires A1–A4 for present, past, and future snapshots.
No extra restriction on template durations is added: conversion to a lap and
application of an expected duration clamp values as the reference does.

## 5. Architecture

```text
SwiftUI + monotonic clock + clipboard (unverified shell)
              |
              | Actions / query arguments
              v
TalkTimerCore / Domain.swift
  apply + 17 handlers       selected/tag/section queries
  initHistory + doAction + preview + commitFrom + undo + redo
              |
              v
New Swift value snapshots -> SwiftUI renders them

Domain.swift + //@ contracts
              |
              v
Swift compiler -> SourceKit -> LemmaSwift IR -> Dafny
                    current translation gaps -> LS_ISSUES.md

Pinned TypeScript domain -> Node reference runner
              |
              v
Same action traces and queries -> compare with Swift runtime
```

All domain updates use the core. The UI formats values and routes gestures to
actions. A compound gesture can use `preview` followed by `commitFrom` to
make one history entry. That changes undo granularity, not action semantics.
The reference's UI, time source, and clipboard were also outside its proofs.

## 6. Properties: staged catalog

| Family | Property | Swift contract / evidence target |
| --- | --- | --- |
| A: validity | Startup and each action preserve validity | `ensures inv(\result)` |
| A: history | Every stored snapshot stays valid | `ensures histInv(\result)` |
| B: aggregation | Total uses selected durations; tag/section queries filter correctly | Compare source queries and reference results; port behavioral lemmas later |
| C: preservation | Delete/reorder/edit preserve unrelated fields | Per-action runtime assertions and reference traces; proof targets retain full records |
| C: practice | Applying a template leaves measured duration/timestamp unchanged | `ensures \result.laps[i].duration == model.laps[i].duration` with valid index premises |
| D: history | Undo followed by redo restores the complete history when past exists | Fieldwise snapshot tests; nominal equality proof support needed for direct equality |
| E: shell codecs | Markdown import/export carries sections, durations, and tags | Runtime checks; parsing and clipboard remain unverified |

The original annotations are retained in Swift form where applicable. The
reference's separate `domain.proofs.dfy` behavioral lemmas are inventoried as
future Swift proof work; they are not treated as proofs of the port.

## 7. Verification approach

Use LemmaSwift's main branch, pinned to a specific Git commit for
reproducibility. Run actual source typechecking and translation on
the full domain. Isolate unsupported features in small reproductions, alongside
passing controls and a deliberately false contract rejected by Dafny.

Use `swiftChecked` for the Swift experiment. LemmaScript's mathematical integer
proofs do not establish Swift `Int` overflow safety. Nonnegative durations do
not bound their aggregate sum. Runtime parity uses bounded integer inputs;
fractional JavaScript numbers are outside this port's integer input domain.

Use native Swift string semantics. JavaScript compares UTF-16 code units while
Swift `String` equality recognizes canonical equivalence. Canonically equivalent
but differently encoded labels/tags are a documented semantic difference.
Do not silently encode strings as integer IDs or flatten structs to bypass a
translation failure. Do not replace failed obligations with assumptions.

## 8. Roadmap

| Stage | Work | Status |
| --- | --- | --- |
| 0 | Native app and all 17 domain actions | Implemented; runtime validation in results |
| 1 | Pin reference, compare runtime traces, reproduce verifier boundaries | Case study in `Verification/RESULTS.md` |
| 2 | Connect Swift string fields, record updates, and collection operations | Blocked features captured in `LS_ISSUES.md` |
| 3 | Prove `inv` and `histInv` on the complete Swift domain | Not established |
| 4 | Port behavioral and history round-trip lemmas | Not established |

## 9. Open questions and deferred work

The product must eventually choose a numeric input/aggregate bound or a checked
overflow result. Cross-language tag identity needs an explicit product choice
if exact JavaScript string equality is required. Neither issue is hidden behind
the default mathematical Dafny model.

iOS packaging, persistence, a translucent overlay window, full Markdown escaping,
and formal verification of the shell are deferred. This delivery targets macOS;
it does not claim complete UI parity or a verified application.
