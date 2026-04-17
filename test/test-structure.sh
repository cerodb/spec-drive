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

echo "-- Checking prompt safety guardrails..."
if grep -q 'Reject any path outside the project root derived from `basePath`' agents/researcher.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: researcher agent missing codebasePath sandbox guidance"
  FAIL=$((FAIL + 1))
fi

if grep -q 'Web research is the default when this runtime supports it' agents/researcher.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: researcher agent missing default web-research guidance"
  FAIL=$((FAIL + 1))
fi

if grep -q '^### Step 2: Related Specs / Prior Artifact Discovery' agents/researcher.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: researcher agent missing related-specs discovery step"
  FAIL=$((FAIL + 1))
fi

if grep -q 'local tool, skill, plugin, hook, command, or CLI integration' agents/researcher.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: researcher agent missing filesystem pre-flight guidance"
  FAIL=$((FAIL + 1))
fi

if grep -q 'Every material claim in `research.md` must be backed by at least one of:' agents/researcher.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: researcher agent missing evidence-discipline rule"
  FAIL=$((FAIL + 1))
fi

if grep -q 'security/privacy constraints are NOT optional: promote them into explicit NFRs' agents/product-manager.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: product-manager missing security/privacy NFR promotion rule"
  FAIL=$((FAIL + 1))
fi

if grep -q 'A compact `File Structure` table' agents/architect.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: architect missing file-structure guidance"
  FAIL=$((FAIL + 1))
fi

if grep -q '^### Step 7: Security Considerations' agents/architect.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: architect missing conditional security considerations step"
  FAIL=$((FAIL + 1))
fi

if grep -q 'Task size guidance:' agents/task-planner.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: task-planner missing task-size guidance"
  FAIL=$((FAIL + 1))
fi

if grep -q 'Prefer robust verification over brittle grep theater' agents/task-planner.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: task-planner missing robust verification guidance"
  FAIL=$((FAIL + 1))
fi

if grep -Fq '<name> [goal] [--auto] [--deep]' commands/new.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: new command missing --deep argument hint"
  FAIL=$((FAIL + 1))
fi

if grep -q '"researchDepth": "<deep|standard>"' commands/new.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: new command missing researchDepth state guidance"
  FAIL=$((FAIL + 1))
fi

if grep -q 'researchDepth: <deep|standard>' commands/new.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: new command missing researcher deep-pass propagation"
  FAIL=$((FAIL + 1))
fi

if grep -q 'Never emit a `Verify` command that is destructive' agents/task-planner.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: task-planner missing unsafe verify guidance"
  FAIL=$((FAIL + 1))
fi

if grep -q 'Before running it, inspect the command string for clearly unsafe patterns' agents/executor.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: executor missing unsafe verify preflight"
  FAIL=$((FAIL + 1))
fi

if grep -q 'Failure classification:' agents/executor.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: executor missing failure classification guidance"
  FAIL=$((FAIL + 1))
fi

if grep -q 'Retry memory:' agents/executor.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: executor missing retry-memory guidance"
  FAIL=$((FAIL + 1))
fi

if grep -q 'Progressive context escalation for retries:' agents/executor.md; then
  PASS=$((PASS + 1))
else
  echo "FAIL: executor missing progressive retry-context guidance"
  FAIL=$((FAIL + 1))
fi

echo "-- Checking phase-transitions.md Refactor section..."
PT_FILE="skills/spec-workflow/references/phase-transitions.md"
if grep -q '^## Refactor' "$PT_FILE"; then
  PASS=$((PASS + 1))
else
  echo "FAIL: phase-transitions.md missing Refactor section"
  FAIL=$((FAIL + 1))
fi

if grep -q 'completed' "$PT_FILE" && grep -q 'execution' "$PT_FILE"; then
  PASS=$((PASS + 1))
else
  echo "FAIL: phase-transitions.md Refactor section missing entry states (completed, execution)"
  FAIL=$((FAIL + 1))
fi

if grep -q 'requirements.md' "$PT_FILE" && grep -q 'design.md' "$PT_FILE" && grep -q 'tasks.md' "$PT_FILE"; then
  PASS=$((PASS + 1))
else
  echo "FAIL: phase-transitions.md Refactor section missing update loop (requirements -> design -> tasks)"
  FAIL=$((FAIL + 1))
fi

if grep -q 'requirementsSha' "$PT_FILE" && grep -q 'designSha' "$PT_FILE"; then
  PASS=$((PASS + 1))
else
  echo "FAIL: phase-transitions.md Refactor section missing requirementsSha/designSha staleness trigger"
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
