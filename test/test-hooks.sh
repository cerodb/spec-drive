#!/usr/bin/env bash
# test-hooks.sh — Validate hooks configuration and scripts
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

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

echo "-- Ambiguous project safety..."
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/spec-drive-projects/P100/spec" "$TMP_HOME/spec-drive-projects/P101/spec"
cat >"$TMP_HOME/.spec-drive-config.json" <<EOF
{"projectRoot":"$TMP_HOME/spec-drive-projects"}
EOF
cat >"$TMP_HOME/spec-drive-projects/P100/spec/.spec-drive-state.json" <<'EOF'
{"phase":"execution","awaitingApproval":false,"mode":"normal","taskIndex":0,"totalTasks":1}
EOF
cat >"$TMP_HOME/spec-drive-projects/P101/spec/.spec-drive-state.json" <<'EOF'
{"phase":"execution","awaitingApproval":false,"mode":"normal","taskIndex":0,"totalTasks":1}
EOF
AMBIGUOUS_OUTPUT="$(HOME="$TMP_HOME" bash hooks/scripts/stop-watcher.sh <<'EOF'
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
NUMERIC_OUTPUT="$(HOME="$TMP_HOME" bash hooks/scripts/stop-watcher.sh <<'EOF'
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
WORKSPACE_OUTPUT="$(HOME="$TMP_HOME" bash hooks/scripts/stop-watcher.sh <<EOF
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
XDG_OUTPUT="$(HOME="$TMP_HOME" bash hooks/scripts/stop-watcher.sh <<EOF
{"cwd":"$WORKSPACE/repo"}
EOF
)"
if echo "$XDG_OUTPUT" | grep -q "Continue spec: P201"; then
  ok "xdg config is used when workspace config is absent"
else
  fail "xdg config was not used when workspace config is absent"
fi

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
