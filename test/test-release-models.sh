#!/usr/bin/env bash
# Isolated file-copy rehearsal, not a package-manager or provider test.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
fail() { echo "FAIL: $*" >&2; exit 1; }
if [ "$#" -ne 0 ] && { [ "$#" -ne 2 ] || [ "$1" != --staged ]; }; then
  echo 'Usage: bash test/test-release-models.sh [--staged <directory>]' >&2
  exit 2
fi
# --staged remains a read-only input; all mutations use this private copy.
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/spec-drive-release.XXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT
runtime=(agents commands hooks profiles schemas skills templates)
metadata=(package.json .claude-plugin/plugin.json)
copy_source() {
  local destination="$1" rel
  mkdir -p "$destination/.claude-plugin"
  for rel in "${runtime[@]}" "${metadata[@]}"; do
    cp -R "$ROOT/$rel" "$destination/$rel"
  done
}
compare_source() {
  local tree="$1" rel
  for rel in "${runtime[@]}" "${metadata[@]}"; do
    diff -qr "$ROOT/$rel" "$tree/$rel" >/dev/null || return 1
  done
}
if [ "$#" -eq 2 ]; then
  INPUT="$(cd "$2" && pwd -P)"
  for tree in package installation; do
    compare_source "$INPUT/$tree" || fail "source/$tree runtime bytes differ"
    cp -R "$INPUT/$tree" "$STAGING/$tree"
  done
  cp -R "$INPUT/xdg" "$STAGING/xdg"
else
  copy_source "$STAGING/package"
  cp -R "$STAGING/package" "$STAGING/installation"
  mkdir -p "$STAGING/xdg/spec-drive"
  printf '{}\n' > "$STAGING/xdg/spec-drive/profiles.local.json"
  cp "$STAGING/xdg/spec-drive/profiles.local.json" "$STAGING/xdg/profiles.local.approved.json"
fi
PACKAGE="$STAGING/package"
INSTALL="$STAGING/installation"
XDG_FIXTURE="$STAGING/xdg/spec-drive/profiles.local.json"
XDG_BEFORE="$STAGING/xdg/profiles.local.approved.json"
for fixture in "$XDG_FIXTURE" "$XDG_BEFORE"; do
  jq -e 'type == "object" and length == 0' "$fixture" >/dev/null || fail 'expected empty XDG fixture'
done
compare_xdg() { cmp -s "$XDG_BEFORE" "$XDG_FIXTURE"; }
compare_xdg || fail 'XDG fixture differs before copies'
compare_source "$PACKAGE" || fail 'package differs'
compare_source "$INSTALL" || fail 'initial installation differs'
cp -R "$PACKAGE/." "$INSTALL/"
compare_source "$INSTALL" || fail 'updated installation differs'
compare_xdg || fail 'update changed XDG fixture'
mkdir "$STAGING/reinstallation"
cp -R "$PACKAGE/." "$STAGING/reinstallation/"
compare_source "$STAGING/reinstallation" || fail 'reinstallation differs'
compare_xdg || fail 'reinstall changed XDG fixture'
# Use the positive checks against real mutations, then restore.
printf '\n# deliberate tamper\n' >> "$INSTALL/hooks/scripts/resolve-model.sh"
if compare_source "$INSTALL"; then fail 'accepted altered runtime'; fi
cp "$ROOT/hooks/scripts/resolve-model.sh" "$INSTALL/hooks/scripts/resolve-model.sh"
compare_source "$INSTALL" || fail 'runtime restoration failed'
printf '\n' >> "$XDG_FIXTURE"
if compare_xdg; then fail 'accepted altered XDG bytes'; fi
cp "$XDG_BEFORE" "$XDG_FIXTURE"
compare_xdg || fail 'XDG restoration failed'
echo 'PASS: runtime copies, update, fresh reinstall, tamper detection and XDG fixture preservation'
echo 'NOTE: isolated local file copies only; no provider, marketplace, installed adapter or package manager tested.'
