# Talk Timer: LemmaSwift case-study issues

Assessed 2026-09-23 against LemmaSwift `main` at
[`f1ecb2a75eaa620660ee6a3c40272b94809df242`](https://github.com/midspiral/LemmaSwift/tree/f1ecb2a75eaa620660ee6a3c40272b94809df242).
The reference is Talk Timer for LemmaScript
[`2b50d690c64c644698f7ab46f071d8c5d7cd17b2`](https://github.com/midspiral/talktimer-lemmascript/tree/2b50d690c64c644698f7ab46f071d8c5d7cd17b2).
These are local findings, not automatically filed GitHub issues. IDs are scoped
to this case study.

`Sources/TalkTimerCore/Domain.swift` ports all 57 reference functions and 17
actions. It compiles and passes runtime comparisons. The full configured
verification command currently stops with:

```text
lemmaswift: No verification model for type 'String'
```

No application proof is claimed. The reproductions below isolate later gaps
without changing the real application into easier substitute representations.
All supplied reproductions pass `swiftc -typecheck` first.

| ID | Result | Domain need | Reproduction |
| --- | --- | --- | --- |
| TT-001 | Translation blocked | String fields, labels, and tags | `Verification/StringField.swift` |
| TT-002 | Translation blocked | Copy a record and update a stored property | `Verification/StoredPropertyUpdate.swift` |
| TT-003 | Translation blocked | `allSatisfy` / higher-order collection calls | `Verification/AllSatisfy.swift` |
| TT-004 | Translation blocked | Array slicing and conversion from ArraySlice | `Verification/ArraySlice.swift` |
| TT-005 | Translation blocked | Concatenation / sequence growth | `Verification/ArrayConcatenation.swift` |
| TT-006 | Dafny rejects unsafe program | Aggregate integer overflow | `Verification/AggregateOverflow.swift` |
| TT-007 | Semantic difference | Swift / JavaScript string equality | Documented; no universal parity claim |

## TT-001 — A String field blocks the entire record

`Lap` needs `section: String` and `tags: [String]`. `TemplateEntry`, `Model`,
`History`, and several action payloads transitively depend on these fields.
Even a function that only reads an `Int` duration must model every field of its
reachable record. `StringField.swift` fails with the same missing-model error
as the full application.

Acceptance: preserve actual Swift strings in records and enum payloads, with an
explicit sound equality model for label matching and tag membership. Prove
field reads and representative label/tag operations through the real frontend.
Support in the Dafny backend alone does not satisfy this acceptance criterion.

## TT-002 — Stored-property mutation

The Swift equivalent of TypeScript `{ ...model, currentTime: time }` is a local
value copy followed by `copy.currentTime = time`. This fails with:

```text
lemmaswift: Mutation requires a local variable
```

Acceptance: translate compiler-selected stored-property writes into a value
update while retaining unrelated fields and copy independence. Extend from
direct fields to required property paths deliberately. The case study keeps
the natural Swift update instead of reconstructing every record to bypass it.

## TT-003 — Higher-order collection operations

The reference uses `laps.every(lapValid)` and `history.past.every(inv)`.
Swift's `allSatisfy(nonnegative)` with a named predicate already fails:

```text
lemmaswift: Only compiler-bound free-function calls in Swift bodies are supported
```

Acceptance: preserve standard-library operation identity and model the predicate
call and result. A named predicate is still a function value. Closure support
and collection combinator support require explicit work; neither is implied by
ordinary verified free-function calls. This can follow the String and record
update work.

## TT-004 — Slices used by recursion and history

The port uses `Array(values.dropFirst())` for TypeScript `values.slice(1)`.
The reproduction stops at the array conversion:

```text
lemmaswift: Call target must be a selected verified function: Array
```

This does not establish that `dropFirst` itself is supported: its conversion is
the first observed failure. `dropLast` and indexed slice bounds are also needed
by history and template operations.

Acceptance: model the actual selected slicing and conversion operations and
their bounds. Preserve element order and contents, including record arrays.
Do not replace the production source with a different hand-written algorithm
merely to make this case study pass.

## TT-005 — Array concatenation

The reference uses array spread for append, prepend, and combining slices.
Swift `first + second` currently reports:

```text
lemmaswift: Expression does not match the compiler-required type
```

The isolated example uses small count preconditions, so this is a translation
gap independent of the result-length overflow obligation.

Acceptance: identify Swift's array concatenation, preserve order, and prove
result bounds under `swiftChecked`. Exercise arrays of Lap, Model, and generic
elements. Existing local-array replacement/removal controls are separate.

## TT-006 — Nonnegative is insufficient for bounded integer sums

```swift
//@ requires first >= 0 && second >= 0
//@ ensures \result >= 0
func selectedTotal(_ first: Int, _ second: Int) -> Int {
  return first + second
}
```

The source translates and Dafny rejects the emitted upper-bound assertion.
This is a valid counterexample, not a verifier bug: `Int.max + 1` traps.
The reference uses mathematical integers in its proofs and JavaScript numbers
at runtime. Those proofs cannot establish Swift overflow safety.

Acceptance: choose and enforce a bounded input/sum policy, an explicit checked
result, or another numeric model, then prove its relation to the runtime.
The app refuses UI edits/imports whose nonnegative total cannot fit `Int` to
avoid a rendering crash. That shell validation is not an invariant proof of
the general public core API. The case study keeps `swiftChecked` enabled.

## TT-007 — Unicode equality is different

For example, composed `"é"` and decomposed `"e\u{301}"` compare equal as Swift
strings; their JavaScript UTF-16 sequences differ. Tag uniqueness/removal and
section aggregation can therefore differ even when both runtimes are correct.

Acceptance: decide whether native Swift equality is the intended product
behavior or whether code-unit identity is required. State the chosen text
domain in proof claims. The differential test uses ASCII labels/tags and
bounded integers; it does not hide this mismatch or claim all-input parity.

## What works and what to tackle first

The controls prove a stored Int record, enum payload dispatch, monotonic clock
update, nonnegative time difference, and generic local-array replacement and
removal. Thus basic structs/enums are no longer the first Talk Timer blocker.

The expanded [feature experiment](Verification/TRANSLATION.md) also proves
recursive and mutually recursive algebraic values and a broad Optional subset
in both integer modes. These are isolated feature tests; the production domain
still uses the reference's integer sentinels and does not gain an Optional proof
merely because those tests pass.

Connect String fields first, then stored-property updates and array operations.
Rerun the full domain after each change to discover the next actual failure.
Higher-order collection predicates and full behavioral lemmas can follow.
Any additional limitation discovered after these blockers is resolved should
be recorded with new evidence; this report is not an exhaustive capability audit.

Run `./Verification/run.sh` with `LEMMASWIFT_BIN` pointing at the pinned build.
The runner succeeds only when the recorded positive and negative outcomes are
reproduced, including rejection of a deliberately false contract. A green
baseline report is not a green application verification result.
