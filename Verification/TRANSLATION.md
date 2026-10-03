# Algebraic types, Optional, and integer models — actual translation

Tested 2026-09-23 with pinned LemmaSwift
`f1ecb2a75eaa620660ee6a3c40272b94809df242`, Swift 6.3.2, and Dafny 4.11.0.

**All expected outcomes were reproduced across 22 source/model combinations:**
7 successful proofs, 11 deliberate proof failures, and 4 translation refusals.
This does not mean the whole Talk Timer app verifies. The app and its
`swiftChecked` configuration are unchanged; [Features/](Features/) contains
separate experiments, not substitute production implementations.

## Run and inspect

```sh
node Verification/run-features.mjs
# Or select cases:
node Verification/run-features.mjs Optionals ArithmeticUnbounded
```

Set `LEMMASWIFT_BIN` to override the sibling verifier build. The runner snapshots
each source once and gives both modes byte-identical copies. It records source
SHA-256 values, the verifier binary hash, environment, timings, and full logs.

```text
One Swift source snapshot
  ├─ config: swiftChecked
  └─ config: mathematical
          |
          v
  swiftc -typecheck
          |
          v
  lemmaswift check --emit-only
  Compiler/SourceKit facts -> verification IR -> generated Dafny
          |
          v
  dafny verify Proofs/dfyconfig.toml
  -> success, proof failure, or backend error
```

`--emit-only` deliberately retains generated code for inspection even when its
proof will fail. No generated line is hand-edited. A missing Dafny verification
summary is classified as a backend failure, not an expected proof rejection.
Expected proof failures must also match their diagnostic.

Recorded local evidence was in `results/features.YYotlN/`. Raw run directories
are not included in this repository. Rerun the command above to create a fresh
directory, referred to below as `<run>`. Open a case/model's
`Proofs/dfyconfig.toml` for the complete Dafny input: `__LemmaSwiftSupport.dfy`
supplies datatypes/helpers, and the case's `.dfy` supplies translated functions.
The matching `.dfy.gen` is the untouched generated baseline.

## Observed results

| Source / experiment | `swiftChecked` | `mathematical` |
| --- | --- | --- |
| `Algebraic.swift`: 14 selected functions | 48 verified, 0 errors | 33 verified, 0 errors |
| `Optionals.swift`: 15 selected functions | 58 verified, 0 errors | 44 verified, 0 errors |
| `Arithmetic.swift`: 4 selected functions | 34 verified, 0 errors | 20 verified, 0 errors |
| `ArithmeticUnbounded.swift`: nonnegative sum | Overflow proof fails | 17 verified, 0 errors |
| `AlgebraicFalse.swift`: wrong postcondition | Proof fails | Proof fails |
| `RecursiveNontermination.swift`: unchanged recursive argument | Termination proof fails | Termination proof fails |
| `OptionalUnsafe.swift`: unwrap without presence premise | Payload-access proof fails | Payload-access proof fails |
| `ArithmeticZeroDivision.swift`: divisor may be zero | Proof fails | Proof fails |
| `ArithmeticFalse.swift`: wrong arithmetic postcondition | Proof fails | Proof fails |
| `OptionalMap.swift`: Optional.map closure | Translation refused | Translation refused |
| Unchanged `TalkTimerCore/Domain.swift` | String translation refused | String translation refused |

Counts are Dafny verification units, including shared support, not independent
application properties. Do not add them together. All sources pass Swift
typechecking, including negative cases. Negative cases are not run at runtime.

## 1. Algebraic types: products, sums, and recursion

[Algebraic.swift](Features/Algebraic.swift) covers nested structs, different enum
payload products, construction, field projection, copying, whole-value
replacement, matching, arrays of enum values, recursive arrays, both forms of
`indirect`, and structural recursion through mutually recursive record/enum types.

Actual emitted declarations in checked mode include:

```dafny
datatype PlannedLap = MakePlannedLap(seconds: SwiftInt, enabled: bool)
datatype PlannedTalk = MakePlannedTalk(opening: PlannedLap, closing: PlannedLap)
datatype PlanEvent = reset | revised(talk: PlannedTalk, selected: bool, revision: SwiftInt) | history(value0: SwiftArray<PlannedTalk>)
datatype SegmentPlan = done | segment(lap: PlannedLap, remainder: SegmentPlan)
```

A struct becomes one constructor containing all its fields: a **product**.
An enum becomes a choice of constructors with case-specific fields: a **sum of
products**. It is not a universal tag/value record.

Construction calls `MakePlannedTalk(...)`; `talk.opening.seconds` reads datatype
fields. A Swift `switch` becomes `match`, binding payloads within their case.
`finishPlan` recursively calls on the matched remainder, and Dafny proves
structural descent. Calling again with the unchanged argument instead fails
termination. Recursive datatype support does not excuse recursive functions
that never terminate.

The copy experiment explicitly replaces a whole value; it does **not** prove
stored-property-path mutation. Generic nominal types, enum equality, classes,
and cyclic object graphs are not established by these experiments.

After rerunning, inspect `<run>/Algebraic/swiftChecked/Proofs/__LemmaSwiftSupport.dfy`
and `<run>/Algebraic/swiftChecked/Proofs/Algebraic.dfy`.

## 2. Optional: presence and lazy branches

[Optionals.swift](Features/Optionals.swift) covers implicit wrapping,
`Optional(value)`, nested optionals, shorthand `if let` / `guard let`, lazy `??`,
stored-field chaining, optional pattern sugar, safe forced unwrap, implicit
unwrap, and a `while let` countdown with an invariant and decreasing measure.

```dafny
datatype Option<T> = None | Some(value: T)
```

| Swift | Emitted meaning |
| --- | --- |
| `Int?` | `Option<SwiftInt>` or `Option<int>` |
| Return an Int from an Int? function | `Some(seconds)` |
| `nil` as `Int??` | `None` |
| `.some(nil)` as `Int??` | `Some(None)`; the actual output uses a temporary for the inner value |
| `if let` / `guard let` | Test `Some?`, then bind `.value` on the successful path |
| `snapshot?.elapsedSeconds` | Produce `Some(field)` when present; otherwise `None` |
| `snapshot?.targetSeconds`, with an optional field | Return that optional field directly when the snapshot exists |
| `while let` | Reevaluate and bind each iteration, preserving loop proof obligations |

The laziness experiment is:

```swift
//@ verify
//@ ensures \result == 60
func presentTargetSkipsFallback(_ divisor: Int) -> Int {
  let target: Int? = 60
  return target ?? (120 / divisor)
}
```

It has no nonzero-divisor premise. The following excerpt is actual checked
output; the division and its obligations are only in the absent branch:

```dafny
if tmp4.Some? {
  var tmp: SwiftInt := tmp4.value;
  tmp3 := tmp;
} else {
  var tmp5: int := 120;
  assert -9223372036854775808 <= tmp5 <= 9223372036854775807;
  assert divisor != 0;
  assert !(tmp5 == -9223372036854775808 && divisor == -1);
  var tmp6: int := JSTruncDiv(tmp5, divisor);
  assert -9223372036854775808 <= tmp6 <= 9223372036854775807;
  tmp3 := tmp6;
}
```

The target is present, so an unsafe fallback is never executed. Forced unwrap
is different: `.value` needs a presence proof. Omitting the premise in
`OptionalUnsafe.swift` produces a Dafny error that the destructor requires a
value constructed by `Some`. `Optional.map` stops earlier, at translation;
these results do not add closure/combinator support.

After rerunning, inspect `<run>/Optionals/swiftChecked/Proofs/Optionals.dfy`.

## 3. Mathematical integers: a different proof claim

Both modes receive the same [unbounded sum](Features/ArithmeticUnbounded.swift):

```swift
//@ verify
//@ requires first >= 0 && second >= 0
//@ ensures \result == first + second
//@ ensures \result >= 0
func unboundedTotal(_ first: Int, _ second: Int) -> Int {
  return first + second
}
```

Checked mode uses `SwiftInt` parameters/results and emits:

```dafny
var tmp1: int := (first + second);
assert -9223372036854775808 <= tmp1 <= 9223372036854775807;
res0 := tmp1;
```

That assertion fails. Mathematical mode uses unbounded `int` parameters/results:

```dafny
var tmp1: int := (first + second);
res0 := tmp1;
```

The nonnegative-sum theorem now proves, but **Swift overflow safety does not**.
The runtime still uses fixed-width `Int`; this configuration does not make the
app execute with arbitrary-precision numbers.

Additional experiments establish that:

- Bounds of `0...1_000_000` on both operands make the sum prove in both modes.
- `-7 / 3 == -2` and `-7 % 3 == -1` prove in both: truncation-toward-zero helpers
  preserve Swift's rule rather than adopting Dafny's division rule.
- Division by zero and incorrect postconditions are rejected in both modes.
- Specification arithmetic is mathematical in both modes. Returning `value`
  satisfies `result < value + 1`, even at checked input `Int.max`, because that
  addition occurs only in the contract, not in the executable Swift body.

After rerunning, compare `<run>/ArithmeticUnbounded/swiftChecked/Proofs/ArithmeticUnbounded.dfy`
with `<run>/ArithmeticUnbounded/mathematical/Proofs/ArithmeticUnbounded.dfy`.

## Observed cost, not a performance benchmark

One sequential local sample from the final run:

| Group | Checked: translation / Dafny | Mathematical: translation / Dafny |
| --- | --- | --- |
| Algebraic | 1.99 s / 1.39 s | 2.04 s / 1.29 s |
| Optional | 2.02 s / 1.46 s | 2.92 s / 1.48 s |
| Arithmetic | 0.85 s / 1.24 s | 0.81 s / 1.15 s |

Translation includes startup, compiler analysis, IR construction, emission,
and file publication. Dafny time includes startup and shared support, not only
the selected functions. The preliminary standalone Swift typecheck is separately
recorded in `results.json`. Cache/scheduling effects are uncontrolled: these
samples establish no speed ranking, scaling law, or app runtime performance.

The useful result is semantic: all three groups translate and prove the exercised
positive cases; unsafe variants fail at the intended boundary. Neither integer
mode fixes the app's remaining String/operation gaps. The app's existing 32
runtime tests, including 550 reference comparisons, also still pass.
