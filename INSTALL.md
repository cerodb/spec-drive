# Install Guide

This file is the operational install guide for `spec-drive`.

Use it when you want concrete setup steps instead of the higher-level overview in `README.md`.

Important install note:

- the preferred install path is marketplace installation for Claude-compatible runtimes
- this source-repo install path is still useful for development and validation
- but it should not be treated as the final preferred distribution experience

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
- the tests are plain shell scripts and are intended to remain portable
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

Default project root:

```text
~/spec-drive-projects
```

Optional override file. Resolution order is first-match-wins:

```text
.spec-drive-config.json           # at nearest git root, or cwd if no git root
~/.config/spec-drive/config.json # or $XDG_CONFIG_HOME/spec-drive/config.json
```

Example:

```json
{
  "projectRoot": "./spec-drive-projects"
}
```

If `projectRoot` is relative, it is resolved relative to the config file location.

## Claude-Compatible Installation

Preferred direction:

- install through the `cerodb/cerodb-plugins` marketplace repo

Current status:

- the marketplace path is live and validated
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

Treat both Kiro and Coda support as manual adapter ports in `v1.0.0`, not native packaged installs.

## Available Commands (v1.1)

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
