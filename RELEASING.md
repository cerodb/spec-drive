# Releasing Spec-Drive

## Minimum version sync checklist

Whenever you cut a new Spec-Drive release, sync all of these before calling the release done:

1. `package.json`
2. `.claude-plugin/plugin.json`
3. `README.md` — the `- Current release:` line under Release Notes
4. `CHANGELOG.md`
5. source git tag / release notes
6. `cerodb-plugins/plugins/spec-drive/package.json`
7. `cerodb-plugins/plugins/spec-drive/.claude-plugin/plugin.json`
8. `cerodb-plugins/.claude-plugin/marketplace.json` plugin entry for `spec-drive`

Items 1-3 are asserted by `test/test-commands.sh`, so a mismatch fails CI.
Items 4-8 are still manual — check them explicitly.

## Important footgun

Claude's `/plugin` UI reads the marketplace index version from `cerodb-plugins/.claude-plugin/marketplace.json`.
If that file is not bumped, the UI can keep showing an old release even after the plugin package itself was updated correctly.
