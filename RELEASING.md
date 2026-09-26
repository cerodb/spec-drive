# Releasing Spec-Drive

## Candidate 1.4.3

This is local preparation, not a published or installed release. Model access
has been validated on the maintainer's Dell environment; the complete adapter
pilot, marketplace publication, actual package-manager update/reinstall and
promotion of the Codex adapter remain separate gates. Record each actual result.

Synchronize package.json, .claude-plugin/plugin.json, README.md, INSTALL.md and
CHANGELOG.md. Run `npm test` from this checkout. CI is configured for Linux and
macOS; record the actual candidate SHA and CI result before claiming CI passed.

## Local staging

`bash test/test-release-models.sh` creates and removes its own temporary staging.
It compares all runtime directories (agents, commands, hooks, profiles, schemas,
skills, templates) and both manifests, exercises update and fresh reinstall as
file copies, and proves that runtime and XDG-byte tampering are rejected. It uses
only an empty isolated XDG fixture, never the user's configuration.

The optional `--staged <directory>` interface remains available. Input must contain
package/, installation/ and xdg/ with spec-drive/profiles.local.json plus
profiles.local.approved.json. Both XDG files must be empty JSON objects with equal
bytes. Input is checked against the source and copied to temporary staging before
mutation; it is not modified. Legacy sibling helper and adapter paths are not used.
The adapter is outside the core comparison and must be checked separately when promoted.

`bash test/test-version-consistency.sh` checks manifest versions, documentation
and equality of commands/tasks.md and commands/tasks-cmd.md. Recovery fixtures and
the evidence-reader negative tests are part of npm test; they do not claim a real
coordinator or provider execution. Guided evidence is checked separately with
`bash test/test-model-recovery.sh --evidence <directory>`.

## Distribution contents and review

Copy runtime directories and manifests from the exact validated source candidate.
Include public documentation as appropriate. Exclude local spec/pg219/ tracking,
user overrides, private captures, credentials and experimental model settings.
Include the full review/adapter-codex/SKILL.md as a separately distributed companion,
along with its installation instructions. It is not installed automatically with the
core; promotion and installed-byte verification are separate. Installed companions
use SPEC_DRIVE_DIR to select the core root. Isolated sessions use SPEC_DRIVE_TEST_CORE
instead and must not overwrite the stable skill, plugin or normal user overrides.
Do not embed private filesystem paths or select an arbitrary cached plugin version.

Preserve the three lean executor instructions in agents/executor.md and
agents/executor-subprocess.md: pass a task-relevant progress extract, apply relevant
learnings, and use targeted reads when context is missing.

## Provider and publication gates

The authorized defaults are Codex light gpt-6-luna, standard gpt-6-sol and
advanced/frontier gpt-6-astra; Claude Code frontier is opus, with its other tiers
unchanged. Access validation on the maintainer's Dell is account-specific and does
not establish adapter-pilot success. Do not infer availability from resolver output
or fixtures. Retain date, CLI/version, requested/effective model, exit status and
real result in sanitized evidence. Record the isolated end-to-end pilot separately
before claiming it passed; models or accounts not exercised remain unverified.

After explicit publication approval, synchronize the marketplace package manifests
and the spec-drive entry in cerodb-plugins/.claude-plugin/marketplace.json. The index
controls the version displayed by the plugin UI. Verify the published source/tag,
package/index, CI for that SHA and installed bytes. Exercise actual manager update
and reinstall separately, preserving user-local override bytes without publishing
them. Local file-copy equality does not satisfy those gates.
