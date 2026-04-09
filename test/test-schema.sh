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
  if jq -e '.properties.phase.enum | index("completed")' "$SCHEMA" >/dev/null 2>&1; then
    ok "phase enum includes completed"
  else
    fail "phase enum missing completed"
  fi
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

# 6. Has requirementsSha and designSha staleness fields
echo "-- Staleness SHA fields..."
if jq -e '.properties.requirementsSha' "$SCHEMA" >/dev/null 2>&1; then
  ok "has 'requirementsSha' property"
else
  fail "missing 'requirementsSha' property"
fi

if jq -e '.properties.requirementsSha.type == "string"' "$SCHEMA" >/dev/null 2>&1; then
  ok "requirementsSha is type string"
else
  fail "requirementsSha is not type string"
fi

if jq -e '.properties.requirementsSha.description | test("requirements\\.md")' "$SCHEMA" >/dev/null 2>&1; then
  ok "requirementsSha description references requirements.md"
else
  fail "requirementsSha description missing requirements.md reference"
fi

if jq -e '.properties.designSha' "$SCHEMA" >/dev/null 2>&1; then
  ok "has 'designSha' property"
else
  fail "missing 'designSha' property"
fi

if jq -e '.properties.designSha.type == "string"' "$SCHEMA" >/dev/null 2>&1; then
  ok "designSha is type string"
else
  fail "designSha is not type string"
fi

if jq -e '.properties.designSha.description | test("design\\.md")' "$SCHEMA" >/dev/null 2>&1; then
  ok "designSha description references design.md"
else
  fail "designSha description missing design.md reference"
fi

# 7. requirementsSha and designSha are NOT in required array (optional fields)
echo "-- SHA fields are optional..."
if jq -e '.required | index("requirementsSha") | not' "$SCHEMA" >/dev/null 2>&1; then
  ok "requirementsSha is optional (not in required)"
else
  fail "requirementsSha should not be in required array"
fi

if jq -e '.required | index("designSha") | not' "$SCHEMA" >/dev/null 2>&1; then
  ok "designSha is optional (not in required)"
else
  fail "designSha should not be in required array"
fi

# 8. Existing required properties unchanged
echo "-- Existing required properties unchanged..."
for prop in name basePath phase; do
  if jq -e ".required | index(\"$prop\")" "$SCHEMA" >/dev/null 2>&1; then
    ok "required still includes '$prop'"
  else
    fail "required missing '$prop'"
  fi
done

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
