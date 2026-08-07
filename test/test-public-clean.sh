#!/usr/bin/env bash
# test-public-clean.sh — Ensure the public spec-drive repo does not leak private/local backend identifiers.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

PASS=0
FAIL=0
PUBLIC_CLEAN_TMP=""

ok() { PASS=$((PASS + 1)); echo "  OK: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

cleanup() {
  if [ -n "$PUBLIC_CLEAN_TMP" ] && [ -d "$PUBLIC_CLEAN_TMP" ]; then
    rm -rf "$PUBLIC_CLEAN_TMP"
  fi
}
trap cleanup EXIT

decode_base64() {
  if printf '%s' "$1" | base64 --decode 2>/dev/null; then
    return 0
  fi
  printf '%s' "$1" | base64 -D
}

# Scan every text file below a candidate public tree. The exclusions are limited
# to repository internals, fetched dependencies, and disposable build/coverage
# trees; fixture, generated, retained, and log files remain in scope.
scan_tree_ere() {
  local root="$1"
  local pattern_file="$2"
  grep -RIlE \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=dist \
    --exclude-dir=coverage \
    -f "$pattern_file" "$root" 2>/dev/null || true
}

scan_tree_fixed() {
  local root="$1"
  local pattern_file="$2"
  grep -RIlF \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=dist \
    --exclude-dir=coverage \
    -f "$pattern_file" "$root" 2>/dev/null || true
}

# The checkout scan follows Git's public-candidate surface: tracked files plus
# untracked, non-ignored files. This avoids treating explicitly local/ignored
# development transcripts as publishable while still catching a newly retained
# fixture or generated output before it is added.
scan_checkout_ere() {
  local pattern_file="$1"
  local candidate
  while IFS= read -r -d '' candidate; do
    if [ -f "$candidate" ] && grep -IqE -f "$pattern_file" "$candidate"; then
      printf '%s\n' "$candidate"
    fi
  done < <(git ls-files --cached --others --exclude-standard -z)
}

scan_checkout_fixed() {
  local pattern_file="$1"
  local candidate
  while IFS= read -r -d '' candidate; do
    if [ -f "$candidate" ] && grep -IqF -f "$pattern_file" "$candidate"; then
      printf '%s\n' "$candidate"
    fi
  done < <(git ls-files --cached --others --exclude-standard -z)
}

echo "=== Spec-Drive Public Cleanliness Test ==="

# The identifiers this test screens for are stored base64-encoded so that THIS file
# contains no plaintext copy of them. A plaintext copy would make the cleanliness
# scan — or any external security grep, even for a partial substring — match this
# test file itself (a false positive that bit twice during development). Decodes to
# newline-separated ERE patterns: the private backend id, the model id, the vendor
# path, and the vendor name (upper and lower case).
DENY_B64='Z2xvYmFudF9kZ3gKR0xNLTRcLjYKTGlicmFyeS9HbG9iYW50CkdFQUkKZ2VhaQo='
DANGER_B64='ZGFuZ2VyLWZ1bGwtYWNjZXNzCg=='

PUBLIC_CLEAN_TMP="$(mktemp -d)"
DENY_FILE="$PUBLIC_CLEAN_TMP/private-patterns.ere"
DANGER_FILE="$PUBLIC_CLEAN_TMP/danger-patterns.ere"
LOCAL_IDENTITY_FILE="$PUBLIC_CLEAN_TMP/local-identities.fixed"

decode_base64 "$DENY_B64" >"$DENY_FILE"
decode_base64 "$DANGER_B64" >"$DANGER_FILE"

# Runtime values catch accidental references to the machine executing the test
# without committing those values to the deny-list. Avoid overly generic root
# identities while still checking concrete home paths and non-trivial hosts.
: >"$LOCAL_IDENTITY_FILE"
if [ -n "${HOME:-}" ] && [ "${HOME:-}" != "/root" ]; then
  printf '%s\n' "$HOME" >>"$LOCAL_IDENTITY_FILE"
fi
CURRENT_HOST="$(hostname 2>/dev/null || true)"
if [ "${#CURRENT_HOST}" -ge 8 ]; then
  printf '%s\n' "$CURRENT_HOST" >>"$LOCAL_IDENTITY_FILE"
fi

# Scan code, fixtures, and any generated/retained output still present in the
# checkout. Only matching paths are reported so a failure does not echo a secret.
matches="$(scan_checkout_ere "$DENY_FILE")"
if [ -s "$LOCAL_IDENTITY_FILE" ]; then
  local_matches="$(scan_checkout_fixed "$LOCAL_IDENTITY_FILE")"
  if [ -n "$local_matches" ]; then
    matches="${matches}${matches:+$'\n'}${local_matches}"
  fi
fi

if [ -z "$matches" ]; then
  ok "code, fixtures, and retained/generated outputs contain no private/local identifiers"
else
  fail "private/local backend identifiers found"
  printf '%s\n' "$matches"
fi

# Public profiles keep the default sandbox; the unrestricted-sandbox flag is not shipped.
dangerous_matches="$(scan_checkout_ere "$DANGER_FILE")"

if [ -z "$dangerous_matches" ]; then
  ok "public profiles use the default sandbox"
else
  fail "the unrestricted-sandbox flag must not ship in public profiles"
  printf '%s\n' "$dangerous_matches"
fi

# The generic coda placeholder is intentionally allowed (it is a documented stub).
if grep -RIn 'coda-batch --model {MODEL}' . >/dev/null 2>&1; then
  ok "generic coda-batch placeholder is allowed"
else
  ok "no generic coda-batch placeholder present"
fi

echo "-- Self-testing public-clean coverage with synthetic identities..."
SELF_ROOT="$PUBLIC_CLEAN_TMP/public-tree"
SELF_PATTERNS="$PUBLIC_CLEAN_TMP/synthetic-identities.fixed"
mkdir -p \
  "$SELF_ROOT/src" \
  "$SELF_ROOT/test/fixtures" \
  "$SELF_ROOT/test/generated" \
  "$SELF_ROOT/test/retained"

printf '%s\n' \
  'synth-user-4821' \
  'host-4821.invalid' \
  '/srv/synthetic-private-4821' \
  'node-synth-4821' \
  'secret_synth_4821' \
  'private-id-synth-4821' >"$SELF_PATTERNS"

for clean_file in \
  "$SELF_ROOT/src/module.sh" \
  "$SELF_ROOT/test/fixtures/config.json" \
  "$SELF_ROOT/test/generated/result.txt" \
  "$SELF_ROOT/test/retained/report.log"; do
  printf '%s\n' 'portable-safe-value' >"$clean_file"
done

if [ -z "$(scan_tree_fixed "$SELF_ROOT" "$SELF_PATTERNS")" ]; then
  ok "clean synthetic code, fixtures, and retained/generated outputs are accepted"
else
  fail "clean synthetic public tree was rejected"
fi

PLANT_FILES=(
  "$SELF_ROOT/src/module.sh"
  "$SELF_ROOT/test/fixtures/config.json"
  "$SELF_ROOT/test/generated/result.txt"
  "$SELF_ROOT/test/retained/report.log"
  "$SELF_ROOT/test/fixtures/node.txt"
  "$SELF_ROOT/test/generated/id.txt"
)
PLANT_VALUES=(
  'synth-user-4821'
  'host-4821.invalid'
  '/srv/synthetic-private-4821'
  'node-synth-4821'
  'secret_synth_4821'
  'private-id-synth-4821'
)
PLANT_LABELS=(username hostname path node secret identifier)

i=0
while [ "$i" -lt "${#PLANT_FILES[@]}" ]; do
  printf '%s\n' "${PLANT_VALUES[$i]}" >"${PLANT_FILES[$i]}"
  if [ -n "$(scan_tree_fixed "$SELF_ROOT" "$SELF_PATTERNS")" ]; then
    ok "synthetic ${PLANT_LABELS[$i]} disclosure is rejected"
  else
    fail "synthetic ${PLANT_LABELS[$i]} disclosure was not detected"
  fi
  printf '%s\n' 'portable-safe-value' >"${PLANT_FILES[$i]}"
  i=$((i + 1))
done

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
