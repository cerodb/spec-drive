#!/usr/bin/env bash
# test-routing.sh — Ensure routing reference fixtures are documented as planner examples.
#
# The actual router is the LLM planner applying agents/task-planner.md Step 3.5.
# This test intentionally does NOT implement a parallel Bash router. It verifies that
# the public fixtures remain present and are mirrored as few-shot/reference examples
# in the real planner prompt, avoiding a false deterministic quality gate.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

FIXTURE_DIR="test/fixtures/routing"
PLANNER="agents/task-planner.md"
PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  echo "  OK: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

echo "=== Routing Reference Consistency Test ==="

if grep -q '#### Routing reference examples' "$PLANNER"; then
  ok "task-planner includes routing reference examples"
else
  fail "task-planner is missing routing reference examples"
fi

count=0
for fixture in "$FIXTURE_DIR"/*.md; do
  count=$((count + 1))
  base="$(basename "$fixture" .md)"
  expected="$(sed -n 's/^expected_tier:[[:space:]]*//p' "$fixture" | head -n 1)"
  example_id="$base"

  if [ -z "$expected" ]; then
    fail "$base missing expected_tier"
    continue
  fi

  case "$expected" in
    light|standard|advanced|frontier) ok "$base has valid expected_tier=$expected" ;;
    *) fail "$base has invalid expected_tier=$expected" ;;
  esac

  if grep -E "\| \`$example_id\` .* \| \`$expected\` \|" "$PLANNER" >/dev/null; then
    ok "$base is represented in task-planner examples with expected tier"
  else
    fail "$base expected tier is not represented in the same task-planner example row"
  fi
done

if [ "$count" -ge 8 ]; then
  ok "at least 8 routing fixtures are present"
else
  fail "expected at least 8 routing fixtures, found $count"
fi

echo ""
echo "Fixtures: $count | Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
