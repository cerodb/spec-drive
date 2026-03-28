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

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
