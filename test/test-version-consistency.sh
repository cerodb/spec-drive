#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
version="$(jq -er '.version' "$ROOT/package.json")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
test "$(jq -er '.version' "$ROOT/.claude-plugin/plugin.json")" = "$version"
for document in INSTALL.md RELEASING.md; do
  grep -Fq "$version" "$ROOT/$document"
done
readme_version="$(sed -n -e 's/^- Current source candidate: `v\([^`]*\)`.*/\1/p' -e 's/^- Current release: `v\([^`]*\)`.*/\1/p' "$ROOT/README.md")"
test "$readme_version" = "$version"
changelog_version="$(sed -n '/^## v/{s/^## v\([^ ]*\).*/\1/;p;q;}' "$ROOT/CHANGELOG.md")"
test "$changelog_version" = "$version"
cmp "$ROOT/commands/tasks.md" "$ROOT/commands/tasks-cmd.md"
echo "PASS: version $version metadata, documentation and task command copies agree"
