# Install Guide

This file is the operational install guide for `spec-drive`.

This guide covers **1.4.6**. The preserved 1.4.5 candidate was not published
separately; its initialization fixes are included in 1.4.6. Use the
[marketplace installation instructions](https://github.com/cerodb/cerodb-plugins#installation)
for distribution, and [cerodb/spec-drive](https://github.com/cerodb/spec-drive)
for source, issues and releases. Verify the installed version after each manager
update or reinstall; Codex adapter installation remains a separate step.

Use it when you want concrete setup steps instead of the higher-level overview in `README.md`.

Important install note:

- the preferred install path is marketplace installation for Claude-compatible runtimes
- this source-repo install path is still useful for development and validation
- but it should not be treated as the final preferred distribution experience
- local installation and validation do not authorize marketplace/distribution sync or any other public action

Preferred marketplace commands:

```text
/plugin marketplace add cerodb/cerodb-plugins
/plugin install spec-drive@cerodb
```

Optional ClawHub wrapper skill (requires the plugin to be installed first):

```bash
clawhub install spec-drive
```

## Prerequisites

Install these first:

- `git`
- `bash`
- `jq`
- `python3` (recovery evidence tests)
- standard Unix tools: `grep`, `sed`, `find`, `readlink`, `mktemp`

Optional but recommended:

- `node` + `npm` so you can run the bundled test suite with `npm test`

## 1. Clone the Repo

```bash
git clone https://github.com/cerodb/spec-drive.git
cd spec-drive
```

## 2. Validate the Checkout

```bash
npm test
```

Current validation truth:

- `npm test` is the main checkout validation path today
- tests use Bash and Python 3; they need no sibling checkout, account or network
- release-copy fixtures use temporary staging and never the real XDG override
- Codex/Kiro/Coda native installers are not part of this repo yet

Or run the shell checks directly:

```bash
bash test/test-structure.sh
bash test/test-hooks.sh
bash test/test-commands.sh
bash test/test-schema.sh
bash test/test-cross-cli.sh
```

## 3. Configure Project Storage

Spec-Drive separates workspace topology from portable project identity.

Canonical project destinations:

- `spec/` for canonical Spec-Drive lifecycle artifacts and workflow state
- `audit/` for project-scoped audits, evidence, diagnostics, investigations, and hygiene records that are neither lifecycle canon nor deliverables
- `input/` for received or collected source material
- `output/` for non-spec deliverables

Agents executing Spec-Drive projects must use these names instead of equivalent ad hoc directories.

Initial scaffold contract:

- create only the project root configuration plus the required `spec/` core
- do not pre-create `audit/`, `input/`, or `output`
- create each optional directory only immediately before its first content is written

Workspace topology can be heterogeneous. A workspace may contain multiple independent project roots, including nested Git repositories.

Configuration resolves per key with this precedence:

1. project scope
2. workspace scope
3. legacy XDG scope

Resolver behavior:

- project scope carries portable project identity and project-local overrides
- workspace scope carries node-local topology such as the projects container
- an absent scope falls through to the next tier
- a present but invalid scope fails instead of being ignored
- legacy XDG remains a compatibility fallback

## Model Routing

Spec-Drive accepts four task tiers: `light`, `standard`, `advanced`, and
`frontier`. A task's explicit `model:` tier is resolved immediately before
dispatch. A missing or unknown tier keeps the existing inherit behavior.
Built-in mappings live in `profiles/claude-code.json`, `profiles/codex.json`,
and `profiles/default.json`; the Coda profile is a subprocess stub.
The effective model can change between dispatches when the active profile or
runtime configuration changes. `model_used:` in `tasks.md` is historical
metadata describing a completed task; it never pins the model for a later run
and never raises a task's tier.

The defaults retained from 1.4.3 are Codex light `gpt-5.6-luna`, standard
`gpt-5.6-sol`, advanced/frontier `gpt-6-astra`; Claude Code frontier uses
`opus` (the other Claude tiers retain their existing mappings). Account access
was validated on the maintainer's account on 2026-09-26. This is not evidence that
the complete adapter pilot or package-manager installation has passed, nor a
guarantee of availability in another account.

The resolver uses this exact selection order for the requested CLI and tier:

1. A complete local scoped value at
   `profiles.<cli>.<tier>` wins without consulting lower-priority profiles.
2. A model-only local scoped value at `profiles.<cli>.<tier>` inherits its
   mechanism and command from a compatible base, in this order: the local
   legacy `<tier>` entry, `profiles/<cli>.json`, then
   `profiles/default.json`. A subprocess base must have a standalone `{MODEL}`
   argument.
3. When no scoped value exists, the local legacy `<tier>` entry is selected.
4. Otherwise the CLI profile `profiles/<cli>.json` is selected.
5. Otherwise the default profile `profiles/default.json` is selected. If no
   entry exists, the resolver reports unresolved inheritance.

Absent entries fall through as described. A present invalid selected profile
fails with an error; it is never silently skipped. A complete scoped value can
win even if a lower-priority legacy entry is invalid. Legacy global entries
remain compatible and produce a warning. If you want to convert one, do so
manually by choosing which CLI-specific value belongs under
`profiles.<cli>.<tier>` in `profiles.local.json`. The resolver does not copy,
display, or convert legacy values for you.

### Recovery, partial work, and privacy

Automatic recovery is limited to one retry after a confirmed model rejection
before work starts. It keeps the same task, tier, CLI, prompt, and dispatch
unit. A configured replacement is preferred; otherwise the user may choose a
replacement model. The selected tier entry's `model` value is the only profile
field updated, and the update preserves other profile values. A second
rejection, an unclear outcome, or a write/validation conflict stops for manual
attention. Once work has started, normal attempt limits apply: partial work is
preserved and the task does not advance until its required artifact passes
validation.

Recovery state records the effective selection and task identity, not prompt
contents, raw provider messages, or secrets. Review local profile changes and
partial artifacts before resuming after a blocked attempt.

Example layout:

```text
workspace-root/
  .spec-drive-config.json
  projects/
    my-project/
      .spec-drive-config.json
      spec/
        idea.md
        .progress.md
        .spec-drive-state.json
      audit/   # optional, created lazily
      input/   # optional, created lazily
      output/  # optional, created lazily
```

## Claude-Compatible Installation

Preferred direction:

- install through the `cerodb/cerodb-plugins` marketplace repo

Current status:

- the marketplace is the distribution channel; verify its displayed version and the installed bytes after installation
- the steps below remain the source-repo bootstrap path

This repo already contains Claude-style plugin metadata:

- `.claude-plugin/plugin.json`
- `hooks/hooks.json`

What you need to do:

1. Make the repo available to the Claude runtime's plugin loader.
2. Point the loader at the repo root.
3. Ensure `${CLAUDE_PLUGIN_ROOT}` resolves correctly so the two hook scripts can run:
   - `hooks/scripts/context-loader.sh`
   - `hooks/scripts/stop-watcher.sh`
4. Restart the runtime if it caches plugin metadata.

Minimum validation:

```bash
bash hooks/scripts/context-loader.sh <<< '{"cwd":"/tmp"}'
bash hooks/scripts/stop-watcher.sh <<< '{"cwd":"/tmp"}'
```

If your Claude environment uses a local plugin directory, install this repo there using that runtime's normal plugin mechanism. This repository is already laid out for that style of loading.

Do not present this temporary source-repo path as equivalent to a polished marketplace install.

## Codex Installation

There is no native Codex installer in this repo yet.

`review/adapter-codex/SKILL.md` is the full Codex companion distributed alongside
the core; it is installed separately. Merely unpacking this source does not replace
an installed skill.

For a separately installed companion, set `SPEC_DRIVE_DIR` to the absolute root
of the selected core (containing `commands/`, `agents/`, and `hooks/`) in its
execution environment. The companion validates that directory before use.
It does not select a version from runtime caches. Its old relative-layout fallback
is used only when no explicit path is set and a valid core exists there.

For an isolated pilot, open a fresh session in a disposable project, ask it to read
this candidate companion by its path, and set `SPEC_DRIVE_TEST_CORE` to the absolute
candidate checkout root for that session. This takes precedence over `SPEC_DRIVE_DIR`.
Use a separate temporary XDG configuration for test overrides. Keep the stable
skill, stable plugin and normal user overrides intact. Record the resolved core
path/version and actual results before claiming the pilot passed.

Use `spec-drive` as a workflow pack:

1. Keep the repo accessible from the Codex workspace.
2. Expose `commands/` as reusable command prompts.
3. Expose `agents/` as reusable role prompts.
4. Reuse `templates/` and `schemas/spec-drive.schema.json`.
5. Recreate the lifecycle behavior of:
   - `hooks/scripts/context-loader.sh`
   - `hooks/scripts/stop-watcher.sh`

Minimum recommended contract in Codex:

- session start should surface active spec context if present
- stop/end-of-turn should decide whether execution should continue
- artifact chain should remain unchanged:
  - `idea.md`
  - `research.md`
  - `requirements.md`
  - `design.md`
  - `tasks.md`
  - `.progress.md`
  - `.spec-drive-state.json`

This means Codex support is real but adapter-driven, not "install and go".

## Kiro Installation

There is no Kiro-native package in this repo.

Recommended approach:

1. Import or copy the prompts from `agents/` and `commands/`.
2. Preserve the Markdown artifact templates from `templates/`.
3. Preserve the state schema from `schemas/spec-drive.schema.json`.
4. Recreate the hook behavior in Kiro's own lifecycle/events mechanism.

Do not rename the artifact files unless you are also changing the whole workflow contract.

## Globant Coda Installation

There is no Globant Coda-specific installer here either.

Recommended approach:

1. Import the role prompts from `agents/`.
2. Import the command prompts from `commands/`.
3. Keep the exact artifact chain and state file naming.
4. Reimplement session-start and stop logic using Coda's own runtime hooks or orchestration layer.

Treat both Kiro and Coda support as manual adapter ports, not native packaged installs.

## Available Commands

The source prompts for task planning and implementation are
`commands/tasks.md` and `commands/implement.md`.

After installation, the following commands are available:

| Command | Description |
|---|---|
| `/spec-drive:new` | Create a new spec-driven project |
| `/spec-drive:research` | Run the research phase |
| `/spec-drive:requirements` | Generate requirements from research |
| `/spec-drive:design` | Generate design from requirements |
| `/spec-drive:tasks` | Generate task list from design |
| `/spec-drive:implement` | Start or resume autonomous execution |
| `/spec-drive:status` | Show current phase and progress |
| `/spec-drive:list` | List all spec-drive projects with phase and last-activity |
| `/spec-drive:switch` | Switch the active spec-drive project |
| `/spec-drive:refactor` | Iterate coherently on spec artifacts after discovering design flaws during execution |
| `/spec-drive:cancel` | Cancel and optionally remove the active project |
| `/spec-drive:help` | Show help and workflow overview |

To navigate multiple projects:

```text
/spec-drive:list
/spec-drive:switch
```

To update spec artifacts after discovering design issues mid-execution:

```text
/spec-drive:refactor
```

## Post-Install Smoke Test

Whichever runtime you use, the minimum smoke test is:

1. Create a new project:

```text
/spec-drive:new test-project Build a tiny test feature
```

2. Confirm these files exist under the project `spec/` directory:

- `idea.md`
- `.progress.md`
- `.spec-drive-state.json`

3. Continue one phase:

```text
/spec-drive:research
```

4. Confirm `research.md` appears and the state file is updated.

## Workflow Guardrail

`--auto` is not a license to bypass project-definition checkpoints.

Current intended behavior:

- research stops for review
- requirements stops for review
- design stops for review
- tasks may hand off directly into `/spec-drive:implement`

Reason:

- scope and project identity are still being clarified during definition phases
- each phase uses a different specialist role
- pushing through all phases automatically can compound the wrong interpretation before a human sees it

## Safety Expectations

The current repo already includes guardrails for:

- project-root validation
- ambiguous active project detection
- safe state-file updates
- bounded iteration caps
- deletion guardrails
- unsafe verify-command rejection

Even so, do not treat installation as “fire and forget.” Run the smoke test in a disposable project first.

The local source repository is separate from marketplace/distribution sync. Every issue, push, pull request, release, publication, or marketplace/distribution sync requires separate explicit owner approval.
