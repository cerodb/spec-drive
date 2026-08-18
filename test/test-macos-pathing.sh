#!/usr/bin/env bash
# test-macos-pathing.sh — Guard the harness against logical/physical path drift.
#
# On macOS the temp root is reached through a symlink (/var -> /private/var), so a
# fixture path taken straight from `mktemp -d` is the *logical* path while the
# resolver reports the *physical* one. Fixtures that skip canonicalization compare
# the two and fail on macOS only.
#
# This suite reproduces that split with a plain symlink, so it runs identically on
# Linux and macOS, and then re-runs the fixture-allocating suites through it.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

PASS=0
FAIL=0
SYMLINK_ROOT=""

ok() {
  PASS=$((PASS + 1))
  echo "  OK: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

cleanup() {
  if [ -n "$SYMLINK_ROOT" ] && [ -d "$SYMLINK_ROOT" ]; then
    rm -rf "$SYMLINK_ROOT"
  fi
}
trap cleanup EXIT

echo "=== Spec-Drive Symlinked Temp Root Test ==="

# A nested run would re-enter the suites below forever.
if [ -n "${SPEC_DRIVE_SYMLINK_TMPDIR_RUN:-}" ]; then
  echo "  SKIP: nested invocation"
  echo ""
  echo "Passed: 0 | Failed: 0"
  echo "PASS"
  exit 0
fi

SYMLINK_ROOT="$(cd "$(mktemp -d)" && pwd -P)"
mkdir -p "$SYMLINK_ROOT/physical"
ln -s "$SYMLINK_ROOT/physical" "$SYMLINK_ROOT/logical"

echo "-- Reproducing the logical/physical split without /var..."
if [ -L "$SYMLINK_ROOT/logical" ] && [ -d "$SYMLINK_ROOT/logical" ]; then
  ok "temp root is reachable through a symlink"
else
  fail "symlinked temp root was not created"
fi

LOGICAL_FIXTURE="$(TMPDIR="$SYMLINK_ROOT/logical" mktemp -d)"
PHYSICAL_FIXTURE="$(cd "$LOGICAL_FIXTURE" && pwd -P)"

if [ "$LOGICAL_FIXTURE" != "$PHYSICAL_FIXTURE" ]; then
  ok "mktemp -d under the symlink yields a logical path distinct from the physical one"
else
  fail "no logical/physical split: '$LOGICAL_FIXTURE' resolved to itself"
fi

if [ "$LOGICAL_FIXTURE" -ef "$PHYSICAL_FIXTURE" ]; then
  ok "both paths still address the same directory"
else
  fail "logical and physical paths address different directories"
fi

echo "-- Resolver canonicalizes a symlinked start dir and workspace root..."
WS_LOGICAL="$LOGICAL_FIXTURE/workspace"
WS_PHYSICAL="$PHYSICAL_FIXTURE/workspace"
mkdir -p "$WS_LOGICAL/P400/spec"
cat >"$WS_LOGICAL/.spec-drive-config.json" <<EOF
{"scope":"workspace","workspaceRoot":"$WS_LOGICAL","projectsPath":"."}
EOF

RESOLVED_CONTAINER="$(HOME="$PHYSICAL_FIXTURE" XDG_CONFIG_HOME="$PHYSICAL_FIXTURE/no-config" \
  bash -c ". hooks/scripts/resolve-config.sh && spec_drive_resolve_projects_container \"$WS_LOGICAL/P400\"")"

if [ "$RESOLVED_CONTAINER" = "$WS_PHYSICAL" ]; then
  ok "a symlinked start dir and workspaceRoot resolve to the physical container"
else
  fail "resolver returned '$RESOLVED_CONTAINER' (expected '$WS_PHYSICAL')"
fi

# This is the mistake the harness kept making: comparing a raw fixture path against
# resolver output. Asserting the mismatch keeps the hazard documented as behaviour.
if [ "$RESOLVED_CONTAINER" != "$WS_LOGICAL" ]; then
  ok "an uncanonicalized fixture path would not match resolver output"
else
  fail "logical fixture path unexpectedly matched resolver output"
fi

echo "-- Re-running fixture-allocating suites through the symlinked temp root..."
# The guard: any suite that allocates fixtures without canonicalizing them fails
# here, on Linux, exactly as it would on a macOS runner.
for suite in hooks schema registrar cross-cli smoke; do
  if SPEC_DRIVE_SYMLINK_TMPDIR_RUN=1 TMPDIR="$SYMLINK_ROOT/logical" \
      bash "test/test-$suite.sh" >"$SYMLINK_ROOT/$suite.log" 2>&1; then
    ok "test-$suite.sh passes under a symlinked temp root"
  else
    fail "test-$suite.sh fails under a symlinked temp root"
    grep "FAIL:" "$SYMLINK_ROOT/$suite.log" | head -5 | sed 's/^/      /' || true
  fi
done

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
