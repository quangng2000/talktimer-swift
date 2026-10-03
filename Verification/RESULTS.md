# Case-study results — 2026-09-23

The native Swift app builds and passes its runtime tests. LemmaScript verifies
the original TypeScript domain and its authored proof file. **The complete Swift
domain is not formally verified:** its first translation failure is `String`.
Passing controls and deliberate failures establish that this is a measured
frontend boundary, not a successful application proof.

## Reproducible baselines

| Component | Exercised version |
| --- | --- |
| Talk Timer reference | `2b50d690c64c644698f7ab46f071d8c5d7cd17b2` |
| LemmaScript | npm package `lemmascript@0.6.4` |
| LemmaSwift | `f1ecb2a75eaa620660ee6a3c40272b94809df242` (main, including Optional support) |
| Swift / Xcode | Apple Swift 6.3.2 / Xcode 26.5 |
| SwiftSyntax used by LemmaSwift | 603.0.2 |
| Dafny | 4.11.0 |
| Node | 26.3.0 |
| Host | arm64 macOS 26.0 |

The Swift app has no external package dependencies. The verifier was built from
its pinned source without patches. The reference source and proofs were left
unchanged; its checkout remained clean after generation and verification.

## 1. TypeScript reference

The following commands passed in the pinned reference checkout:

```sh
npm ci --ignore-scripts
npm run typecheck
npm run build
npx --yes --package lemmascript@0.6.4 lsc check
dafny verify --standard-libraries src/domain.proofs.dfy
```

| Check | Observed result |
| --- | --- |
| TypeScript typecheck and production build | Passed |
| LemmaScript generated domain obligations | 108 verified, 0 errors |
| Authored `domain.proofs.dfy` plus included obligations | 123 verified, 0 errors |

There are 65 authored `lemma` declarations in the reference proof file. Dafny's
reported counts are verification units, not a count of independent application
properties; the two totals above overlap and must not be added together.
These results apply to the reference's configured models and proof boundary.
They do not establish Swift overflow safety or prove the Swift port.

The vendored runtime oracle `parity/reference/domain.ts` has SHA-256:

```text
e13f45a6c8a79f1b7a2b0b1dd0fa18c3edde60b66f80f716f980d95f422fa8c8
```

## 2. Swift runtime and UI

```sh
swift test
./run.sh --build-only
./run.sh
```

All **32 tests passed**, with zero failures:

- 14 domain tests cover invariants, edits, practice, aggregation, and history.
- One differential test replays **550 commands** across five scenarios against
  the actual pinned TypeScript implementation, covering all 17 actions plus
  preview/commit/undo/redo. It compares every history snapshot field and the
  aggregate queries after each command.
- 17 app integration tests cover clock/reset behavior, atomic gesture history,
  Markdown import/export, practice, revision/summary updates, edit precision,
  and aggregate-overflow refusal.

Manual native-window checks also passed: import a three-section outline, edit a
section, undo and redo the edit, start practice, record a take with its section
and tag, and pause the clock. These checks are smoke tests, not an exhaustive UI
or accessibility audit.

Parity inputs use ASCII labels/tags and bounded integral milliseconds. Swift
Unicode equality and bounded integers are deliberately documented differences
from JavaScript. The app shell rejects imports/edits with an unrepresentable
total; this runtime safeguard is tested but not formally proved. The public core
still requires representable arithmetic inputs. See TT-006 and TT-007 in
[LS_ISSUES.md](../LS_ISSUES.md).

## 3. Swift verification experiment

Run the baseline with the pinned verifier:

```sh
LEMMASWIFT_BIN=/absolute/path/to/lemmaswift ./Verification/run.sh
```

Every isolated fixture passes `swiftc -typecheck` before the verifier is run.
The runner checks both the exit status and expected diagnostic and requires
that failed proofs do not publish an output artifact. The configured full-domain
check uses the real `Sources/TalkTimerCore/Domain.swift`.

| Input | Observed result |
| --- | --- |
| `Controls.swift` | 41 verified, 0 errors |
| `FalseContract.swift` | Dafny rejects the false postcondition |
| `StringField.swift` | `No verification model for type 'String'` |
| `StoredPropertyUpdate.swift` | `Mutation requires a local variable` |
| `AllSatisfy.swift` | `Only compiler-bound free-function calls in Swift bodies are supported` |
| `ArraySlice.swift` | `Call target must be a selected verified function: Array` |
| `ArrayConcatenation.swift` | `Expression does not match the compiler-required type` |
| `AggregateOverflow.swift` | Dafny rejects an unproved integer-range assertion |
| Full `TalkTimerCore` configured module | `No verification model for type 'String'` |

The control file contains five selected functions: an Int-only stored record,
enum dispatch, nonnegative time difference, generic local-array replacement,
and generic local-array removal. Its verification-unit count includes support
obligations; it does not mean 41 Talk Timer application properties were proved.

The overflow fixture translates successfully. Its failure is expected and
correct: nonnegative operands alone do not make `Int.max + 1` safe.
The other minimal failures report missing translation support. They are
independent probes of app requirements, not an exhaustive list of all remaining
blockers. Rerun the real domain as each blocker is fixed.

The final local baseline run is in `Verification/results/run.sz3SRN/`, including
`environment.txt`, `outcomes.tsv`, per-case logs, and the passing control's Dafny
artifact. Run directories are ignored by Git; rerunning creates fresh evidence.
Future successful application artifacts are configured for `Proofs/TalkTimerCore`.
No full-domain proof was published in this run.

## What this establishes

The port supplies a runnable app and faithful bounded-input runtime evidence
for all reference actions. It demonstrates that basic records, enum payloads,
and selected generic array helpers work in the pinned Swift frontend. It also
supplies concrete failures for the next required features, with acceptance
criteria in [LS_ISSUES.md](../LS_ISSUES.md).

Next: connect Swift String fields, then stored-property mutation and the needed
array operations. Higher-order predicates and the reference's behavioral lemmas
remain later work. No source flattening, trusted reducer, added assumption, or
verifier modification was used to turn the application's failure into success.

## Follow-up: algebraic types, Optional, and idealized mathematics

The [translation experiment](TRANSLATION.md) now exercises all three categories
with the same sources in both integer modes: 22 source/model combinations,
including positive proofs, deliberate proof failures, and translation refusals.
It records generated Dafny and timings without changing the app. The full domain
still encounters the String blocker in both modes; mathematical integers do not
bypass missing frontend operations.
