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

assert_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Eq "$pattern" "$file"; then
    ok "$label"
  else
    fail "$label"
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Eq "$pattern" "$file"; then
    fail "$label"
  else
    ok "$label"
  fi
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

echo "-- Checking new command scaffold delegation..."
NEW_FILE="commands/new.md"
if [ -f "$NEW_FILE" ]; then
  if grep -q 'spec_drive_resolve_projects_container' "$NEW_FILE"; then
    ok "new command resolves the shared projects container"
  else
    fail "new command missing shared projects container resolver"
  fi

  if grep -q 'hooks/scripts/create-project.sh' "$NEW_FILE"; then
    ok "new command delegates project creation to create-project.sh"
  else
    fail "new command missing create-project.sh delegation"
  fi

  if grep -q 'Delegate to the researcher agent only after the scaffold exits `0`' "$NEW_FILE"; then
    ok "new command documents researcher delegation only after scaffold success"
  else
    fail "new command missing scaffold-before-research contract"
  fi

  if grep -q 'Recovery: open the created project and run /spec-drive:research' "$NEW_FILE"; then
    ok "new command documents recovery after post-scaffold research failure"
  else
    fail "new command missing post-scaffold research recovery guidance"
  fi

  if grep -q 'mkdir -p "\$PROJECT_ROOT/<name>/spec"' "$NEW_FILE"; then
    fail "new command still contains legacy inline mkdir scaffold prose"
  else
    ok "new command no longer contains legacy inline mkdir scaffold prose"
  fi

  GOAL_PROMPT_LINE="$(grep -n 'No goal text provided\. What is the vision for this project\?' "$NEW_FILE" | head -n1 | cut -d: -f1)"
  RESOLVER_LINE="$(grep -n 'spec_drive_resolve_projects_container' "$NEW_FILE" | head -n1 | cut -d: -f1)"
  SCAFFOLD_LINE="$(grep -n 'hooks/scripts/create-project\.sh' "$NEW_FILE" | head -n1 | cut -d: -f1)"
  RESEARCH_LINE="$(grep -n 'subagent_type: spec-drive:researcher' "$NEW_FILE" | head -n1 | cut -d: -f1)"

  if [ -n "$GOAL_PROMPT_LINE" ] && [ -n "$RESOLVER_LINE" ] && [ "$GOAL_PROMPT_LINE" -lt "$RESOLVER_LINE" ]; then
    ok "new command completes goal prompting before resolver execution"
  else
    fail "new command should prompt for missing goal before resolver execution"
  fi

  if [ -n "$RESOLVER_LINE" ] && [ -n "$SCAFFOLD_LINE" ] && [ "$RESOLVER_LINE" -lt "$SCAFFOLD_LINE" ]; then
    ok "new command resolves container before invoking scaffold"
  else
    fail "new command should resolve container before invoking scaffold"
  fi

  if [ -n "$SCAFFOLD_LINE" ] && [ -n "$RESEARCH_LINE" ] && [ "$SCAFFOLD_LINE" -lt "$RESEARCH_LINE" ]; then
    ok "new command delegates research after scaffold invocation"
  else
    fail "new command should delegate research after scaffold invocation"
  fi

  STATUS_LINE="$(grep -n 'CREATE_PROJECT_STATUS=\$?' "$NEW_FILE" | head -n1 | cut -d: -f1)"
  SET_PLUS_E_LINE="$(grep -n 'set +e' "$NEW_FILE" | head -n1 | cut -d: -f1)"
  SET_MINUS_E_LINE="$(grep -n 'set -e' "$NEW_FILE" | head -n1 | cut -d: -f1)"
  EXIT2_LINE="$(grep -n '\[ "\$CREATE_PROJECT_STATUS" -eq 2 \]' "$NEW_FILE" | head -n1 | cut -d: -f1)"
  NONZERO_LINE="$(grep -n '\[ "\$CREATE_PROJECT_STATUS" -ne 0 \]' "$NEW_FILE" | head -n1 | cut -d: -f1)"
  SPEC_PATH_LINE="$(grep -n 'SPEC_PATH="\$PROJECT_PATH/spec"' "$NEW_FILE" | head -n1 | cut -d: -f1)"

  if [ -n "$SET_PLUS_E_LINE" ] && [ -n "$STATUS_LINE" ] && [ -n "$SET_MINUS_E_LINE" ] && [ -n "$EXIT2_LINE" ] && [ -n "$NONZERO_LINE" ] && [ -n "$SPEC_PATH_LINE" ] \
    && [ "$SET_PLUS_E_LINE" -lt "$SCAFFOLD_LINE" ] \
    && [ "$SCAFFOLD_LINE" -lt "$STATUS_LINE" ] \
    && [ "$STATUS_LINE" -lt "$SET_MINUS_E_LINE" ] \
    && [ "$SET_MINUS_E_LINE" -lt "$EXIT2_LINE" ] \
    && [ "$STATUS_LINE" -lt "$EXIT2_LINE" ] \
    && [ "$EXIT2_LINE" -lt "$NONZERO_LINE" ] \
    && [ "$NONZERO_LINE" -lt "$SPEC_PATH_LINE" ]; then
    ok "new command captures scaffold status and branches before deriving SPEC_PATH"
  else
    fail "new command must capture scaffold status, distinguish exit 2, and branch before SPEC_PATH"
  fi
else
  fail "commands/new.md does not exist"
fi

echo "-- Checking local artifact-topology guidance..."
for DOC in skills/spec-workflow/SKILL.md README.md INSTALL.md; do
  assert_contains "$DOC" '`spec/`.*canonical Spec-Drive lifecycle artifacts and workflow state' "$DOC defines spec/ as canonical lifecycle/workflow state"
  assert_contains "$DOC" '`audit/`.*audits, evidence, diagnostics, investigations, and hygiene records' "$DOC defines audit/ scope"
  assert_contains "$DOC" '`input/`.*(received or collected source material|source material received or collected|received.*source material|collected.*source material)' "$DOC defines input/ scope"
  assert_contains "$DOC" '`output/`.*(non-spec deliverables|deliverables that are not canonical Spec-Drive lifecycle artifacts)' "$DOC defines output/ scope"
  assert_contains "$DOC" 'must use these names instead of' "$DOC requires canonical directory names over ad hoc alternatives"
  assert_contains "$DOC" 'optional' "$DOC marks audit/input/output as optional"
  assert_contains "$DOC" '([Cc]reated|[Cc]reate).*only immediately before.*first content' "$DOC requires lazy optional directory creation"
done

echo "-- Checking topology and precedence guidance..."
for DOC in skills/spec-workflow/SKILL.md README.md INSTALL.md; do
  assert_contains "$DOC" 'heterogeneous' "$DOC mentions heterogeneous workspace topology"
  assert_contains "$DOC" 'project scope' "$DOC mentions project scope"
  assert_contains "$DOC" 'workspace scope' "$DOC mentions workspace scope"
  assert_contains "$DOC" 'legacy XDG' "$DOC mentions legacy XDG scope"
  assert_contains "$DOC" 'present but invalid|invalid.*fail' "$DOC states invalid-present failure"
  assert_contains "$DOC" 'absent.*falls? through|falls? through to the next|falls? back to the next' "$DOC states absent-scope fallback"
  assert_contains "$DOC" '(portable project identity|[Pp]roject identity stays portable)' "$DOC states portable project identity"
done

echo "-- Checking owner-approval publication gate..."
for DOC in skills/spec-workflow/SKILL.md README.md INSTALL.md; do
  assert_contains "$DOC" 'local source repositor(y|ies).*separate from.*distribution|separate from any distribution or marketplace sync|separate from marketplace/distribution sync' "$DOC separates local source from distribution sync"
  assert_contains "$DOC" 'issue, push, pull request, release, publication' "$DOC enumerates public actions behind owner approval"
  assert_contains "$DOC" 'separate explicit owner approval' "$DOC requires separate explicit owner approval"
  assert_not_contains "$DOC" 'SharedMemory' "$DOC does not mention SharedMemory"
  assert_not_contains "$DOC" 'P354c' "$DOC does not mention P354c"
  assert_not_contains "$DOC" '/home/' "$DOC does not leak private local absolute paths"
done

echo ""
echo "Commands checked: ${#COMMANDS[@]}"
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
