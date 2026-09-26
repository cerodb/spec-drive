# Spec-Drive

Spec-driven development workflow for coding CLIs.

[cerodb/spec-drive](https://github.com/cerodb/spec-drive) is the canonical source
for development, [issues](https://github.com/cerodb/spec-drive/issues), and
[releases](https://github.com/cerodb/spec-drive/releases). For installation, use the
[cerodb-plugins marketplace instructions](https://github.com/cerodb/cerodb-plugins#installation).
See [INSTALL.md](./INSTALL.md) for runtime-specific setup and model overrides.

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
- `review/adapter-codex/` — adapter review companion, not automatically installed

## Runtime Support

This repo is not equally automatic everywhere.

| Runtime | Status | Notes |
|---|---|---|
| Claude Code / Claude-compatible plugin loaders | Best supported | Native plugin-style layout present: `.claude-plugin/plugin.json` and `hooks/hooks.json` |
| Codex | Supported via manual adapter | Artifacts, agents, commands, templates, and hooks are portable, but there is no one-click Codex installer in this repo |
| Kiro | Supported via manual adapter | Same protocol/artifacts work, but command/hook wiring must be recreated in Kiro's own extension/prompt mechanism |
| Globant Coda | Supported via manual adapter | Use the Markdown artifacts and port the agent/command prompts into its own tool surface |

Honest version: this repo is fully usable today, but only Claude-style runtimes have native plugin metadata in-tree.


## Adaptive Model Router

Spec-Drive accepts optional `model:` task metadata using abstract tiers: `light`,
`standard`, `advanced`, and `frontier`. The planner assigns tiers with a six-signal heuristic;
the executor records `model_used:` for completed tasks.

Scope honesty:

- Out of the box, Claude Code agent routing is supported.
- Codex subprocess defaults are `gpt-5.6-luna` for `light`, `gpt-5.6-sol` for
  `standard`, and `gpt-6-astra` for both `advanced` and `frontier`.
- Claude Code uses `haiku`, `sonnet`, and `opus` agent aliases for the first three
  tiers; `frontier` uses the `opus` subprocess alias with `--effort high`.
- Coda and the generic default subprocess profiles remain public stubs. They document the profile
  shape, but commands containing `{MODEL}` or `{CMD}` are intentionally rejected by
  `hooks/scripts/resolve-model.sh` until the user supplies a full local override.
- Subprocess dispatch uses `agents/executor-subprocess.md`, a CLI-neutral implementer contract. Do not
  send `agents/executor.md` verbatim to subprocess runtimes; it is Claude-Code-flavored.
- To enable a stubbed or custom subprocess runtime, create `~/.config/spec-drive/profiles.local.json`
  with concrete commands and concrete model names. Do not leave `{MODEL}` or `{CMD}` in the final
  command.
- Routing quality is LLM-driven: `agents/task-planner.md` contains reference examples used as
  few-shot calibration. The shell suite checks fixture/example consistency; it does not claim to
  deterministically unit-test the LLM's judgment.

Example scoped local override (in `${XDG_CONFIG_HOME:-~/.config}/spec-drive/profiles.local.json`):

```json
{
  "profiles": {
    "codex": {
      "light": { "model": "your-supported-model-id" }
    }
  }
}
```

Replace the example ID with one supported by your runtime and account. A model-only
override requires a compatible base template with a standalone `{MODEL}` argument.
Complete scoped entries take priority, followed by compatible model-only inheritance,
legacy global entries, the CLI profile and the default profile. Legacy entries still
work with a warning; migration is an explicit user choice. See
[Model Routing](./INSTALL.md#model-routing) for the exact precedence.

Resolve the effective model immediately before dispatch. Historical `model_used:`
records do not pin future selections. Unknown or absent task tiers inherit; definition
delegations without a tier use `standard`. A confirmed pre-work model rejection can
receive at most one retry with the same prompt, unit and template. Uncertain outcomes
and unreconciled reservations pause for supervised review.

The shipped model selections are defaults, not proof of availability for your account.
Provider results apply to the tested account, CLI version and date. Coda/default stubs
remain inactive until configured. The adapter at `review/adapter-codex/SKILL.md` is a
review companion and is not installed by this repository.

## macOS Compatibility

The GitHub Actions workflow configures Linux and macOS checks. Consult the actual run for the release commit before treating CI as passed.

All shell scripts avoid GNU-only extensions:

- `readlink -f` replaced with a portable `portable_realpath()` helper (python3 → realpath → cd/pwd -P fallback)
- `find -mmin` replaced with a portable mtime check (python3 → stat -c %Y on Linux → stat -f %m on macOS)

Prerequisites on macOS: `bash`, `git`, `jq`, `python3`. Install `jq` via Homebrew (`brew install jq`) if not already present.

## Release Notes

- Current release: `v1.4.3` (2026-09-26). See [release details](https://github.com/cerodb/spec-drive/releases/tag/v1.4.3).
- `v1.4.3` fixes recovery continuation and legacy command handling and makes local validation self-contained.
- `v1.4.1` added macOS test-harness fixes without a runtime change over `v1.4.0`.
- `v1.4.0` adds scoped per-key configuration, atomic project scaffolding, canonical project artifact destinations, and expanded portability/security regression coverage.
- `v1.3.0` introduced the adaptive model router: optional `model:`/`model_used:` task metadata, abstract routing tiers, and `/spec-drive:implement` dispatch through the model resolver. The `v1.3.1`-`v1.3.4` patches added concrete Codex subprocess model IDs and the CLI-neutral implementer contract, fixed resolver lookup via `${CLAUDE_PLUGIN_ROOT}`, and moved subprocess prompts to a file handoff.
- `v1.2.1` is a small post-QA polish release: related-spec discovery and conditional PR lifecycle gating.
- `v1.2.0` packaged the successful calibration pass: direct `tasks` command surface, tighter coordinator conflict scoring, and restored design/task compression.

## Validation Status

- `npm test` runs deterministic Bash/Python tests without sibling files, accounts or network.
- Release tests create temporary file-copy staging, detect tampering and preserve an isolated XDG fixture.
- CI is configured for `ubuntu-latest` and `macos-latest`; actual CI and provider results must be recorded separately.
- This repo does **not** yet ship native install adapters for Codex, Kiro, or Globant Coda.
- Cross-CLI support today means:
  - portable artifacts
  - portable prompts
  - manual adapter work per runtime

## Requirements

- `bash`
- `git`
- `jq`
- `python3`
- standard Unix tools: `grep`, `sed`, `find`, `readlink`, `mktemp`

## Install

Preferred install path for Claude-compatible runtimes:

- install from the [cerodb/cerodb-plugins marketplace](https://github.com/cerodb/cerodb-plugins#installation)

Current marketplace install:

```text
/plugin marketplace add cerodb/cerodb-plugins
/plugin install spec-drive@cerodb
```

Optional ClawHub wrapper skill (install after the plugin if you want the wrapper entry point too):

```bash
clawhub install spec-drive
```

Current reality:

- this source repo is the local source-of-truth checkout for development and validation
- marketplace/distribution sync is a separate channel, not an automatic consequence of local edits here
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

The portability claim concerns the artifact/protocol design; manual adapter setup is still required for these runtimes.

## Project Layout at Runtime

Spec-Drive uses four canonical project destinations:

- `spec/` for canonical Spec-Drive lifecycle artifacts and workflow state
- `audit/` for project-scoped audits, evidence, diagnostics, investigations, and hygiene records that are neither lifecycle canon nor deliverables
- `input/` for received or collected source material
- `output/` for non-spec deliverables

Agents executing Spec-Drive projects must use these names instead of ad hoc equivalents when the content matches one of those roles.

The initial scaffold is intentionally minimal. It contains only the project root configuration plus the required `spec/` core. `audit/`, `input/`, and `output/` are optional and must be created only immediately before their first content is written.

Example runtime shape:

```text
workspace-root/
  .spec-drive-config.json        # optional workspace-scope topology
  projects/
    my-project/
      .spec-drive-config.json    # required project-scope identity/overrides
      spec/
        idea.md
        .progress.md
        .spec-drive-state.json
      audit/                     # optional, created lazily
      input/                     # optional, created lazily
      output/                    # optional, created lazily
```

Workspace topology can be heterogeneous. A workspace may contain multiple independent project roots, including nested Git repositories, and Spec-Drive still resolves configuration per key by scope rather than by picking one whole file.

Per-key precedence is:

1. project scope
2. workspace scope
3. legacy XDG scope

Resolution rules:

- A project scope can override only the keys it defines; omitted keys continue to workspace or legacy XDG.
- A configuration that is present but invalid fails immediately instead of being ignored.
- An absent scope falls through to the next precedence tier.
- Legacy XDG remains a compatibility fallback, not the preferred source of truth.
- Project identity stays portable by keeping topology in workspace scope and project-specific identity/overrides in project scope.

## Commands

| Command | Description |
|---|---|
| `/spec-drive:new` | Create a new spec-driven project with `idea.md` and start research |
| `/spec-drive:research` | Run or re-run the research phase |
| `/spec-drive:requirements` | Generate structured requirements from research |
| `/spec-drive:design` | Generate technical design from requirements |
| `/spec-drive:tasks` | Generate implementation task list from design |
| `/spec-drive:implement` | Start or resume autonomous task execution loop |
| `/spec-drive:status` | Show current phase, task progress, and recent activity |
| `/spec-drive:list` | List all spec-drive projects with phase and last-activity |
| `/spec-drive:switch` | Switch the active spec-drive project |
| `/spec-drive:refactor` | Iterate coherently on spec artifacts after discovering design flaws during execution |
| `/spec-drive:cancel` | Cancel and optionally remove the active spec project |
| `/spec-drive:help` | Show help for spec-drive commands and workflow |

## Quick Start

Start from a new project:

```text
/spec-drive:new my-feature Build a small feature that does X
```

If the project needs a wider first pass:

```text
/spec-drive:new my-feature Build a small feature that does X --deep
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

## Small but Important Runtime Notes

- `--deep` asks the researcher for a broader discovery pass before requirements.
- `/spec-drive:research` now performs a lightweight coordinator preflight before delegating research.
- `/spec-drive:requirements` can pause for targeted clarification instead of silently guessing when research leaves important ambiguity unresolved.

Important:

- `--auto` does not mean "write idea, research, requirements, design, and tasks in one blind burst"
- definition phases still pause for review
- auto mode becomes autonomous only after `tasks.md` exists and execution begins

If you have multiple projects, use `list` and `switch` to navigate:

```text
/spec-drive:list
/spec-drive:switch
```

If you discover design flaws mid-execution, use `refactor` to coherently update spec artifacts:

```text
/spec-drive:refactor
```

## Notes

This is an agentic execution workflow: it runs commands and writes files on your behalf. Review the generated task plan before running `/spec-drive:implement`, and review the resulting changes before merging or tagging.

This local source repository is separate from any marketplace or distribution sync. No issue, push, pull request, release, publication, or marketplace/distribution sync is authorized by local validation alone; each requires separate explicit owner approval.

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
