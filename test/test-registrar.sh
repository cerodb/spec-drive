#!/usr/bin/env bash
# test-registrar.sh — Validate atomic project scaffold behavior.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

PASS=0
FAIL=0
TMP_REGISTRAR=""

ok() {
  PASS=$((PASS + 1))
  echo "  OK: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

cleanup() {
  if [ -n "$TMP_REGISTRAR" ] && [ -d "$TMP_REGISTRAR" ]; then
    rm -rf "$TMP_REGISTRAR"
  fi
}
trap cleanup EXIT

assert_no_staging() {
  local container="$1"
  if find "$container" -maxdepth 1 -name '.spec-drive-new.*' -print -quit | grep -q .; then
    fail "staging residue remains in $container"
  else
    ok "no staging residue remains in $container"
  fi
}

echo "=== Spec-Drive Registrar Test ==="

if bash -n hooks/scripts/create-project.sh 2>/dev/null; then
  ok "create-project.sh passes syntax check"
else
  fail "create-project.sh has syntax errors"
fi

if [ -x hooks/scripts/create-project.sh ]; then
  ok "create-project.sh is executable"
else
  fail "create-project.sh is not executable"
fi

TMP_REGISTRAR="$(mktemp -d)"
PROJECTS="$TMP_REGISTRAR/projects"
SLUG="p900-alpha.registry"
GOAL="Build deterministic registrar coverage with spaces and quoted-safe text."
CREATED_AT="2026-08-07T00:00:00Z"
mkdir -p "$PROJECTS"

echo "-- Successful deterministic scaffold..."
PROJECT_PATH="$(bash hooks/scripts/create-project.sh \
  --projects-container "$PROJECTS" \
  --project-slug "$SLUG" \
  --goal "$GOAL" \
  --mode auto \
  --research-depth deep \
  --created-at "$CREATED_AT")"
EXPECTED_PATH="$(cd "$PROJECTS" && pwd -P)/$SLUG"

if [ "$PROJECT_PATH" = "$EXPECTED_PATH" ] && [ -d "$EXPECTED_PATH" ]; then
  ok "scaffold publishes the project at the requested destination"
else
  fail "scaffold did not publish at expected destination"
fi

for required in \
  "$EXPECTED_PATH/.spec-drive-config.json" \
  "$EXPECTED_PATH/spec/idea.md" \
  "$EXPECTED_PATH/spec/.progress.md" \
  "$EXPECTED_PATH/spec/.spec-drive-state.json" \
  "$EXPECTED_PATH/.git"; do
  if [ -e "$required" ]; then
    ok "required artifact exists: ${required#$EXPECTED_PATH/}"
  else
    fail "required artifact missing: ${required#$EXPECTED_PATH/}"
  fi
done

for optional in audit input output; do
  if [ ! -e "$EXPECTED_PATH/$optional" ]; then
    ok "optional directory is absent: $optional"
  else
    fail "optional directory should not exist: $optional"
  fi
done

if jq -e --arg slug "$SLUG" 'keys == ["projectSlug", "scope"] and .scope == "project" and .projectSlug == $slug' "$EXPECTED_PATH/.spec-drive-config.json" >/dev/null; then
  ok "project config contains exactly portable project identity"
else
  fail "project config content is not exact"
fi

EXPECTED_IDEA="$TMP_REGISTRAR/expected-idea.md"
cat >"$EXPECTED_IDEA" <<EOF
---
spec: "$SLUG"
phase: idea
created: "$CREATED_AT"
---

# Idea: $SLUG

## Vision

$GOAL

## Constraints

<!-- User should fill constraints. Leave section with placeholder comment for now. -->
EOF
if cmp -s "$EXPECTED_IDEA" "$EXPECTED_PATH/spec/idea.md"; then
  ok "idea.md content is deterministic"
else
  fail "idea.md content differs from expected"
fi

EXPECTED_PROGRESS="$TMP_REGISTRAR/expected-progress.md"
cat >"$EXPECTED_PROGRESS" <<EOF
---
spec: "$SLUG"
phase: idea
created: "$CREATED_AT"
---

# Progress: $SLUG

## Original Goal

$GOAL

## Completed Tasks

## Current Task

Research phase starting

## Learnings

## Blockers

None currently

## Next

Research phase
EOF
if cmp -s "$EXPECTED_PROGRESS" "$EXPECTED_PATH/spec/.progress.md"; then
  ok ".progress.md content is deterministic"
else
  fail ".progress.md content differs from expected"
fi

if jq -e \
  --arg name "$SLUG" \
  --arg basePath "$EXPECTED_PATH/spec" \
  '. == {
    name: $name,
    basePath: $basePath,
    phase: "research",
    mode: "auto",
    researchDepth: "deep",
    taskIndex: 0,
    totalTasks: 0,
    taskIteration: 1,
    maxTaskIterations: 5,
    globalIteration: 1,
    maxGlobalIterations: 100,
    awaitingApproval: false,
    taskResults: {}
  }' "$EXPECTED_PATH/spec/.spec-drive-state.json" >/dev/null; then
  ok "state JSON content is deterministic"
else
  fail "state JSON content differs from expected"
fi

assert_no_staging "$PROJECTS"

echo "-- Stdout failure before publish..."
STDOUT_FAIL_SLUG="p902-stdout-fail"
set +e
bash hooks/scripts/create-project.sh \
  --projects-container "$PROJECTS" \
  --project-slug "$STDOUT_FAIL_SLUG" \
  --goal "Do not publish if stdout is unavailable." \
  --mode normal \
  --research-depth standard \
  --created-at "$CREATED_AT" >/dev/full 2>"$TMP_REGISTRAR/stdout-fail.err"
STDOUT_FAIL_STATUS=$?
set -e
if [ "$STDOUT_FAIL_STATUS" -ne 0 ] && [ ! -e "$PROJECTS/$STDOUT_FAIL_SLUG" ]; then
  ok "stdout failure returns non-zero before destination publish"
else
  fail "stdout failure produced status $STDOUT_FAIL_STATUS with destination existence: $([ -e "$PROJECTS/$STDOUT_FAIL_SLUG" ] && printf yes || printf no)"
fi
assert_no_staging "$PROJECTS"

echo "-- Existing destination protection..."
CONFIG_BEFORE="$TMP_REGISTRAR/config.before"
IDEA_BEFORE="$TMP_REGISTRAR/idea.before"
cp "$EXPECTED_PATH/.spec-drive-config.json" "$CONFIG_BEFORE"
cp "$EXPECTED_PATH/spec/idea.md" "$IDEA_BEFORE"
set +e
EXISTING_OUTPUT="$(bash hooks/scripts/create-project.sh \
  --projects-container "$PROJECTS" \
  --project-slug "$SLUG" \
  --goal "Do not overwrite this project." \
  --mode normal \
  --research-depth standard \
  --created-at "2026-08-07T01:00:00Z" 2>&1)"
EXISTING_STATUS=$?
set -e
if [ "$EXISTING_STATUS" -eq 2 ] && printf '%s\n' "$EXISTING_OUTPUT" | grep -q 'destination already exists'; then
  ok "existing destination returns exit 2"
else
  fail "existing destination did not return exit 2"
fi
if cmp -s "$CONFIG_BEFORE" "$EXPECTED_PATH/.spec-drive-config.json" && cmp -s "$IDEA_BEFORE" "$EXPECTED_PATH/spec/idea.md"; then
  ok "existing destination remains unchanged"
else
  fail "existing destination was mutated"
fi
assert_no_staging "$PROJECTS"

echo "-- Injected failure cleanup..."
FAIL_SLUG="p901-rollback"
set +e
FAIL_OUTPUT="$(SPEC_DRIVE_CREATE_PROJECT_FAIL_AFTER=validate bash hooks/scripts/create-project.sh \
  --projects-container "$PROJECTS" \
  --project-slug "$FAIL_SLUG" \
  --goal "Rollback this staged project." \
  --mode normal \
  --research-depth standard \
  --created-at "$CREATED_AT" 2>&1)"
FAIL_STATUS=$?
set -e
if [ "$FAIL_STATUS" -eq 1 ] && printf '%s\n' "$FAIL_OUTPUT" | grep -q 'injected failure'; then
  ok "injected failure returns operational exit 1"
else
  fail "injected failure did not return exit 1"
fi
if [ ! -e "$PROJECTS/$FAIL_SLUG" ]; then
  ok "failed destination is absent"
else
  fail "failed destination should be absent"
fi
assert_no_staging "$PROJECTS"

echo "-- Invalid invocation..."
set +e
bash hooks/scripts/create-project.sh \
  --projects-container "$PROJECTS" \
  --project-slug "../bad" \
  --goal "Bad slug." \
  --mode normal \
  --research-depth standard \
  --created-at "$CREATED_AT" >/dev/null 2>&1
BAD_STATUS=$?
set -e
if [ "$BAD_STATUS" -eq 64 ]; then
  ok "unsafe slug returns exit 64"
else
  fail "unsafe slug returned $BAD_STATUS instead of 64"
fi

echo ""
echo "Registrar tests: $PASS passed, $FAIL failed"

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
