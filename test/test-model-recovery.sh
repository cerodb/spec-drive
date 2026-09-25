#!/usr/bin/env bash
# Deterministic checks for coordinator-recorded recovery classifications and guided evidence.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CASES="$ROOT/test/fixtures/model-recovery/cases.json"
OBSERVATIONS="$ROOT/test/fixtures/model-recovery/rejection.jsonl"
POSITIVE="$ROOT/../evidence/codex-rejection.jsonl"

usage() { echo "Usage: bash test/test-model-recovery.sh [--evidence DIR]" >&2; }
EVIDENCE_DIR=""
if [ "$#" -gt 0 ]; then
  if [ "$#" -ne 2 ] || [ "$1" != "--evidence" ]; then usage; exit 2; fi
  EVIDENCE_DIR="$2"
fi

fail() { echo "FAIL: $*" >&2; exit 1; }
jq empty "$CASES" || fail "cases.json is invalid JSON"
[ -f "$POSITIVE" ] || fail "existing positive rejection capture is missing: $POSITIVE"
grep -q '"type":"turn.started"' "$POSITIVE" || fail "positive capture lost turn.started"
grep -q '"type":"turn.failed"' "$POSITIVE" || fail "positive capture lacks terminal turn.failed"
jq -e '.fixturesAreNotProviderEvidence == true and (.cases|length == 10)' "$CASES" >/dev/null || fail "fixture manifest is incomplete or overclaims provider evidence"

# The actual column is a DispatchResult observation recorded by the coordinator.
# This shell suite compares that record to expected values; it intentionally does not
# implement a second classifier over provider event streams.
jq -s -e --slurpfile expected "$CASES" '
  ($expected[0].cases | map({key: .id, value: .expected}) | from_entries) as $expectedById
  | length == ($expected[0].cases | length) and
  all(.[]; . as $actual | $expectedById[$actual.case] as $want |
      $actual.outcome == $want.outcome and
      $actual.started == $want.started and
      $actual.recoveryAllowed == $want.recoveryAllowed) and
  ([.[].case] | length) == ([.[].case] | unique | length) and
  ([.[].case] | sort) == ([$expected[0].cases[].id] | sort) and
  ([.[] | select(.recoveryAllowed == true)] | length == 1) and
  ([.[] | select(.case == "positive_existing") | .signature] == ["codex-0.156.1-chatgpt-model-rejection-v1"])
' "$OBSERVATIONS" >/dev/null || fail "coordinator classification observations differ from expected C3/C4 outcomes"
echo "PASS: deterministic fixture observations match expected classifications; no provider is called."

if [ -z "$EVIDENCE_DIR" ]; then
  echo "NOTE: this run does not accredit coordinator Markdown integration; pass --evidence DIR after guided captures exist."
  exit 0
fi

for entry in agent.json task.json; do
  [ -s "$EVIDENCE_DIR/$entry" ] || fail "guided evidence missing: $EVIDENCE_DIR/$entry"
done
for entry in agent.json task.json; do
  jq -e '
    .guided == true and .shellReplay == false and
    (.dispatches | type == "number" and . >= 1 and . <= 2) and
    (.choiceQueries | type == "number" and . >= 0 and . <= 1) and
    (.argv | type == "array") and
    ([.argv[] | select(startswith("--"))] | group_by(.) | all(.[]; length == 1)) and
    ([.argv[] | select(. == "--json")] | length == 1) and
    ([.argv[] | select(. == "--skip-git-repo-check")] | length == 1) and
    (.invocations | type == "array") and (.invocations | length) == .dispatches and
    (.decisions | type == "array" and length > 0) and
    (.choice | type == "object") and
    (.samePromptAndUnit == true) and (.preservedAfterInitialRejection == true) and
    (.blockedAfterRestart == true) and
    (.snapshots.before and .snapshots.afterRejection and .snapshots.afterRestart)
  ' "$EVIDENCE_DIR/$entry" >/dev/null || fail "guided evidence assertions failed: $EVIDENCE_DIR/$entry"
done
echo "PASS: Agent and Task guided adapter evidence satisfies dispatch, prompt, state and restart invariants."
