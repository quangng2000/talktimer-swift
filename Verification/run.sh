#!/usr/bin/env bash
# Green means the recorded pass/fail boundaries were reproduced, not that the
# Talk Timer application was proved. A future newly supported case fails this
# baseline gate so the report must be updated deliberately.
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
verifier=${LEMMASWIFT_BIN:-"$project/../LemmaSwift-case-study-toolchain/tools/.build/debug/lemmaswift"}
test -x "$verifier" || { printf 'Set LEMMASWIFT_BIN to a built lemmaswift executable.\n' >&2; exit 2; }
mkdir -p "$project/Verification/results"
results=$(mktemp -d "$project/Verification/results/run.XXXXXX")
printf 'Evidence: %s\n' "$results"
swift --version > "$results/environment.txt" 2>&1
dafny --version >> "$results/environment.txt"
"$verifier" version >> "$results/environment.txt"

check_case() {
  local name=$1 expected=$2 pattern=${3:-}
  swiftc -typecheck "$project/Verification/$name.swift" > "$results/$name.swift.log" 2>&1
  local status=0
  # Run outside the configured project so a single-file probe stays independent.
  (cd "$results" && "$verifier" check "$project/Verification/$name.swift" \
    --output "$results/$name.dfy") > "$results/$name.log" 2>&1 || status=$?
  if [[ "$expected" == pass ]]; then
    test "$status" -eq 0 || { cat "$results/$name.log"; exit 1; }
    test -f "$results/$name.dfy"
  else
    test "$status" -ne 0 || { printf 'Unexpected proof success: %s; update the baseline.\n' "$name"; exit 1; }
    test ! -e "$results/$name.dfy"
    grep -Eq "$pattern" "$results/$name.log" || { cat "$results/$name.log"; exit 1; }
  fi
  printf '%s\t%s\t%s\n' "$name" "$expected" "$status" >> "$results/outcomes.tsv"
  printf '%s: expected %s reproduced\n' "$name" "$expected"
}

check_case Controls pass
check_case FalseContract proof-failure 'postcondition|could not be proved'
check_case StringField translation-failure "No verification model for type 'String'"
check_case StoredPropertyUpdate translation-failure 'Mutation requires a local variable'
check_case AllSatisfy translation-failure 'Only compiler-bound free-function calls in Swift bodies are supported'
check_case ArraySlice translation-failure 'Call target must be a selected verified function: Array'
check_case ArrayConcatenation translation-failure 'Expression does not match the compiler-required type'
check_case AggregateOverflow proof-failure 'assertion might not hold'

status=0
"$verifier" check --config "$project/lemmaswift.toml" > "$results/TalkTimerCore.log" 2>&1 || status=$?
test "$status" -ne 0 || { printf 'Full domain now verifies; update the case-study report.\n'; exit 1; }
grep -q "No verification model for type 'String'" "$results/TalkTimerCore.log" || {
  cat "$results/TalkTimerCore.log"; exit 1;
}
printf 'TalkTimerCore\ttranslation-failure\t%s\n' "$status" >> "$results/outcomes.tsv"
printf 'TalkTimerCore: known String translation blocker reproduced\n'
printf 'Case-study baseline reproduced; the application is NOT formally verified.\n'
