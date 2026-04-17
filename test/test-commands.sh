#!/usr/bin/env bash
# test-commands.sh — Validate command file frontmatter
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

COMMANDS=(new research requirements design tasks implement status cancel help list switch refactor)

echo "=== Spec-Drive Commands Test ==="

for cmd in "${COMMANDS[@]}"; do
  FILE="commands/$cmd.md"
  echo "-- Checking $FILE..."

  if [ ! -f "$FILE" ]; then
    fail "$FILE does not exist"
    continue
  fi

  # Check YAML frontmatter (starts with ---)
  FIRST_LINE=$(head -1 "$FILE")
  if [ "$FIRST_LINE" = "---" ]; then
    ok "$cmd has YAML frontmatter"
  else
    fail "$cmd missing YAML frontmatter (first line: $FIRST_LINE)"
    continue
  fi

  # Extract frontmatter (between first and second ---)
  FRONTMATTER=$(sed -n '2,/^---$/p' "$FILE" | sed '$d')

  # Check description field
  if echo "$FRONTMATTER" | grep -q '^description:'; then
    ok "$cmd has description field"
  else
    fail "$cmd missing description field"
  fi

  # Check argument-hint field
  if echo "$FRONTMATTER" | grep -q '^argument-hint:'; then
    ok "$cmd has argument-hint field"
  else
    fail "$cmd missing argument-hint field"
  fi

  # Check allowed-tools field
  if echo "$FRONTMATTER" | grep -q '^allowed-tools:'; then
    ok "$cmd has allowed-tools field"
  else
    fail "$cmd missing allowed-tools field"
  fi
done

echo "-- Checking list command completeness..."
LIST_FILE="commands/list.md"
if [ -f "$LIST_FILE" ]; then
  LIST_FM=$(sed -n '2,/^---$/p' "$LIST_FILE" | sed '$d')

  if echo "$LIST_FM" | grep -q '^description:'; then
    ok "list.md has description frontmatter key"
  else
    fail "list.md missing description frontmatter key"
  fi

  if echo "$LIST_FM" | grep -q '^argument-hint:'; then
    ok "list.md has argument-hint frontmatter key"
  else
    fail "list.md missing argument-hint frontmatter key"
  fi

  if echo "$LIST_FM" | grep -q '^allowed-tools:'; then
    ok "list.md has allowed-tools frontmatter key"
  else
    fail "list.md missing allowed-tools frontmatter key"
  fi

  if grep -q 'PROJECT_ROOT' "$LIST_FILE"; then
    ok "list.md body references PROJECT_ROOT"
  else
    fail "list.md body does not reference PROJECT_ROOT"
  fi

  if grep -q 'phase' "$LIST_FILE"; then
    ok "list.md body references phase output"
  else
    fail "list.md body does not reference phase output"
  fi
else
  fail "commands/list.md does not exist"
fi

echo "-- Checking switch command completeness..."
SWITCH_FILE="commands/switch.md"
if [ -f "$SWITCH_FILE" ]; then
  SWITCH_FM=$(sed -n '2,/^---$/p' "$SWITCH_FILE" | sed '$d')

  if echo "$SWITCH_FM" | grep -q '^description:'; then
    ok "switch.md has description frontmatter key"
  else
    fail "switch.md missing description frontmatter key"
  fi

  if echo "$SWITCH_FM" | grep -q '^argument-hint:'; then
    ok "switch.md has argument-hint frontmatter key"
  else
    fail "switch.md missing argument-hint frontmatter key"
  fi

  if echo "$SWITCH_FM" | grep -q '^allowed-tools:'; then
    ok "switch.md has allowed-tools frontmatter key"
  else
    fail "switch.md missing allowed-tools frontmatter key"
  fi

  if grep -q '~/.spec-drive-active.json' "$SWITCH_FILE"; then
    ok "switch.md references ~/.spec-drive-active.json"
  else
    fail "switch.md does not reference ~/.spec-drive-active.json"
  fi

  if grep -q 'activePath' "$SWITCH_FILE" && grep -q 'switchedAt' "$SWITCH_FILE"; then
    ok "switch.md documents registry format: activePath and switchedAt fields"
  else
    fail "switch.md missing registry format documentation (activePath/switchedAt)"
  fi

  if grep -q 'cwd' "$SWITCH_FILE"; then
    ok "switch.md documents cwd fallback"
  else
    fail "switch.md missing cwd fallback documentation"
  fi
else
  fail "commands/switch.md does not exist"
fi

echo "-- Checking refactor command completeness..."
REFACTOR_FILE="commands/refactor.md"
if [ -f "$REFACTOR_FILE" ]; then
  REFACTOR_FM=$(sed -n '2,/^---$/p' "$REFACTOR_FILE" | sed '$d')

  if echo "$REFACTOR_FM" | grep -q '^description:'; then
    ok "refactor.md has description frontmatter key"
  else
    fail "refactor.md missing description frontmatter key"
  fi

  if echo "$REFACTOR_FM" | grep -q '^argument-hint:'; then
    ok "refactor.md has argument-hint frontmatter key"
  else
    fail "refactor.md missing argument-hint frontmatter key"
  fi

  if echo "$REFACTOR_FM" | grep -q '^allowed-tools:'; then
    ok "refactor.md has allowed-tools frontmatter key"
  else
    fail "refactor.md missing allowed-tools frontmatter key"
  fi

  if grep -q '\.progress\.md' "$REFACTOR_FILE"; then
    ok "refactor.md references .progress.md as source for execution learnings"
  else
    fail "refactor.md does not reference .progress.md"
  fi

  if grep -q 'requirements.*design.*tasks' "$REFACTOR_FILE" || (grep -q 'requirements' "$REFACTOR_FILE" && grep -q 'design' "$REFACTOR_FILE" && grep -q 'tasks' "$REFACTOR_FILE"); then
    ok "refactor.md specifies update sequence: requirements, design, tasks"
  else
    fail "refactor.md missing sequential update order (requirements -> design -> tasks)"
  fi

  if grep -q 'requirementsSha' "$REFACTOR_FILE" && grep -q 'designSha' "$REFACTOR_FILE"; then
    ok "refactor.md references requirementsSha and designSha staleness detection"
  else
    fail "refactor.md missing requirementsSha/designSha staleness detection"
  fi

  if grep -q 'CHANGELOG' "$REFACTOR_FILE"; then
    ok "refactor.md instructs recording changes in .progress.md CHANGELOG section"
  else
    fail "refactor.md missing CHANGELOG section reference in .progress.md"
  fi

  if grep -q 'phase-transitions' "$REFACTOR_FILE"; then
    ok "refactor.md references phase-transitions.md for valid navigation"
  else
    fail "refactor.md does not reference phase-transitions.md"
  fi
else
  fail "commands/refactor.md does not exist"
fi

echo "-- Checking cancel safety guidance..."
if grep -q 'outside the approved Spec-Drive root' commands/cancel.md; then
  ok "cancel command guards deletion to approved project root"
else
  fail "cancel command missing approved-root deletion guard"
fi

if grep -q 'command -v trash' commands/cancel.md; then
  ok "cancel command prefers trash when available"
else
  fail "cancel command missing trash-first deletion guidance"
fi

if grep -q 'mktemp "\${state_file}\.XXXXXX"' commands/research.md; then
  ok "research command uses same-directory temp file for state updates"
else
  fail "research command missing same-directory temp file safety"
fi

echo "-- Checking coordinator agent..."
COORDINATOR_FILE="agents/coordinator.md"
if [ -f "$COORDINATOR_FILE" ]; then
  ok "coordinator agent file exists"

  FIRST_LINE=$(head -1 "$COORDINATOR_FILE")
  if [ "$FIRST_LINE" = "---" ]; then
    ok "coordinator agent has YAML frontmatter"
  else
    fail "coordinator agent missing YAML frontmatter"
  fi

  if grep -q '^name: coordinator' "$COORDINATOR_FILE"; then
    ok "coordinator agent has name: coordinator"
  else
    fail "coordinator agent missing name: coordinator"
  fi

  if grep -q '^description:' "$COORDINATOR_FILE"; then
    ok "coordinator agent has description field"
  else
    fail "coordinator agent missing description field"
  fi

  if grep -q 'continue_sequential' "$COORDINATOR_FILE" && \
     grep -q 'clarify_first' "$COORDINATOR_FILE" && \
     grep -q 'coordinate_research' "$COORDINATOR_FILE" && \
     grep -q 'block_and_escalate' "$COORDINATOR_FILE"; then
    ok "coordinator agent defines all four outcome names"
  else
    fail "coordinator agent missing one or more outcome names"
  fi

  if grep -q 'A1' "$COORDINATOR_FILE" && grep -q 'A5' "$COORDINATOR_FILE"; then
    ok "coordinator agent documents ambiguity signals A1-A5"
  else
    fail "coordinator agent missing ambiguity signals A1-A5"
  fi

  if grep -q 'F1' "$COORDINATOR_FILE" && grep -q 'F4' "$COORDINATOR_FILE"; then
    ok "coordinator agent documents fan-out signals F1-F4"
  else
    fail "coordinator agent missing fan-out signals F1-F4"
  fi

  if grep -q 'COORDINATOR_OUTCOME' "$COORDINATOR_FILE"; then
    ok "coordinator agent defines structured output contract"
  else
    fail "coordinator agent missing COORDINATOR_OUTCOME output contract"
  fi

  if grep -q '### Coordinator Clarification' "$COORDINATOR_FILE"; then
    ok "coordinator agent documents Coordinator Clarification block format"
  else
    fail "coordinator agent missing Coordinator Clarification block format"
  fi
else
  fail "coordinator agent file $COORDINATOR_FILE does not exist"
fi

echo "-- Checking coordinator-first requirements behavior..."
if grep -q 'spec-drive:coordinator' commands/requirements.md; then
  ok "requirements command delegates to spec-drive:coordinator agent"
else
  fail "requirements command missing spec-drive:coordinator delegation"
fi

if grep -q 'clarify_first' commands/requirements.md; then
  ok "requirements command handles clarify_first outcome"
else
  fail "requirements command missing clarify_first outcome handling"
fi

if grep -q 'block_and_escalate' commands/requirements.md; then
  ok "requirements command handles block_and_escalate outcome"
else
  fail "requirements command missing block_and_escalate outcome handling"
fi

if grep -q 'coordinator' commands/requirements.md; then
  ok "requirements command documents coordinator state handling"
else
  fail "requirements command missing coordinator state handling"
fi

echo "-- Checking coordinator-first research behavior..."
if grep -q 'spec-drive:coordinator' commands/research.md; then
  ok "research command delegates to spec-drive:coordinator agent"
else
  fail "research command missing spec-drive:coordinator delegation"
fi

if grep -q 'coordinate_research' commands/research.md; then
  ok "research command handles coordinate_research outcome"
else
  fail "research command missing coordinate_research outcome handling"
fi

if grep -q 'Post-Validate' commands/research.md; then
  ok "research command includes fan-out post-validation step"
else
  fail "research command missing fan-out post-validation step"
fi

echo ""
echo "Commands checked: ${#COMMANDS[@]}"
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
