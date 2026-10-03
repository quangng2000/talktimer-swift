# TypeScript / Swift differential case study

`reference/domain.ts` is the unmodified Talk Timer domain from
[`midspiral/talktimer-lemmascript`, commit `2b50d690c64c644698f7ab46f071d8c5d7cd17b2`](https://github.com/midspiral/talktimer-lemmascript/tree/2b50d690c64c644698f7ab46f071d8c5d7cd17b2).
The upstream MIT license is preserved in `reference/LICENSE`. This copy is a
runtime comparison oracle; its annotations are preserved, and it is not a new
LemmaScript proof artifact.

Run from the project root:

```sh
swift test
```

The `ReferenceParityTests` test launches `node parity/generate.mjs`. Node 22.18+
is required for native TypeScript type stripping (tested with Node 26.3.0).
There are no npm dependencies. `NODE_EXECUTABLE=/absolute/path/to/node swift test`
can select another installation. Missing Node is a test failure, so parity
cannot silently disappear from a green test run.

The JavaScript harness imports and executes the original TypeScript. It creates
one directed scenario covering all 17 reducer actions and history boundaries,
plus four deterministic seeded scenarios. Swift replays each command and checks
every field of the entire history and the current model. It also checks selected
durations/count/total, tags, sections, minimum/maximum duration, and running
totals after every command. A checksum pins the oracle bytes to the source used
to establish these expectations.

These are finite runtime comparisons, not a proof of translation correctness.
Times and sums are bounded, integral, and well within JavaScript's safe-integer
range and Swift's `Int` range. Strings use ASCII: JavaScript compares UTF-16 code
units while Swift `String` equality recognizes Unicode canonical equivalence.
Arbitrary Unicode tag deduplication and section matching therefore require an
explicit string model before claiming equivalent behavior for all strings.

The harness exercises the domain only. Browser/SwiftUI rendering, clock delivery,
persistence, import parsing, keyboard handling, and accessibility are outside
these comparisons. The Swift unit tests separately document expected domain
behavior with direct examples; the formal case-study results are reported in
the project documentation.
