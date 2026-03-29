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

COMMANDS=(new research requirements design tasks-cmd implement status cancel help)

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
  FRONTMATTER=$(sed -n '2,/^---$/p' "$FILE" | head -n -1)

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
