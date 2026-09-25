#!/usr/bin/env bash
# Deterministic local checks for source, package, and isolated file-copy installation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK="$(cd "$ROOT/.." && pwd -P)"
STAGED=""

fail() { echo "FAIL: $*" >&2; exit 1; }
usage() { echo "Usage: bash test/test-release-models.sh --staged <directory>" >&2; }

if [ "$#" -ne 2 ] || [ "$1" != "--staged" ]; then usage; exit 2; fi
STAGING="$(cd "$2" && pwd -P)"
STAGED="$STAGING/package"
PACKAGE="$STAGING/package"
INSTALL="$STAGING/installation"
APPROVED_ADAPTER="$WORK/adapter-codex/SKILL.md"
STAGED_ADAPTER="$STAGED/adapter-codex/SKILL.md"
APPROVED_XDG="$WORK/execution-xdg/spec-drive/profiles.local.json"
XDG_FIXTURE="$STAGING/xdg/spec-drive/profiles.local.json"
XDG_BEFORE="$STAGING/xdg/profiles.local.approved.json"

[ -d "$STAGED" ] || fail "staged directory does not exist: $STAGED"
[ -f "$APPROVED_ADAPTER" ] || fail "approved external adapter is missing"
[ -f "$APPROVED_XDG" ] || fail "approved XDG override fixture is missing"

profiles=("$ROOT"/profiles/*.json)
sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
same_hash() { [ "$(sha256_file "$1")" = "$(sha256_file "$2")" ]; }
for source in "${profiles[@]}"; do
  rel="${source#"$ROOT"/}"
  [ -f "$STAGED/$rel" ] || fail "staged profile is missing: $rel"
  same_hash "$source" "$STAGED/$rel" || fail "profile SHA-256 differs: $rel"
done

compare_file() {
  local rel="$1"
  [ -f "$STAGED/$rel" ] || fail "staged file is missing: $rel"
  same_hash "$ROOT/$rel" "$STAGED/$rel" || fail "source/staged SHA-256 differs: $rel"
}

compare_file hooks/scripts/resolve-model.sh
compare_file package.json
compare_file .claude-plugin/plugin.json
for group in agents commands; do
  while IFS= read -r -d '' source; do
    rel="${source#"$ROOT"/}"
    compare_file "$rel"
  done < <(find "$ROOT/$group" -type f -print0 | sort -z)
done

# Keep the external adapter's digest check separate from package/source checks.
[ -f "$STAGED_ADAPTER" ] || fail "staged external adapter is missing"
adapter_source_sha="$(sha256_file "$APPROVED_ADAPTER")"
adapter_staged_sha="$(sha256_file "$STAGED_ADAPTER")"
[ "$adapter_source_sha" = "$adapter_staged_sha" ] || fail "external adapter SHA-256 differs"

for tree in "$PACKAGE" "$INSTALL"; do
  [ -d "$tree" ] || fail "isolated release tree is missing: $tree"
  for source in "${profiles[@]}"; do
    rel="${source#"$ROOT"/}"
    [ -f "$tree/$rel" ] || fail "release tree is missing $rel: $tree"
    cmp -s "$source" "$tree/$rel" || fail "release tree bytes differ for $rel: $tree"
  done
  for rel in hooks/scripts/resolve-model.sh package.json .claude-plugin/plugin.json; do
    [ -f "$tree/$rel" ] || fail "release tree is missing $rel: $tree"
    cmp -s "$ROOT/$rel" "$tree/$rel" || fail "release tree bytes differ for $rel: $tree"
  done
  for group in agents commands; do
    while IFS= read -r -d '' source; do
      rel="${source#"$ROOT"/}"
      [ -f "$tree/$rel" ] || fail "release tree is missing $rel: $tree"
      cmp -s "$source" "$tree/$rel" || fail "release tree bytes differ for $rel: $tree"
    done < <(find "$ROOT/$group" -type f -print0 | sort -z)
  done
done

cmp -s "$PACKAGE/adapter-codex/SKILL.md" "$APPROVED_ADAPTER" || fail "package adapter copy differs from approved adapter"
cmp -s "$INSTALL/adapter-codex/SKILL.md" "$APPROVED_ADAPTER" || fail "installation adapter copy differs from approved adapter"

# This is a local byte-copy rehearsal. It does not invoke a package manager.
diff -qr "$PACKAGE" "$INSTALL" >/dev/null || fail "isolated package and installation trees differ"

[ -f "$XDG_FIXTURE" ] || fail "isolated XDG fixture override is missing"
[ -f "$XDG_BEFORE" ] || fail "approved XDG fixture snapshot is missing"
cmp -s "$APPROVED_XDG" "$XDG_BEFORE" || fail "approved XDG fixture snapshot differs from source"
cmp -s "$XDG_BEFORE" "$XDG_FIXTURE" || fail "XDG fixture override differs before release operations"
before_sha="$(shasum -a 256 "$XDG_FIXTURE" | awk '{print $1}')"

# Exercise update and reinstall as file copies only, preserving the override byte-for-byte.
cp -R "$PACKAGE/." "$INSTALL/"
diff -qr "$PACKAGE" "$INSTALL" >/dev/null || fail "update copy did not reproduce package bytes"
cp -R "$PACKAGE/." "$INSTALL/"
diff -qr "$PACKAGE" "$INSTALL" >/dev/null || fail "reinstall copy did not reproduce package bytes"
after_sha="$(shasum -a 256 "$XDG_FIXTURE" | awk '{print $1}')"
[ "$before_sha" = "$after_sha" ] || fail "XDG override bytes changed across update/reinstall"
cmp -s "$XDG_BEFORE" "$XDG_FIXTURE" || fail "full XDG override bytes changed across update/reinstall"

# Prove that the fixture comparison notices a divergence, then restore from the approved file.
printf '\n' >> "$XDG_FIXTURE"
if python3 "$WORK/verify-evidence.py" release-staged >/dev/null 2>&1; then
  fail "release-staged verifier accepted deliberate XDG fixture divergence"
fi
cp "$XDG_BEFORE" "$XDG_FIXTURE"
cmp -s "$XDG_BEFORE" "$XDG_FIXTURE" || fail "fixture was not restored from approved copy"

echo "PASS: source/staged hashes, isolated copy installation, external adapter SHA-256 ($adapter_source_sha), and XDG override bytes agree"
echo "NOTE: package and installation checks use local file copies; no published release or real package manager is claimed."
