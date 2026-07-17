#!/usr/bin/env bash
# test-public-clean.sh — Ensure public spec-drive repo does not leak private/local backend identifiers.
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

echo "=== Spec-Drive Public Cleanliness Test ==="

# Build private-token patterns in pieces so the cleanliness test does not match itself.
pat_backend="globant"'_dgx'
pat_model='GLM-''4\.6'
pat_path='Library/''Globant'
pat_vendor_upper='GE''AI'
pat_vendor_lower='ge''ai'

# Scan tracked + staged/untracked public files, excluding git internals and dependency/build outputs.
if matches="$(grep -RInE   --exclude-dir=.git   --exclude-dir=node_modules   --exclude-dir=dist   --exclude-dir=coverage   --exclude='*.log'   -e "$pat_backend"   -e "$pat_model"   -e "$pat_path"   -e "$pat_vendor_upper"   -e "$pat_vendor_lower"   . 2>/dev/null || true)"; then
  :
fi

if [ -z "$matches" ]; then
  ok "no private/local backend identifiers found"
else
  fail "private/local backend identifiers found"
  printf '%s\n' "$matches"
fi

pat_danger='danger-'"full-access"
if dangerous_matches="$(grep -RIn --include='*.json' --include='*.md' --include='*.sh' -e "$pat_danger" profiles commands agents hooks test README.md CHANGELOG.md HANDOFF.md .claude-plugin package.json 2>/dev/null || true)"; then
  :
fi

if [ -z "$dangerous_matches" ]; then
  ok "no full-access sandbox flag in public profiles or docs"
else
  fail "dangerous full-access sandbox must not ship in public profiles or docs"
  printf '%s
' "$dangerous_matches"
fi

if grep -RIn 'coda-batch --model {MODEL}' . >/dev/null 2>&1; then
  ok "generic coda-batch placeholder is allowed"
else
  ok "no generic coda-batch placeholder present"
fi

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
