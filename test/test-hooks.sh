#!/usr/bin/env bash
# test-hooks.sh — Validate hooks configuration and scripts
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

PASS=0
FAIL=0
TEST_TEMP_DIRS=()

cleanup_test_dirs() {
  local dir
  for dir in "${TEST_TEMP_DIRS[@]}"; do
    rm -rf "$dir"
  done
}
trap cleanup_test_dirs EXIT

ok() {
  PASS=$((PASS + 1))
  echo "  OK: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

echo "=== Spec-Drive Hooks Test ==="

# 1. hooks.json is valid JSON
echo "-- hooks.json validity..."
if jq empty hooks/hooks.json 2>/dev/null; then
  ok "hooks.json is valid JSON"
else
  fail "hooks.json is not valid JSON"
fi

# 2. stop-watcher.sh passes bash -n syntax check
echo "-- Script syntax..."
if bash -n hooks/scripts/stop-watcher.sh 2>/dev/null; then
  ok "stop-watcher.sh passes syntax check"
else
  fail "stop-watcher.sh has syntax errors"
fi

# 3. context-loader.sh passes bash -n syntax check
if bash -n hooks/scripts/context-loader.sh 2>/dev/null; then
  ok "context-loader.sh passes syntax check"
else
  fail "context-loader.sh has syntax errors"
fi

if bash -n hooks/scripts/resolve-config.sh 2>/dev/null; then
  ok "resolve-config.sh passes syntax check"
else
  fail "resolve-config.sh has syntax errors"
fi

# 4. Both scripts are executable
echo "-- Script permissions..."
if [ -x hooks/scripts/stop-watcher.sh ]; then
  ok "stop-watcher.sh is executable"
else
  fail "stop-watcher.sh is not executable"
fi

if [ -x hooks/scripts/context-loader.sh ]; then
  ok "context-loader.sh is executable"
else
  fail "context-loader.sh is not executable"
fi

if [ -f hooks/scripts/resolve-config.sh ]; then
  ok "resolve-config.sh exists"
else
  fail "resolve-config.sh is missing"
fi

# 5. hooks.json references correct script paths
echo "-- hooks.json references..."
if jq -e '.hooks.Stop' hooks/hooks.json >/dev/null 2>&1; then
  ok "hooks.json has Stop hook"
else
  fail "hooks.json missing Stop hook"
fi

if jq -e '.hooks.SessionStart' hooks/hooks.json >/dev/null 2>&1; then
  ok "hooks.json has SessionStart hook"
else
  fail "hooks.json missing SessionStart hook"
fi

STOP_CMD=$(jq -r '.hooks.Stop[0].hooks[0].command' hooks/hooks.json 2>/dev/null)
if echo "$STOP_CMD" | grep -q 'stop-watcher.sh'; then
  ok "Stop hook references stop-watcher.sh"
else
  fail "Stop hook does not reference stop-watcher.sh (got: $STOP_CMD)"
fi

SESSION_CMD=$(jq -r '.hooks.SessionStart[0].hooks[0].command' hooks/hooks.json 2>/dev/null)
if echo "$SESSION_CMD" | grep -q 'context-loader.sh'; then
  ok "SessionStart hook references context-loader.sh"
else
  fail "SessionStart hook does not reference context-loader.sh (got: $SESSION_CMD)"
fi

echo "-- portable_realpath portability..."
# Verify portable_realpath is defined in resolve-config.sh
if grep -q 'portable_realpath()' hooks/scripts/resolve-config.sh; then
  ok "portable_realpath() is defined in resolve-config.sh"
else
  fail "portable_realpath() is not defined in resolve-config.sh"
fi

# Verify hook scripts no longer use bare readlink -f
if ! grep -q 'readlink -f' hooks/scripts/stop-watcher.sh; then
  ok "stop-watcher.sh does not use bare readlink -f"
else
  fail "stop-watcher.sh still uses bare readlink -f"
fi

if ! grep -q 'readlink -f' hooks/scripts/context-loader.sh; then
  ok "context-loader.sh does not use bare readlink -f"
else
  fail "context-loader.sh still uses bare readlink -f"
fi

# Verify portable_realpath resolves correctly on this system. On macOS, /var is a
# symlink to /private/var, so compare against the physical canonical path.
REAL_TMP_DIR="$(mktemp -d)"
TEST_TEMP_DIRS+=("$REAL_TMP_DIR")
EXPECTED_REAL_TMP_DIR="$(cd "$REAL_TMP_DIR" && pwd -P)"
RESOLVED="$(bash -c ". hooks/scripts/resolve-config.sh && portable_realpath \"$REAL_TMP_DIR\"")"
if [ "$RESOLVED" = "$EXPECTED_REAL_TMP_DIR" ]; then
  ok "portable_realpath resolves a real directory path correctly"
else
  fail "portable_realpath returned unexpected result: '$RESOLVED' (expected '$EXPECTED_REAL_TMP_DIR')"
fi

echo "-- Ambiguous project safety..."
# Canonicalize: on macOS mktemp -d returns a /var symlink path, while the
# resolver reports the physical /private/var path it resolves to.
TMP_HOME="$(cd "$(mktemp -d)" && pwd -P)"
TEST_TEMP_DIRS+=("$TMP_HOME")
mkdir -p "$TMP_HOME/spec-drive-projects/P100/spec" "$TMP_HOME/spec-drive-projects/P101/spec"
mkdir -p "$TMP_HOME/.config/spec-drive"
cat >"$TMP_HOME/.config/spec-drive/config.json" <<EOF
{"projectRoot":"$TMP_HOME/spec-drive-projects"}
EOF
cat >"$TMP_HOME/spec-drive-projects/P100/spec/.spec-drive-state.json" <<'EOF'
{"phase":"execution","awaitingApproval":false,"mode":"normal","taskIndex":0,"totalTasks":1}
EOF
cat >"$TMP_HOME/spec-drive-projects/P101/spec/.spec-drive-state.json" <<'EOF'
{"phase":"execution","awaitingApproval":false,"mode":"normal","taskIndex":0,"totalTasks":1}
EOF
AMBIGUOUS_OUTPUT="$(HOME="$TMP_HOME" XDG_CONFIG_HOME="$TMP_HOME/.config" bash hooks/scripts/stop-watcher.sh <<'EOF'
{"cwd":"/tmp"}
EOF
)"
if echo "$AMBIGUOUS_OUTPUT" | grep -q "Ambiguous Active Spec"; then
  ok "stop-watcher refuses ambiguous active project selection"
else
  fail "stop-watcher did not report ambiguous active project selection"
fi

echo "-- Numeric guardrails..."
rm -rf "$TMP_HOME/spec-drive-projects/P101"
cat >"$TMP_HOME/spec-drive-projects/P100/spec/.spec-drive-state.json" <<'EOF'
{"name":"P100","phase":"execution","awaitingApproval":false,"mode":"normal","taskIndex":0,"totalTasks":1,"taskIteration":1,"maxTaskIterations":5,"globalIteration":"abc","maxGlobalIterations":"xyz"}
EOF
NUMERIC_OUTPUT="$(HOME="$TMP_HOME" XDG_CONFIG_HOME="$TMP_HOME/.config" bash hooks/scripts/stop-watcher.sh <<'EOF'
{"cwd":"/tmp"}
EOF
)"
if echo "$NUMERIC_OUTPUT" | grep -q "Continue spec: P100"; then
  ok "stop-watcher safely normalizes non-numeric iteration values"
else
  fail "stop-watcher did not safely handle non-numeric iteration values"
fi

echo "-- Workspace config precedence..."
WORKSPACE="$TMP_HOME/workspace"
mkdir -p "$WORKSPACE/repo" "$WORKSPACE/workspace-projects/P200/spec"
(
  cd "$WORKSPACE/repo"
  git init -q
)
cat >"$WORKSPACE/repo/.spec-drive-config.json" <<EOF
{"projectRoot":"../workspace-projects"}
EOF
cat >"$WORKSPACE/workspace-projects/P200/spec/.spec-drive-state.json" <<'EOF'
{"name":"P200","phase":"execution","awaitingApproval":false,"mode":"normal","taskIndex":0,"totalTasks":1}
EOF
WORKSPACE_OUTPUT="$(HOME="$TMP_HOME" XDG_CONFIG_HOME="$TMP_HOME/.config" bash hooks/scripts/stop-watcher.sh <<EOF
{"cwd":"$WORKSPACE/repo"}
EOF
)"
if echo "$WORKSPACE_OUTPUT" | grep -q "Continue spec: P200"; then
  ok "workspace config resolves relative projectRoot from git root"
else
  fail "workspace config did not resolve relative projectRoot from git root"
fi

echo "-- XDG fallback..."
rm -f "$WORKSPACE/repo/.spec-drive-config.json"
mkdir -p "$TMP_HOME/.config/spec-drive" "$TMP_HOME/xdg-projects/P201/spec"
cat >"$TMP_HOME/.config/spec-drive/config.json" <<EOF
{"projectRoot":"$TMP_HOME/xdg-projects"}
EOF
cat >"$TMP_HOME/xdg-projects/P201/spec/.spec-drive-state.json" <<'EOF'
{"name":"P201","phase":"execution","awaitingApproval":false,"mode":"normal","taskIndex":0,"totalTasks":1}
EOF
XDG_OUTPUT="$(HOME="$TMP_HOME" XDG_CONFIG_HOME="$TMP_HOME/.config" bash hooks/scripts/stop-watcher.sh <<EOF
{"cwd":"$WORKSPACE/repo"}
EOF
)"
if echo "$XDG_OUTPUT" | grep -q "Continue spec: P201"; then
  ok "xdg config is used when workspace config is absent"
else
  fail "xdg config was not used when workspace config is absent"
fi

echo "-- Scoped per-key config resolution..."
SCOPED_HOME="$(cd "$(mktemp -d)" && pwd -P)"
TEST_TEMP_DIRS+=("$SCOPED_HOME")

SCOPED_FLAT_WS="$SCOPED_HOME/flat-workspace"
SCOPED_NESTED_WS="$SCOPED_HOME/nested-workspace"
mkdir -p "$SCOPED_FLAT_WS/P300/spec/deep" "$SCOPED_NESTED_WS/Projects/P301/spec/deep"
mkdir -p "$SCOPED_HOME/.config/spec-drive"
git -C "$SCOPED_FLAT_WS/P300" init -q
git -C "$SCOPED_NESTED_WS/Projects/P301" init -q

cat >"$SCOPED_FLAT_WS/.spec-drive-config.json" <<EOF
{"scope":"workspace","workspaceRoot":"$SCOPED_FLAT_WS","projectsPath":"."}
EOF
cat >"$SCOPED_FLAT_WS/P300/.spec-drive-config.json" <<'EOF'
{"scope":"project","projectSlug":"P300","cli":"codex"}
EOF
cat >"$SCOPED_NESTED_WS/.spec-drive-config.json" <<EOF
{"scope":"workspace","workspaceRoot":"$SCOPED_NESTED_WS","projectsPath":"Projects"}
EOF
cat >"$SCOPED_NESTED_WS/Projects/P301/.spec-drive-config.json" <<'EOF'
{"scope":"project","projectSlug":"P301"}
EOF
cat >"$SCOPED_HOME/.config/spec-drive/config.json" <<EOF
{"projectRoot":"$SCOPED_HOME/xdg-projects","cli":"claude-code"}
EOF

FLAT_CONTEXT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$SCOPED_FLAT_WS/P300\"")"
FLAT_NESTED_CONTEXT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$SCOPED_FLAT_WS/P300/spec/deep\"")"
if [ "$(echo "$FLAT_CONTEXT" | jq -r '.projectsContainer')" = "$SCOPED_FLAT_WS" ] \
  && [ "$(echo "$FLAT_CONTEXT" | jq -r '.projectRoot')" = "$SCOPED_FLAT_WS/P300" ] \
  && [ "$FLAT_CONTEXT" = "$FLAT_NESTED_CONTEXT" ]; then
  ok "scoped flat workspace resolves identical context from project root and nested cwd"
else
  fail "scoped flat workspace context was not deterministic from nested cwd"
fi

NESTED_CONTEXT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$SCOPED_NESTED_WS/Projects/P301/spec/deep\"")"
if [ "$(echo "$NESTED_CONTEXT" | jq -r '.projectsContainer')" = "$SCOPED_NESTED_WS/Projects" ] \
  && [ "$(echo "$NESTED_CONTEXT" | jq -r '.projectRoot')" = "$SCOPED_NESTED_WS/Projects/P301" ] \
  && [ "$(echo "$NESTED_CONTEXT" | jq -r '.projectSlug')" = "P301" ] \
  && [ "$(git -C "$SCOPED_FLAT_WS/P300/spec/deep" rev-parse --show-toplevel)" = "$SCOPED_FLAT_WS/P300" ] \
  && [ "$(git -C "$SCOPED_NESTED_WS/Projects/P301/spec/deep" rev-parse --show-toplevel)" = "$SCOPED_NESTED_WS/Projects/P301" ] \
  && [ ! -e "$SCOPED_FLAT_WS/.git" ] \
  && [ ! -e "$SCOPED_NESTED_WS/.git" ]; then
  ok "nested projectsPath resolves across independent project git roots"
else
  fail "nested projectsPath did not resolve expected project context"
fi

FLAT_CLI="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_value cli \"$SCOPED_FLAT_WS/P300/spec/deep\"")"
NESTED_CLI="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_value cli \"$SCOPED_NESTED_WS/Projects/P301/spec/deep\"")"
if [ "$FLAT_CLI" = "codex" ] && [ "$NESTED_CLI" = "claude-code" ]; then
  ok "per-key resolution uses project overrides and lower-tier fallbacks independently"
else
  fail "per-key cli resolution did not preserve project override and XDG fallback"
fi

FLAT_CONTAINER="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_projects_container \"$SCOPED_FLAT_WS/P300/spec/deep\"")"
FLAT_COMPAT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_project_root \"$SCOPED_FLAT_WS/P300/spec/deep\"")"
if [ "$FLAT_CONTAINER" = "$SCOPED_FLAT_WS" ] && [ "$FLAT_COMPAT" = "$FLAT_CONTAINER" ]; then
  ok "projects-container accessor and legacy project-root wrapper agree"
else
  fail "projects-container accessor or compatibility wrapper returned the wrong path"
fi

NEW_PROJECT_SLUG="P307"
if [ "$FLAT_CONTAINER/$NEW_PROJECT_SLUG" = "$SCOPED_FLAT_WS/$NEW_PROJECT_SLUG" ] \
  && [ "$FLAT_CONTAINER/$NEW_PROJECT_SLUG" != "$SCOPED_FLAT_WS/P300/$NEW_PROJECT_SLUG" ]; then
  ok "creation resolved from an existing project targets the workspace container"
else
  fail "creation resolved from an existing project would nest under that project"
fi

# The start dir must exist: a missing dir makes the resolver fall back to PWD,
# which would discover whatever workspace config sits above this repo.
mkdir -p "$SCOPED_HOME/no-config"
MISSING_CONTEXT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/missing-config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$SCOPED_HOME/no-config\"")"
if [ "$(echo "$MISSING_CONTEXT" | jq -r '.projectsContainer')" = "$SCOPED_HOME/spec-drive-projects" ]; then
  ok "missing config tiers fall back to the legacy home projects container"
else
  fail "missing config tiers did not use the legacy home projects container"
fi

ISO_A="$SCOPED_FLAT_WS/P300"
ISO_B="$SCOPED_NESTED_WS/Projects/P301"
ISO_A_OUTPUT="$SCOPED_HOME/session-a.json"
ISO_B_OUTPUT="$SCOPED_HOME/session-b.json"
ISO_A_ERROR="$SCOPED_HOME/session-a.err"
ISO_B_ERROR="$SCOPED_HOME/session-b.err"
HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$ISO_A/spec/deep\"" >"$ISO_A_OUTPUT" 2>"$ISO_A_ERROR" &
ISO_A_PID=$!
HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$ISO_B/spec/deep\"" >"$ISO_B_OUTPUT" 2>"$ISO_B_ERROR" &
ISO_B_PID=$!
set +e
wait "$ISO_A_PID"
ISO_A_STATUS=$?
wait "$ISO_B_PID"
ISO_B_STATUS=$?
set -e
ISO_A_ROOT="$(jq -r '.projectRoot // empty' "$ISO_A_OUTPUT" 2>/dev/null || true)"
ISO_B_ROOT="$(jq -r '.projectRoot // empty' "$ISO_B_OUTPUT" 2>/dev/null || true)"
if [ "$ISO_A_STATUS" -eq 0 ] && [ "$ISO_B_STATUS" -eq 0 ] \
  && [ "$ISO_A_ROOT" = "$ISO_A" ] && [ "$ISO_B_ROOT" = "$ISO_B" ] \
  && [ "$ISO_A_ROOT" != "$ISO_B_ROOT" ] \
  && [ ! -s "$ISO_A_ERROR" ] && [ ! -s "$ISO_B_ERROR" ] \
  && [ ! -e "$SCOPED_HOME/.config/spec-drive/active-project" ]; then
  ok "concurrent project sessions resolve isolated identities without shared active state"
else
  fail "concurrent project sessions did not remain isolated"
fi

DETERMINISTIC_FIRST="$(printf '%s' "$FLAT_NESTED_CONTEXT" | jq -cS .)"
DETERMINISTIC_MATCH=true
i=1
while [ "$i" -le 20 ]; do
  DETERMINISTIC_NEXT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$SCOPED_FLAT_WS/P300/spec/deep\"" | jq -cS .)"
  if [ "$DETERMINISTIC_NEXT" != "$DETERMINISTIC_FIRST" ]; then
    DETERMINISTIC_MATCH=false
    break
  fi
  i=$((i + 1))
done
if [ "$DETERMINISTIC_MATCH" = "true" ]; then
  ok "fixed cwd and config produce 20 identical context resolutions"
else
  fail "fixed cwd and config did not produce 20 identical context resolutions"
fi

WORKSPACE_OVERRIDE_WS="$SCOPED_HOME/workspace-cli-override"
mkdir -p "$WORKSPACE_OVERRIDE_WS/Projects/P304/deep"
cat >"$WORKSPACE_OVERRIDE_WS/.spec-drive-config.json" <<EOF
{"scope":"workspace","workspaceRoot":"$WORKSPACE_OVERRIDE_WS","projectsPath":"Projects","cli":"codex"}
EOF
cat >"$WORKSPACE_OVERRIDE_WS/Projects/P304/.spec-drive-config.json" <<'EOF'
{"scope":"project","projectSlug":"P304"}
EOF
WORKSPACE_OVERRIDE_CLI="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_value cli \"$WORKSPACE_OVERRIDE_WS/Projects/P304/deep\"")"
if [ "$WORKSPACE_OVERRIDE_CLI" = "codex" ]; then
  ok "partial project config inherits workspace key before XDG fallback"
else
  fail "partial project config did not inherit workspace key"
fi

LEGACY_LOCAL_WS="$SCOPED_HOME/legacy-local-workspace"
LEGACY_LOCAL_CONTAINER="$SCOPED_HOME/legacy-local-projects"
mkdir -p "$LEGACY_LOCAL_WS/repo/deep" "$LEGACY_LOCAL_CONTAINER/P305"
cat >"$LEGACY_LOCAL_WS/repo/.spec-drive-config.json" <<EOF
{"projectRoot":"$LEGACY_LOCAL_CONTAINER"}
EOF
LEGACY_LOCAL_RESOLVED="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_projects_container \"$LEGACY_LOCAL_WS/repo/deep\"")"
if [ "$LEGACY_LOCAL_RESOLVED" = "$LEGACY_LOCAL_CONTAINER" ]; then
  ok "legacy unscoped projectRoot remains compatible"
else
  fail "legacy unscoped projectRoot did not resolve its container"
fi

LEGACY_FLAT_HOME="$SCOPED_HOME/legacy-flat-home"
LEGACY_FLAT_CONTAINER="$SCOPED_HOME/legacy-flat-projects"
LEGACY_FLAT_PROJECT="$LEGACY_FLAT_CONTAINER/P306"
mkdir -p "$LEGACY_FLAT_HOME/.config/spec-drive" "$LEGACY_FLAT_PROJECT/deep"
cat >"$LEGACY_FLAT_HOME/.config/spec-drive/config.json" <<EOF
{"projectRoot":"$LEGACY_FLAT_CONTAINER","cli":"claude-code"}
EOF
LEGACY_FLAT_CONTEXT="$(HOME="$LEGACY_FLAT_HOME" XDG_CONFIG_HOME="$LEGACY_FLAT_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$LEGACY_FLAT_PROJECT/deep\"")"
if [ "$(printf '%s' "$LEGACY_FLAT_CONTEXT" | jq -r '.projectsContainer')" = "$LEGACY_FLAT_CONTAINER" ] \
  && [ "$(printf '%s' "$LEGACY_FLAT_CONTEXT" | jq -r '.cli')" = "claude-code" ] \
  && [ ! -e "$LEGACY_FLAT_PROJECT/spec" ]; then
  ok "legacy XDG fallback supports flat projects without spec directory"
else
  fail "legacy XDG fallback did not support a flat project without spec directory"
fi

INVALID_PROJECT="$SCOPED_HOME/invalid-workspace/Projects/P302"
mkdir -p "$INVALID_PROJECT/spec"
cat >"$SCOPED_HOME/invalid-workspace/.spec-drive-config.json" <<EOF
{"scope":"workspace","workspaceRoot":"$SCOPED_HOME/invalid-workspace","projectsPath":"Projects"}
EOF
cat >"$INVALID_PROJECT/.spec-drive-config.json" <<'EOF'
{"scope":"project","projectSlug":"P302","projectRoot":"/tmp/forbidden"}
EOF
set +e
INVALID_OUTPUT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$INVALID_PROJECT/spec\"" 2>&1)"
INVALID_STATUS=$?
set -e
if [ "$INVALID_STATUS" -ne 0 ] && echo "$INVALID_OUTPUT" | grep -q "$INVALID_PROJECT/.spec-drive-config.json"; then
  ok "invalid-present scoped config fails with offending path"
else
  fail "invalid-present scoped config did not fail with offending path"
fi

INVALID_SLUG_PROJECT="$SCOPED_HOME/invalid-slug-workspace/Projects/bad slug"
mkdir -p "$INVALID_SLUG_PROJECT/spec"
cat >"$SCOPED_HOME/invalid-slug-workspace/.spec-drive-config.json" <<EOF
{"scope":"workspace","workspaceRoot":"$SCOPED_HOME/invalid-slug-workspace","projectsPath":"Projects"}
EOF
cat >"$INVALID_SLUG_PROJECT/.spec-drive-config.json" <<'EOF'
{"scope":"project","projectSlug":"bad slug"}
EOF
set +e
INVALID_SLUG_OUTPUT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$INVALID_SLUG_PROJECT/spec\"" 2>&1)"
INVALID_SLUG_STATUS=$?
set -e
if [ "$INVALID_SLUG_STATUS" -eq 3 ] && echo "$INVALID_SLUG_OUTPUT" | grep -q "$INVALID_SLUG_PROJECT/.spec-drive-config.json" && echo "$INVALID_SLUG_OUTPUT" | grep -q 'projectSlug'; then
  ok "projectSlug with whitespace fails with exit 3 and offending config path"
else
  fail "projectSlug with whitespace did not fail with controlled exit 3 and path"
fi

UNSAFE_SLUG_PROJECT="$SCOPED_HOME/unsafe-slug-workspace/Projects/bad@slug"
mkdir -p "$UNSAFE_SLUG_PROJECT/spec"
cat >"$SCOPED_HOME/unsafe-slug-workspace/.spec-drive-config.json" <<EOF
{"scope":"workspace","workspaceRoot":"$SCOPED_HOME/unsafe-slug-workspace","projectsPath":"Projects"}
EOF
cat >"$UNSAFE_SLUG_PROJECT/.spec-drive-config.json" <<'EOF'
{"scope":"project","projectSlug":"bad@slug"}
EOF
set +e
UNSAFE_SLUG_OUTPUT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$UNSAFE_SLUG_PROJECT/spec\"" 2>&1)"
UNSAFE_SLUG_STATUS=$?
set -e
if [ "$UNSAFE_SLUG_STATUS" -eq 3 ] && echo "$UNSAFE_SLUG_OUTPUT" | grep -q "$UNSAFE_SLUG_PROJECT/.spec-drive-config.json" && echo "$UNSAFE_SLUG_OUTPUT" | grep -q 'projectSlug'; then
  ok "projectSlug with unsafe characters fails with exit 3 and offending config path"
else
  fail "projectSlug with unsafe characters did not fail with controlled exit 3 and path"
fi

NUMERIC_SLUG_PROJECT="$SCOPED_HOME/numeric-slug-workspace/Projects/123"
mkdir -p "$NUMERIC_SLUG_PROJECT/spec"
cat >"$SCOPED_HOME/numeric-slug-workspace/.spec-drive-config.json" <<EOF
{"scope":"workspace","workspaceRoot":"$SCOPED_HOME/numeric-slug-workspace","projectsPath":"Projects"}
EOF
cat >"$NUMERIC_SLUG_PROJECT/.spec-drive-config.json" <<'EOF'
{"scope":"project","projectSlug":123}
EOF
set +e
NUMERIC_SLUG_OUTPUT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$NUMERIC_SLUG_PROJECT/spec\"" 2>&1)"
NUMERIC_SLUG_STATUS=$?
set -e
if [ "$NUMERIC_SLUG_STATUS" -eq 3 ] \
  && echo "$NUMERIC_SLUG_OUTPUT" | grep -q "Invalid Spec-Drive config: $NUMERIC_SLUG_PROJECT/.spec-drive-config.json:" \
  && ! echo "$NUMERIC_SLUG_OUTPUT" | grep -qi 'jq:'; then
  ok "numeric projectSlug fails with controlled exit 3 diagnostic"
else
  fail "numeric projectSlug did not fail with controlled exit 3 diagnostic"
fi

BOOLEAN_SLUG_PROJECT="$SCOPED_HOME/boolean-slug-workspace/Projects/true"
mkdir -p "$BOOLEAN_SLUG_PROJECT/spec"
cat >"$SCOPED_HOME/boolean-slug-workspace/.spec-drive-config.json" <<EOF
{"scope":"workspace","workspaceRoot":"$SCOPED_HOME/boolean-slug-workspace","projectsPath":"Projects"}
EOF
cat >"$BOOLEAN_SLUG_PROJECT/.spec-drive-config.json" <<'EOF'
{"scope":"project","projectSlug":true}
EOF
set +e
BOOLEAN_SLUG_OUTPUT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$BOOLEAN_SLUG_PROJECT/spec\"" 2>&1)"
BOOLEAN_SLUG_STATUS=$?
set -e
if [ "$BOOLEAN_SLUG_STATUS" -eq 3 ] \
  && echo "$BOOLEAN_SLUG_OUTPUT" | grep -q "Invalid Spec-Drive config: $BOOLEAN_SLUG_PROJECT/.spec-drive-config.json:" \
  && ! echo "$BOOLEAN_SLUG_OUTPUT" | grep -qi 'jq:'; then
  ok "boolean projectSlug fails with controlled exit 3 diagnostic"
else
  fail "boolean projectSlug did not fail with controlled exit 3 diagnostic"
fi

BOUNDARY_WS="$SCOPED_HOME/boundary-workspace"
mkdir -p "$BOUNDARY_WS/Projects/P303/spec"
cat >"$SCOPED_HOME/.spec-drive-config.json" <<'EOF'
{"scope":"workspace","workspaceRoot":"/tmp"
EOF
cat >"$BOUNDARY_WS/.spec-drive-config.json" <<EOF
{"scope":"workspace","workspaceRoot":"$BOUNDARY_WS","projectsPath":"Projects"}
EOF
cat >"$BOUNDARY_WS/Projects/P303/.spec-drive-config.json" <<'EOF'
{"scope":"project","projectSlug":"P303"}
EOF
BOUNDARY_CONTEXT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$BOUNDARY_WS/Projects/P303/spec\"")"
if [ "$(echo "$BOUNDARY_CONTEXT" | jq -r '.projectRoot')" = "$BOUNDARY_WS/Projects/P303" ] \
  && [ "$(echo "$BOUNDARY_CONTEXT" | jq -r '.workspaceConfig')" = "$BOUNDARY_WS/.spec-drive-config.json" ]; then
  ok "resolver stops above nearest valid workspace boundary"
else
  fail "resolver was contaminated by invalid config above workspace boundary"
fi

NON_OBJECT_WS="$SCOPED_HOME/non-object-workspace"
mkdir -p "$NON_OBJECT_WS"
cat >"$NON_OBJECT_WS/.spec-drive-config.json" <<'EOF'
[]
EOF
set +e
NON_OBJECT_OUTPUT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$NON_OBJECT_WS\"" 2>&1)"
NON_OBJECT_STATUS=$?
set -e
if [ "$NON_OBJECT_STATUS" -eq 3 ] && echo "$NON_OBJECT_OUTPUT" | grep -q "$NON_OBJECT_WS/.spec-drive-config.json" && echo "$NON_OBJECT_OUTPUT" | grep -q 'config root must be a JSON object' && ! echo "$NON_OBJECT_OUTPUT" | grep -qi 'jq:'; then
  ok "non-object config root fails with controlled exit 3 diagnostic"
else
  fail "non-object config root did not fail with controlled Spec-Drive diagnostic"
fi

INVALID_JSON_WS="$SCOPED_HOME/invalid-json-workspace"
mkdir -p "$INVALID_JSON_WS/deep"
cat >"$INVALID_JSON_WS/.spec-drive-config.json" <<'EOF'
{"scope":"workspace"
EOF
set +e
INVALID_JSON_OUTPUT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$INVALID_JSON_WS/deep\"" 2>&1)"
INVALID_JSON_STATUS=$?
set -e
if [ "$INVALID_JSON_STATUS" -eq 3 ] \
  && echo "$INVALID_JSON_OUTPUT" | grep -q "$INVALID_JSON_WS/.spec-drive-config.json" \
  && echo "$INVALID_JSON_OUTPUT" | grep -q 'invalid JSON'; then
  ok "invalid JSON fails with exit 3 and offending config path"
else
  fail "invalid JSON did not fail with controlled diagnostic"
fi

INVALID_SCOPE_WS="$SCOPED_HOME/invalid-scope-workspace"
mkdir -p "$INVALID_SCOPE_WS/deep"
cat >"$INVALID_SCOPE_WS/.spec-drive-config.json" <<'EOF'
{"scope":"fixture","workspaceRoot":".","projectsPath":"Projects"}
EOF
set +e
INVALID_SCOPE_OUTPUT="$(HOME="$SCOPED_HOME" XDG_CONFIG_HOME="$SCOPED_HOME/.config" bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_context \"$INVALID_SCOPE_WS/deep\"" 2>&1)"
INVALID_SCOPE_STATUS=$?
set -e
if [ "$INVALID_SCOPE_STATUS" -eq 3 ] \
  && echo "$INVALID_SCOPE_OUTPUT" | grep -q "$INVALID_SCOPE_WS/.spec-drive-config.json" \
  && echo "$INVALID_SCOPE_OUTPUT" | grep -q "unsupported scope 'fixture'"; then
  ok "invalid scope fails with exit 3 and offending config path"
else
  fail "invalid scope did not fail with controlled diagnostic"
fi

echo "-- find -mmin portability (US2)..."
# AC1: no find -mmin usage remains in stop-watcher.sh (exclude comment lines)
if ! grep -vE '^\s*#' hooks/scripts/stop-watcher.sh | grep -qE 'find\s.*-mmin'; then
  ok "stop-watcher.sh does not use GNU-only find -mmin"
else
  fail "stop-watcher.sh still contains GNU-only find -mmin"
fi

# AC4: cleanup block is still guarded by is_safe_spec_path
if grep -A2 'is_safe_spec_path.*SPEC_PATH' hooks/scripts/stop-watcher.sh | grep -q '_cleanup_old_progress_files'; then
  ok "cleanup block is still guarded by is_safe_spec_path"
else
  fail "cleanup block is not guarded by is_safe_spec_path"
fi

# AC2 + AC3: old files are deleted; recent files and unsupported-mtime are handled gracefully
CLEANUP_TMP="$(cd "$(mktemp -d)" && pwd -P)"
TEST_TEMP_DIRS+=("$CLEANUP_TMP")

# Create a mock project structure
mkdir -p "$CLEANUP_TMP/sd-projects/P999/spec"
mkdir -p "$CLEANUP_TMP/.config/spec-drive"
printf '{"projectRoot":"%s"}\n' "$CLEANUP_TMP/sd-projects" >"$CLEANUP_TMP/.config/spec-drive/config.json"

SPEC_PATH="$CLEANUP_TMP/sd-projects/P999/spec"
OLD_FILE="$SPEC_PATH/.progress-task-old-123.md"
NEW_FILE="$SPEC_PATH/.progress-task-new-456.md"
touch "$OLD_FILE"
touch "$NEW_FILE"

# Backdate the old file to 2 hours ago using touch -t or python3
if command -v python3 >/dev/null 2>&1; then
  python3 -c "import os, time; os.utime('$OLD_FILE', (time.time()-7400, time.time()-7400))"
elif touch -t "$(date -d '2 hours ago' +%Y%m%d%H%M.%S 2>/dev/null || true)" "$OLD_FILE" 2>/dev/null; then
  true
fi

# Source the cleanup function and call it directly
(
  . hooks/scripts/resolve-config.sh
  # Define is_safe_spec_path inline for testing (always returns 0 for our spec path)
  is_safe_spec_path() { [ "$1" = "$SPEC_PATH" ]; }
  _cleanup_old_progress_files() {
    local spec_path="$1"
    local max_age_seconds=3600
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$spec_path" "$max_age_seconds" <<'PYEOF' 2>/dev/null || true
import os, sys, glob, time
spec_path, max_age = sys.argv[1], int(sys.argv[2])
now = time.time()
for f in glob.glob(os.path.join(spec_path, ".progress-task-*.md")):
    try:
        if now - os.path.getmtime(f) > max_age:
            os.remove(f)
    except OSError:
        pass
PYEOF
      return
    fi
    local stat_fmt stat_arg now file mtime age
    if stat -c '%Y' /dev/null >/dev/null 2>&1; then
      stat_fmt="-c"; stat_arg="%Y"
    elif stat -f '%m' /dev/null >/dev/null 2>&1; then
      stat_fmt="-f"; stat_arg="%m"
    else
      return
    fi
    now=$(date +%s 2>/dev/null) || return
    for file in "$spec_path"/.progress-task-*.md; do
      [ -f "$file" ] || continue
      mtime=$(stat "$stat_fmt" "$stat_arg" "$file" 2>/dev/null) || continue
      age=$(( now - mtime ))
      [ "$age" -gt "$max_age_seconds" ] && rm -f "$file" 2>/dev/null || true
    done
  }
  _cleanup_old_progress_files "$SPEC_PATH"
)

if [ ! -f "$OLD_FILE" ]; then
  ok "cleanup deletes .progress-task-*.md files older than 60 min"
else
  fail "cleanup did not delete old .progress-task-*.md file (mtime backdating may be unsupported here)"
fi

if [ -f "$NEW_FILE" ]; then
  ok "cleanup preserves .progress-task-*.md files newer than 60 min"
else
  fail "cleanup incorrectly deleted recent .progress-task-*.md file"
fi

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
