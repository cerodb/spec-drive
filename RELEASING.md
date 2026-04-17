# Releasing Spec-Drive

## Minimum version sync checklist

Whenever you cut a new Spec-Drive release, sync all of these before calling the release done:

1. `package.json`
2. `.claude-plugin/plugin.json`
3. source git tag / release notes
4. `cerodb-plugins/plugins/spec-drive/package.json`
5. `cerodb-plugins/plugins/spec-drive/.claude-plugin/plugin.json`
6. `cerodb-plugins/.claude-plugin/marketplace.json` plugin entry for `spec-drive`

## Important footgun

Claude's `/plugin` UI reads the marketplace index version from `cerodb-plugins/.claude-plugin/marketplace.json`.
If that file is not bumped, the UI can keep showing an old release even after the plugin package itself was updated correctly.
