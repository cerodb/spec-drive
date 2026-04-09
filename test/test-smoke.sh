#!/usr/bin/env bash
# test-smoke.sh — Smoke test: minimal project creation flow (no LLM, file/state validation only)
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

PASS=0
FAIL=0
TMPDIR_SMOKE=""

ok() {
  PASS=$((PASS + 1))
  echo "  OK: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

cleanup() {
  if [ -n "$TMPDIR_SMOKE" ] && [ -d "$TMPDIR_SMOKE" ]; then
    rm -rf "$TMPDIR_SMOKE"
  fi
}
trap cleanup EXIT

echo "=== Spec-Drive Smoke Test ==="

# Setup: create a temp project directory mimicking a real spec-drive project
echo "-- Setup: creating temp project dir..."
TMPDIR_SMOKE="$(mktemp -d)"
SPEC_DIR="$TMPDIR_SMOKE/spec"
mkdir -p "$SPEC_DIR"

PROJECT_NAME="smoke-test-project"
STATE_FILE="$SPEC_DIR/.spec-drive-state.json"
IDEA_FILE="$SPEC_DIR/idea.md"

# AC3: write a valid .spec-drive-state.json with required fields: name, basePath, phase
cat > "$STATE_FILE" <<STATE_EOF
{
  "name": "$PROJECT_NAME",
  "basePath": "$SPEC_DIR",
  "phase": "idea"
}
STATE_EOF

# Write idea.md at expected path
cat > "$IDEA_FILE" <<IDEA_EOF
---
spec: "$PROJECT_NAME"
phase: idea
created: "2026-04-09T00:00:00Z"
---

# Idea: $PROJECT_NAME

## Vision

Smoke test project to validate artifact creation path.

## Constraints

None.
IDEA_EOF

echo "-- Validating state file..."

# AC3: .spec-drive-state.json has required field: name
if jq -e '.name' "$STATE_FILE" >/dev/null 2>&1; then
  ok "state file has 'name' field"
else
  fail "state file missing 'name' field"
fi

# AC3: .spec-drive-state.json has required field: basePath
if jq -e '.basePath' "$STATE_FILE" >/dev/null 2>&1; then
  ok "state file has 'basePath' field"
else
  fail "state file missing 'basePath' field"
fi

# AC3: .spec-drive-state.json has required field: phase
if jq -e '.phase' "$STATE_FILE" >/dev/null 2>&1; then
  ok "state file has 'phase' field"
else
  fail "state file missing 'phase' field"
fi

# Verify field values are non-empty strings
NAME_VAL="$(jq -r '.name' "$STATE_FILE")"
BASEPATH_VAL="$(jq -r '.basePath' "$STATE_FILE")"
PHASE_VAL="$(jq -r '.phase' "$STATE_FILE")"

if [ -n "$NAME_VAL" ] && [ "$NAME_VAL" != "null" ]; then
  ok "name value is non-empty: $NAME_VAL"
else
  fail "name value is empty or null"
fi

if [ -n "$BASEPATH_VAL" ] && [ "$BASEPATH_VAL" != "null" ]; then
  ok "basePath value is non-empty: $BASEPATH_VAL"
else
  fail "basePath value is empty or null"
fi

VALID_PHASES="idea research requirements design tasks execution completed"
PHASE_VALID=false
for p in $VALID_PHASES; do
  if [ "$PHASE_VAL" = "$p" ]; then
    PHASE_VALID=true
    break
  fi
done
if [ "$PHASE_VALID" = "true" ]; then
  ok "phase value is a valid enum: $PHASE_VAL"
else
  fail "phase value '$PHASE_VAL' is not a valid enum value"
fi

echo "-- Validating artifact presence..."

# AC4: idea.md exists at expected path
if [ -f "$IDEA_FILE" ]; then
  ok "idea.md exists at expected path"
else
  fail "idea.md missing from expected path: $IDEA_FILE"
fi

# Validate idea.md has content
if [ -s "$IDEA_FILE" ]; then
  ok "idea.md is non-empty"
else
  fail "idea.md is empty"
fi

# Validate idea.md has frontmatter with spec field
if grep -q "^spec:" "$IDEA_FILE"; then
  ok "idea.md has spec frontmatter field"
else
  fail "idea.md missing spec frontmatter field"
fi

echo "-- Validating state file is valid JSON..."
if jq empty "$STATE_FILE" 2>/dev/null; then
  ok "state file is valid JSON"
else
  fail "state file is not valid JSON"
fi

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
