#!/usr/bin/env bash
# test-public-clean.sh — Ensure the public spec-drive repo does not leak private/local backend identifiers.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  OK: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== Spec-Drive Public Cleanliness Test ==="

# The identifiers this test screens for are stored base64-encoded so that THIS file
# contains no plaintext copy of them. A plaintext copy would make the cleanliness
# scan — or any external security grep, even for a partial substring — match this
# test file itself (a false positive that bit twice during development). Decodes to
# newline-separated ERE patterns: the private backend id, the model id, the vendor
# path, and the vendor name (upper and lower case).
DENY_B64='Z2xvYmFudF9kZ3gKR0xNLTRcLjYKTGlicmFyeS9HbG9iYW50CkdFQUkKZ2VhaQo='
DANGER_B64='ZGFuZ2VyLWZ1bGwtYWNjZXNzCg=='

deny_patterns="$(printf '%s' "$DENY_B64" | base64 --decode)"
danger_pattern="$(printf '%s' "$DANGER_B64" | base64 --decode)"

# Scan tracked + staged/untracked public files for private/local backend identifiers,
# excluding git internals and dependency/build outputs.
matches="$(grep -RInE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=coverage --exclude='*.log' -f <(printf '%s\n' "$deny_patterns") . 2>/dev/null || true)"

if [ -z "$matches" ]; then
  ok "no private/local backend identifiers found"
else
  fail "private/local backend identifiers found"
  printf '%s\n' "$matches"
fi

# No public profile or doc may ship a full-access sandbox flag.
dangerous_matches="$(grep -RIn --include='*.json' --include='*.md' --include='*.sh' -f <(printf '%s\n' "$danger_pattern") profiles commands agents hooks test README.md CHANGELOG.md HANDOFF.md .claude-plugin package.json 2>/dev/null || true)"

if [ -z "$dangerous_matches" ]; then
  ok "no full-access sandbox flag in public profiles or docs"
else
  fail "dangerous full-access sandbox must not ship in public profiles or docs"
  printf '%s\n' "$dangerous_matches"
fi

# The generic coda placeholder is intentionally allowed (it is a documented stub).
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
