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
  local candidate

  for candidate in "$container"/.spec-drive-new.*; do
    [ -e "$candidate" ] || continue
    fail "staging residue remains in $container"
    return
  done

  ok "no staging residue remains in $container"
}

assert_exact_core() {
  local project="$1"
  local entry
  local name
  local unexpected=""

  for entry in "$project"/* "$project"/.[!.]* "$project"/..?*; do
    [ -e "$entry" ] || continue
    name="${entry##*/}"
    case "$name" in
      .git|.spec-drive-config.json|spec) ;;
      *) unexpected="${unexpected}${unexpected:+, }$name" ;;
    esac
  done

  for entry in "$project/spec"/* "$project/spec"/.[!.]* "$project/spec"/..?*; do
    [ -e "$entry" ] || continue
    name="${entry##*/}"
    case "$name" in
      idea.md|.progress.md|.spec-drive-state.json) ;;
      *) unexpected="${unexpected}${unexpected:+, }spec/$name" ;;
    esac
  done

  if [ -z "$unexpected" ]; then
    ok "scaffold contains exactly the required core entries"
  else
    fail "scaffold contains unexpected entries: $unexpected"
  fi
}

run_injected_failure() {
  local point="$1"
  local container="$TMP_REGISTRAR/failure-$point"
  local slug="p901-rollback-$point"
  local stderr_file="$TMP_REGISTRAR/failure-$point.err"
  local status

  mkdir -p "$container"
  set +e
  SPEC_DRIVE_CREATE_PROJECT_FAIL_AFTER="$point" bash hooks/scripts/create-project.sh \
    --projects-container "$container" \
    --project-slug "$slug" \
    --goal "Rollback the synthetic $point failure." \
    --mode normal \
    --research-depth standard \
    --created-at "$CREATED_AT" >"$TMP_REGISTRAR/failure-$point.out" 2>"$stderr_file"
  status=$?
  set -e

  if [ "$status" -eq 1 ] && grep -q "injected failure after $point" "$stderr_file"; then
    ok "injected $point failure returns operational exit 1"
  else
    fail "injected $point failure returned status $status or wrong diagnostic"
  fi
  if [ ! -e "$container/$slug" ]; then
    ok "injected $point failure leaves destination absent"
  else
    fail "injected $point failure published a destination"
  fi
  assert_no_staging "$container"
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
PROJECTS="$TMP_REGISTRAR/success-projects"
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
assert_exact_core "$EXPECTED_PATH"

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

if git -C "$EXPECTED_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
   [ "$(git -C "$EXPECTED_PATH" rev-parse --show-toplevel)" = "$EXPECTED_PATH" ]; then
  ok "Git is initialized with the published project as its root"
else
  fail "Git repository was not initialized at the published project root"
fi

assert_no_staging "$PROJECTS"

echo "-- Stdout failure before publish..."
STDOUT_FAIL_SLUG="p902-stdout-fail"
STDOUT_FAIL_PROJECTS="$TMP_REGISTRAR/stdout-failure-projects"
mkdir -p "$STDOUT_FAIL_PROJECTS"
set +e
bash hooks/scripts/create-project.sh \
  --projects-container "$STDOUT_FAIL_PROJECTS" \
  --project-slug "$STDOUT_FAIL_SLUG" \
  --goal "Do not publish if stdout is unavailable." \
  --mode normal \
  --research-depth standard \
  --created-at "$CREATED_AT" >&- 2>"$TMP_REGISTRAR/stdout-fail.err"
STDOUT_FAIL_STATUS=$?
set -e
if [ "$STDOUT_FAIL_STATUS" -ne 0 ] && [ ! -e "$STDOUT_FAIL_PROJECTS/$STDOUT_FAIL_SLUG" ]; then
  ok "stdout failure returns non-zero before destination publish"
else
  fail "stdout failure produced status $STDOUT_FAIL_STATUS with destination existence: $([ -e "$STDOUT_FAIL_PROJECTS/$STDOUT_FAIL_SLUG" ] && printf yes || printf no)"
fi
assert_no_staging "$STDOUT_FAIL_PROJECTS"

echo "-- Existing destination protection..."
EXISTING_PROJECTS="$TMP_REGISTRAR/existing-projects"
EXISTING_PATH="$EXISTING_PROJECTS/$SLUG"
EXISTING_BEFORE="$TMP_REGISTRAR/existing.before"
mkdir -p "$EXISTING_PROJECTS"
cp -R "$EXPECTED_PATH" "$EXISTING_PATH"
cp -R "$EXISTING_PATH" "$EXISTING_BEFORE"
set +e
EXISTING_OUTPUT="$(bash hooks/scripts/create-project.sh \
  --projects-container "$EXISTING_PROJECTS" \
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
if diff -r "$EXISTING_BEFORE" "$EXISTING_PATH" >/dev/null; then
  ok "existing destination tree remains byte-for-byte unchanged"
else
  fail "existing destination was mutated"
fi
assert_no_staging "$EXISTING_PROJECTS"

echo "-- Injected pre-publication failure cleanup matrix..."
for failure_point in write validate git; do
  run_injected_failure "$failure_point"
done

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
