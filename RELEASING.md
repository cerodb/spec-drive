# Releasing Spec-Drive

## Versioned release files

Before preparing a release, synchronize the version in:

1. `package.json`
2. `.claude-plugin/plugin.json`
3. `CHANGELOG.md`
4. `release-staging/package/package.json`
5. `release-staging/package/.claude-plugin/plugin.json`
6. `release-staging/installation/package.json`
7. `release-staging/installation/.claude-plugin/plugin.json`

Refresh the local package and installation trees from the source release. They
must contain the runtime integration files: `agents/`, `commands/`,
`hooks/hooks.json`, every script under `hooks/scripts/`, `profiles/`,
`schemas/`, `skills/`, and `templates/`. Keep the external Codex adapter at
`../adapter-codex/SKILL.md`; copy it into each staged tree at
`adapter-codex/SKILL.md` and preserve its independently maintained contents.
The `commands/tasks.md` and `commands/tasks-cmd.md` copies must stay identical.

The three lean executor instructions introduced during 1.3 maintenance must
remain present in both `agents/executor.md` and
`agents/executor-subprocess.md`: pass a task-relevant progress extract, apply
relevant learnings, and use targeted reads when context is missing. Do not
replace the extract with the full progress history.

## Marketplace integration

The marketplace repository has separate release metadata which must be updated
as part of an explicitly authorized publication:

1. `cerodb-plugins/plugins/spec-drive/package.json`
2. `cerodb-plugins/plugins/spec-drive/.claude-plugin/plugin.json`
3. `cerodb-plugins/.claude-plugin/marketplace.json`, the `spec-drive` index
   entry

Claude's `/plugin` UI reads the marketplace index version from
`cerodb-plugins/.claude-plugin/marketplace.json`. Updating the plugin package
alone can leave the UI showing an older version. Preparing local files or
passing local checks does not authorize marketplace synchronization,
publication, or any remote operation.

## Local staging and evidence

Run `python3 ../verify-evidence.py quality` to check source documentation,
version metadata, JSON files, the synchronized task commands, documented paths,
and lean executor instructions. Refresh the isolated local release copy under
`../release-staging/`, then run:

```bash
python3 ../verify-evidence.py release-staged
```

`release-staged` compares local source, package, installation, adapter, and
approved fixture bytes. It is a fixture-based check; it does not install
through a package manager, invoke a model/provider, or prove a runtime smoke
test. A real runtime smoke must be run separately in a disposable
environment and recorded in `../evidence/runtime-release.json` with requested
and effective model IDs, process outcome, and hashed output captures. A fixture
or model catalog is not runtime evidence. Marketplace publication requires
separate evidence in `../evidence/release-published.json` and explicit owner
authorization.

Keep user-local overrides and private execution evidence outside the staged
package and installation trees. In particular, do not distribute experimental
model or reasoning-effort overrides, authentication material, prompts, or raw
provider diagnostics.
