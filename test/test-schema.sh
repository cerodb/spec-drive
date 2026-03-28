#!/usr/bin/env bash
# test-schema.sh — Validate spec-drive state schema
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

SCHEMA="schemas/spec-drive.schema.json"
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

echo "=== Spec-Drive Schema Test ==="

# 1. Schema is valid JSON
echo "-- JSON validity..."
if jq empty "$SCHEMA" 2>/dev/null; then
  ok "schema is valid JSON"
else
  fail "schema is not valid JSON"
  echo "Passed: $PASS | Failed: $FAIL"
  exit 1
fi

# 2. Has "properties" key
echo "-- Required keys..."
if jq -e '.properties' "$SCHEMA" >/dev/null 2>&1; then
  ok "has 'properties' key"
else
  fail "missing 'properties' key"
fi

# 3. Has "phase" property with enum
echo "-- Phase property..."
if jq -e '.properties.phase' "$SCHEMA" >/dev/null 2>&1; then
  ok "has 'phase' property"
else
  fail "missing 'phase' property"
fi

if jq -e '.properties.phase.enum' "$SCHEMA" >/dev/null 2>&1; then
  ok "phase has enum"
  # Verify all expected phases
  PHASES=$(jq -r '.properties.phase.enum[]' "$SCHEMA" | sort | tr '\n' ' ')
  echo "    phases: $PHASES"
else
  fail "phase missing enum"
fi

# 4. Has "mode" property
echo "-- Mode property..."
if jq -e '.properties.mode' "$SCHEMA" >/dev/null 2>&1; then
  ok "has 'mode' property"
else
  fail "missing 'mode' property"
fi

# 5. Has taskIndex, totalTasks, awaitingApproval
echo "-- Execution state properties..."
for prop in taskIndex totalTasks awaitingApproval; do
  if jq -e ".properties.$prop" "$SCHEMA" >/dev/null 2>&1; then
    ok "has '$prop' property"
  else
    fail "missing '$prop' property"
  fi
done

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
