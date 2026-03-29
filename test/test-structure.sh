#!/usr/bin/env bash
# test-structure.sh — Validate spec-drive plugin directory structure
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

PASS=0
FAIL=0
MISSING=()

check_exists() {
  local path="$1"
  if [ -e "$path" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    MISSING+=("$path")
  fi
}

echo "=== Spec-Drive Structure Test ==="

# Required directories
echo "-- Checking directories..."
for dir in agents commands hooks/scripts skills/spec-workflow skills/spec-workflow/references skills/delegation-principle skills/communication-style templates schemas .claude-plugin; do
  check_exists "$dir"
done

# 6 agent files
echo "-- Checking agents (6)..."
for agent in researcher product-manager architect task-planner executor qa-engineer; do
  check_exists "agents/$agent.md"
done

# 9 command files
echo "-- Checking commands (9)..."
for cmd in new research requirements design tasks-cmd implement status cancel help; do
  check_exists "commands/$cmd.md"
done

# 5 skill files
echo "-- Checking skills (5)..."
check_exists "skills/spec-workflow/SKILL.md"
check_exists "skills/spec-workflow/references/phase-checklists.md"
check_exists "skills/spec-workflow/references/phase-transitions.md"
check_exists "skills/delegation-principle/SKILL.md"
check_exists "skills/communication-style/SKILL.md"

# Core files
echo "-- Checking core files..."
check_exists ".claude-plugin/plugin.json"
check_exists "package.json"
check_exists "hooks/hooks.json"
check_exists "hooks/scripts/stop-watcher.sh"
check_exists "hooks/scripts/context-loader.sh"

# Templates
echo "-- Checking templates (6)..."
for tpl in idea research requirements design tasks progress; do
  check_exists "templates/$tpl.md"
done

# Schema
check_exists "schemas/spec-drive.schema.json"

echo "-- Checking state-update safety..."
if grep -q 'mktemp "\${state_file}\.XXXXXX"' agents/researcher.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: researcher agent missing same-directory temp file safety"
  FAIL=$((FAIL + 1))
fi

# Total file count (non-directory, non-.git)
TOTAL=$(find . -not -path './.git/*' -not -path './test/*' -not -path './node_modules/*' -type f | wc -l)
echo ""
echo "Total plugin files: $TOTAL"
if [ "$TOTAL" -lt 32 ]; then
  echo "FAIL: Expected >= 32 files, found $TOTAL"
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Missing:"
  for m in "${MISSING[@]}"; do
    echo "  - $m"
  done
  exit 1
fi

echo "PASS"
exit 0
