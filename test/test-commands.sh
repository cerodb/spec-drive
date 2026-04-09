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

COMMANDS=(new research requirements design tasks-cmd implement status cancel help list)

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

echo ""
echo "Commands checked: ${#COMMANDS[@]}"
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
