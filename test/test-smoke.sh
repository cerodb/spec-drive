#!/usr/bin/env bash
# test-smoke.sh — Smoke test: minimal project creation flow (no LLM, file/state validation only)
set -euo pipefail


echo "-- Legacy no-model task compatibility (PG115)..."
pg115_tmp="$(mktemp -d)"
cat > "$pg115_tmp/tasks.md" <<'EOF_PG115_LEGACY_TASK'
- [ ] 1.1 Legacy task without model field
  - **Do**: Keep backward compatibility for pre-router task blocks.
  - **Files**: `README.md`
  - **Traces**: FR-8
  - **Cwd**: `<repoRoot>`
  - **Done when**: resolver inherits the session model.
  - **Verify**: `true`
  - **Timeout**: `30s`
  - **Commit**: `test: legacy no-model task`
EOF_PG115_LEGACY_TASK
if grep -q 'model:' "$pg115_tmp/tasks.md"; then
  echo "  FAIL: legacy fixture unexpectedly contains model field"
  rm -rf "$pg115_tmp"
  exit 1
fi
pg115_err="$pg115_tmp/resolve-model.err"
pg115_out="$(bash hooks/scripts/resolve-model.sh "" claude-code 2>"$pg115_err")"
if printf '%s\n' "$pg115_out" | grep -qx 'mechanism=inherit' && [ ! -s "$pg115_err" ]; then
  echo "  OK: legacy no-model task resolves to inherit without warnings"
else
  echo "  FAIL: legacy no-model task did not resolve cleanly to inherit"
  printf 'stdout:\n%s\n' "$pg115_out"
  printf 'stderr:\n'
  cat "$pg115_err"
  rm -rf "$pg115_tmp"
  exit 1
fi
rm -rf "$pg115_tmp"

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

# ============================================================================
# Backward-compat and coordinator smoke tests
# ============================================================================

RESOLVE_MODEL_SCRIPT="$PLUGIN_ROOT/hooks/scripts/resolve-model.sh"
SCORE_SCRIPT="$PLUGIN_ROOT/hooks/scripts/coordinator-score.sh"

echo "-- Backward-compat resolver behavior..."
LEGACY_DIR="$TMPDIR_SMOKE/legacy-no-model"
mkdir -p "$LEGACY_DIR"
cat > "$LEGACY_DIR/tasks.md" <<'TASKS_LEGACY'
# Tasks: legacy

## Task 1: Keep legacy tasks valid

- [ ] Preserve tasks.md blocks with no model field
TASKS_LEGACY

if [ ! -x "$RESOLVE_MODEL_SCRIPT" ]; then
  fail "resolve-model.sh is missing or not executable at $RESOLVE_MODEL_SCRIPT"
else
  ok "resolve-model.sh exists and is executable"

  RESOLVE_STDERR="$TMPDIR_SMOKE/resolve-model.stderr"
  RESOLVE_OUT="$(cd "$LEGACY_DIR" && bash "$RESOLVE_MODEL_SCRIPT" "" 2>"$RESOLVE_STDERR")"
  RESOLVE_EXIT=$?

  if [ "$RESOLVE_EXIT" -eq 0 ]; then
    ok "resolver exits 0 when model tier is absent"
  else
    fail "resolver should exit 0 when model tier is absent (got $RESOLVE_EXIT)"
  fi

  if printf '%s\n' "$RESOLVE_OUT" | grep -q '^mechanism=inherit$'; then
    ok "resolver emits mechanism=inherit for absent model tier"
  else
    fail "resolver should emit mechanism=inherit for absent model tier"
  fi

  if [ ! -s "$RESOLVE_STDERR" ]; then
    ok "resolver does not write stderr for absent model tier"
  else
    fail "resolver should not write stderr for absent model tier"
  fi

  PLACEHOLDER_STDERR="$TMPDIR_SMOKE/resolve-model-placeholder.stderr"
  set +e
  PLACEHOLDER_OUT="$(cd "$LEGACY_DIR" && bash "$RESOLVE_MODEL_SCRIPT" light codex 2>"$PLACEHOLDER_STDERR")"
  PLACEHOLDER_EXIT=$?
  set -e

  if [ "$PLACEHOLDER_EXIT" -ne 0 ]; then
    ok "resolver fails fast for unresolved subprocess placeholders"
  else
    fail "resolver should fail when shipped subprocess profile still contains placeholders"
  fi

  if grep -q '^error=unresolved_placeholder$' "$PLACEHOLDER_STDERR"; then
    ok "resolver reports unresolved_placeholder for template stubs"
  else
    fail "resolver should report error=unresolved_placeholder for template stubs"
  fi

  if [ -z "$PLACEHOLDER_OUT" ]; then
    ok "resolver does not emit stdout for unresolved placeholder errors"
  else
    fail "resolver should not emit stdout for unresolved placeholder errors"
  fi
fi

# Coordinator scoring function smoke tests
# Exercise hooks/scripts/coordinator-score.sh against fixtures without an LLM.
# Each fixture asserts a specific (outcome, mode, reason_prefix) triple.

if [ ! -x "$SCORE_SCRIPT" ]; then
  fail "coordinator-score.sh is missing or not executable at $SCORE_SCRIPT"
else
  ok "coordinator-score.sh exists and is executable"

  echo "-- Coordinator fixture 1: clean research -> continue_sequential..."
  F1="$TMPDIR_SMOKE/coord-f1"
  mkdir -p "$F1"
  cat > "$F1/idea.md" <<'IDEA_F1'
# Idea: sample

## Vision

Build a REST API for user management that exposes create, read, update and delete endpoints over HTTP. The API stores users in a SQLite database and uses Node.js with Express as the runtime.

## Constraints

- Node.js 20+
IDEA_F1
  cat > "$F1/research.md" <<'RESEARCH_F1'
# Research: sample

## Executive Summary

- Express with SQLite is a well-known stack
- No major feasibility blockers identified

## External Research

- express.js documentation

## Codebase Analysis

- existing src/ directory uses Express conventions

## Feasibility Assessment

| Component | Effort | Risk | Notes |
|---|---|---|---|
| API handlers | S | L | standard CRUD |

## Open Questions

None identified.
RESEARCH_F1
  printf '{"name":"sample","basePath":"%s","phase":"research"}\n' "$F1" > "$F1/.spec-drive-state.json"

  F1_OUT="$(bash "$SCORE_SCRIPT" "$F1" requirements)"
  if printf '%s\n' "$F1_OUT" | grep -q '^outcome=continue_sequential$'; then
    ok "fixture 1 produced continue_sequential"
  else
    fail "fixture 1 expected continue_sequential, got: $F1_OUT"
  fi
  if printf '%s\n' "$F1_OUT" | grep -q '^signals=none$'; then
    ok "fixture 1 has no ambiguity signals"
  else
    fail "fixture 1 expected signals=none"
  fi

  echo "-- Coordinator fixture 2: ambiguous research -> block_and_escalate..."
  F2="$TMPDIR_SMOKE/coord-f2"
  mkdir -p "$F2"
  cat > "$F2/idea.md" <<'IDEA_F2'
# Idea: sample2

## Vision

Build a thing that helps users manage their tasks and track time spent per task with some kind of reporting dashboard later on.

## Constraints

- unknown
IDEA_F2
  cat > "$F2/research.md" <<'RESEARCH_F2'
# Research: sample2

## Executive Summary

- TBD: stack choice pending
- feasibility depends on integration decisions
- conflicting platform assumptions remain unresolved

## External Research

## Codebase Analysis

## Feasibility Assessment

| Component | Effort | Risk | Notes |
|---|---|---|---|

## Open Questions

- What is the target platform?
- Which database should we use?
RESEARCH_F2
  printf '{"name":"sample2","basePath":"%s","phase":"research"}\n' "$F2" > "$F2/.spec-drive-state.json"

  F2_OUT="$(bash "$SCORE_SCRIPT" "$F2" requirements)"
  if printf '%s\n' "$F2_OUT" | grep -q '^outcome=block_and_escalate$'; then
    ok "fixture 2 produced block_and_escalate"
  else
    fail "fixture 2 expected block_and_escalate, got: $F2_OUT"
  fi
  if printf '%s\n' "$F2_OUT" | grep -q '^reason=high_ambiguity_or_conflict$'; then
    ok "fixture 2 reason is high_ambiguity_or_conflict"
  else
    fail "fixture 2 expected reason=high_ambiguity_or_conflict"
  fi

  echo "-- Coordinator fixture 3: multi-domain idea -> coordinate_research..."
  F3="$TMPDIR_SMOKE/coord-f3"
  mkdir -p "$F3"
  cat > "$F3/idea.md" <<'IDEA_F3'
# Idea: bigstack

## Vision

Build a full platform that includes a backend API for data ingestion written in Go, a frontend React dashboard for analytics, a CLI utility for batch imports, and mobile clients for iOS and Android. The ML model training pipeline runs on infra managed via Terraform and feeds the API.

## Constraints

- Go 1.22+ for backend
- React 18 for frontend
- Node 20 for CLI
- Swift and Kotlin for mobile
- Terraform 1.6+ for infra
IDEA_F3
  printf '{"name":"bigstack-platform","basePath":"%s","phase":"idea"}\n' "$F3" > "$F3/.spec-drive-state.json"

  F3_OUT="$(bash "$SCORE_SCRIPT" "$F3" research)"
  if printf '%s\n' "$F3_OUT" | grep -q '^outcome=coordinate_research$'; then
    ok "fixture 3 produced coordinate_research"
  else
    fail "fixture 3 expected coordinate_research, got: $F3_OUT"
  fi
  if printf '%s\n' "$F3_OUT" | grep -q '^mode=research$'; then
    ok "fixture 3 mode is research"
  else
    fail "fixture 3 expected mode=research"
  fi

  echo "-- Coordinator fixture 4: simple single-domain idea -> continue_sequential..."
  F4="$TMPDIR_SMOKE/coord-f4"
  mkdir -p "$F4"
  cat > "$F4/idea.md" <<'IDEA_F4'
# Idea: simple

## Vision

Build a small command line tool that converts YAML files to JSON using a standard library. The tool reads from stdin and writes to stdout.

## Constraints

- Python 3.11+
IDEA_F4
  printf '{"name":"simple","basePath":"%s","phase":"idea"}\n' "$F4" > "$F4/.spec-drive-state.json"

  F4_OUT="$(bash "$SCORE_SCRIPT" "$F4" research)"
  if printf '%s\n' "$F4_OUT" | grep -q '^outcome=continue_sequential$'; then
    ok "fixture 4 produced continue_sequential"
  else
    fail "fixture 4 expected continue_sequential, got: $F4_OUT"
  fi

  echo "-- Coordinator fixture 5: one real open question -> clarify_first..."
  F5="$TMPDIR_SMOKE/coord-f5"
  mkdir -p "$F5"
  cat > "$F5/idea.md" <<'IDEA_F5'
# Idea: f5

## Vision

Build a REST API for user management with create, read, update, delete endpoints over HTTP using Node and Express.

## Constraints

- Node 20+
IDEA_F5
  cat > "$F5/research.md" <<'RESEARCH_F5'
# Research: f5

## Executive Summary

- Node + Express is standard

## External Research

- Express docs

## Codebase Analysis

- src/ uses Express

## Feasibility Assessment

| Component | Effort | Risk | Notes |
|---|---|---|---|
| API | S | L | standard |

## Open Questions

- Which authentication strategy should the API use?
RESEARCH_F5
  printf '{"name":"f5","basePath":"%s","phase":"research"}\n' "$F5" > "$F5/.spec-drive-state.json"

  F5_OUT="$(bash "$SCORE_SCRIPT" "$F5" requirements)"
  if printf '%s\n' "$F5_OUT" | grep -q '^outcome=clarify_first$'; then
    ok "fixture 5 produced clarify_first"
  else
    fail "fixture 5 expected clarify_first, got: $F5_OUT"
  fi
  if printf '%s\n' "$F5_OUT" | grep -q '^signals=A1$'; then
    ok "fixture 5 has exactly signal A1"
  else
    fail "fixture 5 expected signals=A1"
  fi

  echo "-- Coordinator fixture 6: quoted blocked string should not escalate..."
  F6="$TMPDIR_SMOKE/coord-f6"
  mkdir -p "$F6"
  cat > "$F6/idea.md" <<'IDEA_F6'
# Idea: f6

## Vision

Build a small local wrapper that delegates one focused task to another CLI tool and returns the result safely to the original caller.

## Constraints

- Local-only
IDEA_F6
  cat > "$F6/research.md" <<'RESEARCH_F6'
# Research: f6

## Executive Summary

- Feasible once one remaining naming choice is resolved

## External Research

- local evidence only

## Codebase Analysis

- Existing guard example: `console.error("Recursive cross-agent call blocked")`

## Feasibility Assessment

| Component | Effort | Risk | Notes |
|---|---|---|---|
| Wrapper | S | L | straightforward |

## Open Questions

- Should the wrapper reuse the existing skill name?
RESEARCH_F6
  printf '{"name":"f6","basePath":"%s","phase":"research"}\n' "$F6" > "$F6/.spec-drive-state.json"

  F6_OUT="$(bash "$SCORE_SCRIPT" "$F6" requirements)"
  if printf '%s\n' "$F6_OUT" | grep -q '^outcome=clarify_first$'; then
    ok "fixture 6 produced clarify_first"
  else
    fail "fixture 6 expected clarify_first, got: $F6_OUT"
  fi
  if printf '%s\n' "$F6_OUT" | grep -q '^signals=A1$'; then
    ok "fixture 6 ignores inert quoted blocked string"
  else
    fail "fixture 6 expected signals=A1"
  fi
fi

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
