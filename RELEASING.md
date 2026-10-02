# Releasing Spec-Drive

## Release 1.4.6

Version 1.4.6 retains the unpublished 1.4.5 initialization fixes and adds a shared
recovery protocol to `/spec-drive:new`. Resolver, scaffold, routing and researcher
failures stop mutations and dependent dispatches, then return control to the calling
agent for read-only inspection. The agent applies only an unequivocal, safe,
already-authorized resolution; otherwise it asks the human one contextual question
with a concrete recommendation. Without an answer the decision remains pending.
Resumption rereads actual state and artifacts, preserving completed work without
reinitialization or blind retries. Scaffold protections, model recovery, defaults
and the Codex companion are unchanged from the preceding candidate. Version 1.4.5
was not published separately. Tests cover shell behavior and instruction contracts,
not conversational model E2E. Record platform CI results separately for the exact
release commit; publication does not establish installation results.

## Previous source candidate 1.4.5

This unreleased candidate distinguishes new-directory creation, non-clobbering
adoption of an existing directory, and read-only resume of an existing spec while
preserving its approval gates. Partial and conflicting projects are preserved with
explicit diagnostics. Legacy path-only output remains compatible, and
`/spec-drive:new` uses the JSON opt-in contract. Preservation, idempotency,
worktree, optional legacy and concurrency regressions cover these paths. Model
defaults and the separately distributed Codex companion remain unchanged. Local
validation does not establish publication, marketplace availability, installation,
CI or new provider results.

The canonical source, issue tracker and releases are maintained in
[cerodb/spec-drive](https://github.com/cerodb/spec-drive). Distribution and
[installation instructions](https://github.com/cerodb/cerodb-plugins#installation)
live in the marketplace repository. Synchronize both for each release.
Model access was validated on the maintainer's account on 2026-09-26; provider
results remain account-, CLI-version- and date-specific. Record the complete
adapter pilot, actual package-manager update/reinstall and Codex adapter promotion
separately; source publication does not establish those results.

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
Include public documentation as appropriate. Exclude local implementation tracking,
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

The authorized defaults are Codex light gpt-5.6-luna, standard gpt-5.6-sol and
advanced/frontier gpt-6-astra; Claude Code frontier is opus, with its other tiers
unchanged. Access validation on the maintainer's account on 2026-09-26 does
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
