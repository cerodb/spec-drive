# Spec-Drive

Spec-driven development workflow for coding CLIs.

It takes a project through this chain:

`idea -> research -> requirements -> design -> tasks -> implement`

Each phase produces plain Markdown artifacts so another runtime can continue without hidden session context.

## What This Repo Contains

- `agents/` — role prompts for researcher, product-manager, architect, task-planner, executor, qa-engineer
- `commands/` — slash-command style command specs
- `templates/` — initial artifact templates
- `schemas/` — state schema for `.spec-drive-state.json`
- `hooks/` — session-start and stop hooks for context loading and execution continuation
- `skills/` — supporting workflow and style guidance
- `test/` — validation scripts

## Runtime Support

This repo is not equally automatic everywhere.

| Runtime | Status | Notes |
|---|---|---|
| Claude Code / Claude-compatible plugin loaders | Best supported | Native plugin-style layout present: `.claude-plugin/plugin.json` and `hooks/hooks.json` |
| Codex | Supported via manual adapter | Artifacts, agents, commands, templates, and hooks are portable, but there is no one-click Codex installer in this repo |
| Kiro | Supported via manual adapter | Same protocol/artifacts work, but command/hook wiring must be recreated in Kiro's own extension/prompt mechanism |
| Globant Coda | Supported via manual adapter | Use the Markdown artifacts and port the agent/command prompts into its own tool surface |

Honest version: this repo is fully usable today, but only Claude-style runtimes have native plugin metadata in-tree.

## Validation Status

- Local shell validation passes with `npm test` on Linux.
- The shell test suite is intended to stay POSIX-friendly so it can run on macOS too.
- This repo does **not** yet ship native install adapters for Codex, Kiro, or Globant Coda.
- Cross-CLI support today means:
  - portable artifacts
  - portable prompts
  - manual adapter work per runtime

## Requirements

- `bash`
- `git`
- `jq`
- standard Unix tools: `grep`, `sed`, `find`, `readlink`, `mktemp`

## Install

Preferred install path for Claude-compatible runtimes:

- install from the `cerodb/cerodb-plugins` marketplace repo

Current marketplace install:

```text
/plugin marketplace add cerodb/cerodb-plugins
/plugin install spec-drive@cerodb
```

Current reality:

- this source repo is still the development/source-of-truth repo
- the marketplace/distribution path is now live
- direct source-repo setup remains a developer/bootstrap path, not the preferred end-user install story

### 1. Clone

```bash
git clone https://github.com/cerodb/spec-drive.git
cd spec-drive
```

### 2. Validate the repo

```bash
npm test
```

If you do not want `npm`, the tests are plain shell scripts:

```bash
bash test/test-structure.sh
bash test/test-hooks.sh
bash test/test-commands.sh
bash test/test-schema.sh
bash test/test-cross-cli.sh
```

For runtime-specific install steps, see [INSTALL.md](./INSTALL.md).

## Install in Claude-Compatible Runtimes

Install note:

- the preferred install surface is the `cerodb/cerodb-plugins` marketplace
- the instructions below are the developer/bootstrap path from source

Point your plugin loader at this repository root.

Relevant files:

- plugin manifest: `.claude-plugin/plugin.json`
- hook config: `hooks/hooks.json`
- commands: `commands/`
- agents: `agents/`

If your Claude runtime expects plugins in a local plugin directory, install this repo there using whatever plugin mechanism that runtime already supports. This repo already includes Claude-style metadata, but this source-repo path should be treated as transitional until the marketplace path is the normal install flow.

## Install in Codex, Kiro, or Globant Coda

There is no native installer here yet. Use the repo as a portable prompt/workflow pack.

Minimum manual adapter:

1. Make the repo available to the runtime.
2. Port the six agent prompts from `agents/`.
3. Port the command prompts from `commands/`.
4. Copy the artifact templates from `templates/`.
5. Preserve the state file contract from `schemas/spec-drive.schema.json`.
6. Recreate the two hooks using:
   - `hooks/scripts/context-loader.sh`
   - `hooks/scripts/stop-watcher.sh`

If your runtime cannot execute shell hooks directly, preserve the same behavior in its own lifecycle mechanism:

- Session start: detect active project and surface state/context
- Stop: continue execution loop safely, with ambiguity and iteration guards

This is deliberate. The portability claim is about the artifact/protocol design, not about shipping one-click adapters for every CLI in `v1.0.0`.

## Project Layout at Runtime

By default, projects live under:

```text
~/spec-drive-projects/
  my-project/
    spec/
      idea.md
      research.md
      requirements.md
      design.md
      tasks.md
      .progress.md
      .spec-drive-state.json
```

The project root can be overridden with the first config file found in this order:

```text
.spec-drive-config.json           # at nearest git root, or cwd if no git root
~/.config/spec-drive/config.json # or $XDG_CONFIG_HOME/spec-drive/config.json
~/.spec-drive-config.json        # legacy fallback
```

Example:

```json
{
  "projectRoot": "./spec-drive-projects"
}
```

If `projectRoot` is relative, it is resolved relative to the config file location. That makes workspace-scoped configs portable across machines.

## Quick Start

Start from a new project:

```text
/spec-drive:new my-feature Build a small feature that does X
```

Then continue phase by phase:

```text
/spec-drive:research
/spec-drive:requirements
/spec-drive:design
/spec-drive:tasks
/spec-drive:implement
```

Or use auto mode:

```text
/spec-drive:new my-feature Build a small feature that does X --auto
```

## Safety Notes

This repo includes hardening for:

- safe project-path validation
- ambiguous project detection
- bounded iteration caps
- safer state-file updates
- deletion guards in cancel flows
- guardrails against dangerous verify commands

Still, this is an agentic execution workflow. Review before tagging or exposing it publicly in environments you do not control.

## Cross-CLI Design Goal

Spec-Drive is intentionally artifact-first.

The important contract is not a hidden runtime session. It is the artifact chain:

- `idea.md`
- `research.md`
- `requirements.md`
- `design.md`
- `tasks.md`
- `.progress.md`
- `.spec-drive-state.json`

If those files stay clean and truthful, another CLI can resume the work.
