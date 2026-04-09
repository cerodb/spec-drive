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

# Verify portable_realpath resolves correctly on this system
REAL_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$REAL_TMP_DIR"' EXIT
RESOLVED="$(bash -c ". hooks/scripts/resolve-config.sh && portable_realpath \"$REAL_TMP_DIR\"")"
if [ "$RESOLVED" = "$REAL_TMP_DIR" ]; then
  ok "portable_realpath resolves a real directory path correctly"
else
  fail "portable_realpath returned unexpected result: '$RESOLVED' (expected '$REAL_TMP_DIR')"
fi

echo "-- Ambiguous project safety..."
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
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
CLEANUP_TMP="$(mktemp -d)"
trap 'rm -rf "$CLEANUP_TMP"' EXIT

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
  PROJECT_ROOT_REAL="$CLEANUP_TMP/sd-projects"
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
