# Talk Timer — Swift / LemmaSwift case study

A native macOS SwiftUI port of
[Talk Timer for LemmaScript](https://github.com/midspiral/talktimer-lemmascript),
with the original domain's 17 actions, practice templates, lap editing,
tags/section statistics, Markdown import/export, and undo/redo.

The Swift app builds and runs. Its domain is compared directly with the pinned
TypeScript implementation. **The full Swift domain is not yet formally
verified:** current LemmaSwift stops at its String fields. See
[LS_ISSUES.md](LS_ISSUES.md) for minimal reproductions and
[Verification/RESULTS.md](Verification/RESULTS.md) for measured evidence.
LemmaScript verifies the TypeScript reference; LemmaSwift is the verifier for
the Swift port.

## Run and debug

Requires macOS 14+ and a Swift 6 toolchain. Tested with Xcode 26.5 / Swift 6.3.2.

```sh
./run.sh
```

This builds and opens `.build/TalkTimer.app`. Use `./run.sh --demo` on a fresh
launch for a sample outline, or `./run.sh --build-only` to build the app bundle.
There are no external Swift package dependencies.

For debugging, open `Package.swift` in Xcode, select the **TalkTimer** executable
scheme and **My Mac**, place a breakpoint in `apply` or `TimerStore.lap`, and
run. `--demo` can be added in Scheme → Run → Arguments. The app requires no CLI
subcommand. Alternatively run `swift run TalkTimer` in Terminal.

Start the timer, use **Mark a take** (⌘L), and edit each take's name, duration,
or tags. Selected takes contribute to the total. Named takes can become a
practice outline; click a section to jump, click again to repeat, or return to
sequential practice. Undo/redo use ⌘Z / ⇧⌘Z.

Reset clears/restores the domain according to the original reducer and restarts
the displayed clock. The Swift shell retains a monotonic offset so a new
session's lap does not stay at zero until it catches up with the old time.
Undo restores model snapshots; it does not rewind or pause the live clock.
Multi-action gestures are one undo entry, using the core's `preview` and
`commitFrom`. This is an intentional UI adaptation from the React app.

Sessions are in memory. Copy Markdown before quitting to retain your selected
takes. iOS packaging, persistent storage, and the overlay window are not part
of this delivery. Markdown uses the reference's simple minute/second format;
it is not a lossless snapshot or millisecond-precision export.

## Runtime tests

```sh
swift test
```

Node 22.18+ is required for the differential test, which runs the original
TypeScript with native type stripping. Missing Node fails that test. No npm
install is needed. The test replays 550 action/history commands, comparing all
snapshot fields and aggregate queries. See [parity/README.md](parity/README.md).

The comparisons use bounded integral milliseconds and ASCII labels/tags.
Native Swift Unicode equality and finite `Int` arithmetic differ from the
reference's JavaScript semantics. Runtime parity tests are finite evidence,
not formal proofs. UI imports and duration edits reject totals that cannot
fit `Int`; the general core API still requires representable numeric inputs.

## Formal case study

Build the exact baseline verifier separately:

```sh
git clone https://github.com/midspiral/LemmaSwift.git ../LemmaSwift-case-study-toolchain
git -C ../LemmaSwift-case-study-toolchain checkout --detach f1ecb2a75eaa620660ee6a3c40272b94809df242
swift build --package-path ../LemmaSwift-case-study-toolchain/tools
./Verification/run.sh
```

If you already have a build, set
`LEMMASWIFT_BIN=/absolute/path/to/lemmaswift`. Dafny 4.11.0 must be on PATH.
The case-study runner tests passing controls, expected translation failures,
and expected proof failures. It writes fresh logs to `Verification/results/`.
Success means the documented support boundary was reproduced.

For algebraic types, Optional, and a same-source comparison of both integer
models, run `node Verification/run-features.mjs`. See the
[translation walkthrough](Verification/TRANSLATION.md) for measured results,
Swift-to-Dafny examples, expected negative cases, and generated output.

To attempt the real application directly:

```sh
../LemmaSwift-case-study-toolchain/tools/.build/debug/lemmaswift check --config lemmaswift.toml
```

This command currently fails at `String` translation. Successful future module
proofs belong in `Proofs/TalkTimerCore`, as configured. The case study neither
patches the verifier nor replaces failing application code with trusted stubs.

## Layout and provenance

| Path | Responsibility |
| --- | --- |
| `Sources/TalkTimerCore/Domain.swift` | All 57 ported domain functions and annotations |
| `Sources/TalkTimerApp/` | SwiftUI, clock, clipboard, and text-formatting shell |
| `Tests/` | Runtime properties, reference parity, and app integration tests |
| `parity/reference/domain.ts` | Unchanged TypeScript oracle at pinned commit |
| `Verification/` | Positive/negative reproductions and recorded results |
| `DESIGN.md` | Data model, proof targets, boundaries, and staged work |
| `LS_ISSUES.md` | Measured implementation gaps and acceptance criteria |

Upstream reference commit:
[`2b50d690c64c644698f7ab46f071d8c5d7cd17b2`](https://github.com/midspiral/talktimer-lemmascript/tree/2b50d690c64c644698f7ab46f071d8c5d7cd17b2).
The original MIT license is preserved. The reference source and proofs were
not weakened to obtain a passing check.
