# Changelog

## v1.4.1 — 2026-08-18

Test-harness maintenance. **No runtime change.**

The plugin code shipped by v1.4.0 is unchanged: no command, agent, hook, skill,
schema, profile, or template was touched. Installing v1.4.1 over v1.4.0 changes
nothing at runtime.

### Fixed

- Test suites built expected paths from the raw output of `mktemp -d` and compared
  them against resolver output, which goes through `portable_realpath`. On macOS the
  temp root is reached through a symlink (`/var` -> `/private/var`), so the two sides
  disagreed and the suites failed on `macos-latest` while passing on `ubuntu-latest`.
  The product behaviour was correct throughout.
- A hooks assertion passed a non-existent start dir, so it exercised the `$PWD`
  fallback instead of the intended tier and could pick up a real workspace config
  above the repo.
- A failure diagnostic ran unguarded under `set -e` with pipefail, so a red suite
  with no `FAIL:` lines aborted the loop and hid every suite after it.

### Added

- `test/test-macos-pathing.sh`, covering a workspace root configured through a
  symlink, wired into `npm test`.

## v1.4.0 — 2026-08-07

Scoped project registration and portable workspace topology.

### Highlights

- Added explicit project/workspace configuration scopes with per-key `project > workspace > legacy XDG` resolution and strict invalid-present failures.
- Added an executable atomic project scaffold used by `/spec-drive:new`, with safe slugs, deterministic core artifacts, Git initialization, rollback, and existing-destination protection.
- Defined canonical project destinations: `spec/` for lifecycle canon, `audit/` for project evidence and diagnostics, `input/` for received material, and `output/` for non-spec deliverables.
- Preserved legacy unscoped configuration and heterogeneous flat or nested workspace layouts.
- Expanded regression coverage for rollback, concurrent project resolution, Linux/macOS portability, synthetic fixtures, and disclosure scanning.
- Kept all remote publication and marketplace/distribution synchronization behind separate explicit owner approval.

## v1.3.4 — 2026-07-20

- Internal test-tooling cleanup so a consistency check no longer flags its own configuration. No functional change to the plugin.

## v1.3.3 — 2026-07-17

- Subprocess model tiers now receive the task prompt via a file (`{promptfile}`) instead of inline command-line text — more robust for large prompts and text containing special characters.
- Codex, Claude frontier, and Coda subprocess profile templates updated to consume the prompt file / stdin.
- The model resolver requires `{promptfile}` for subprocess profiles.

Notes:
- Executors remain pure implementers; the coordinator owns git commits and tracking updates.
- Codex subprocess profiles run under `workspace-write`.

## v1.3.2 — 2026-07-17

- Fixed: the model resolver is now located via `${CLAUDE_PLUGIN_ROOT}`, so routing engages regardless of the working directory. Previously a relative path meant the resolver was not found and tasks fell back to the session model.

## v1.3.1 — 2026-07-17

- Codex subprocess profiles ship with concrete GPT model IDs (`gpt-5.4-mini`, `gpt-5.4`, `gpt-5.5`, `gpt-5.6-sol`).
- Added `agents/executor-subprocess.md`, a CLI-neutral subprocess implementer contract used by `/spec-drive:implement`.
- Executors are pure implementers; the coordinator owns git commits and tracking updates.
- Coda and generic default subprocess profiles remain documented stubs requiring a local `profiles.local.json` override.

Notes:
- Codex subprocess routing works out of the box on runtimes where those model IDs are available.
- Subprocess stdout must end in `TASK_COMPLETE` or `TASK_BLOCKED: <reason>` so the existing implement parser can consume it unchanged.

## v1.3.0 — 2026-07-16

Adaptive model router for spec execution.

- Added optional `model:` and `model_used:` task metadata while preserving existing task files.
- Introduced abstract routing tiers (`light`, `standard`, `advanced`, `frontier`) with Claude Code routing and generic cross-CLI profile stubs.
- Wired `/spec-drive:implement` dispatch through the model resolver with safe inherit fallbacks.
- Added routing reference fixtures as planner calibration examples, legacy no-model compatibility coverage, and schema-stability checks.

Notes:
- Out-of-box automatic model routing is supported for Claude Code agent profiles.
- Codex, Coda, and default subprocess profiles are scaffolding stubs; users provide concrete local commands via `profiles.local.json`.
- Routing quality is LLM-driven; the fixtures calibrate the planner prompt and are checked for reference consistency, not deterministic scoring.

## v1.2.1 — 2026-04-18

Post-QA polish release after the v1.2.0 calibration wave.

### Highlights

- researcher now performs an explicit sibling-spec discovery pass under `repoRoot/specs/`
- `research.md` now requires a `## Related Specs` section, even when no overlap is found
- task-planner now uses an explicit `remoteTarget` gate before adding Phase 5 PR lifecycle work
- local-only projects now default to no PR lifecycle unless there is positive remote-repo evidence
- structural tests now guard both behaviors against regression

## v1.2.0 — 2026-04-17

P336 closes as a calibration release that keeps the benchmark research gains while fixing the main regressions exposed by the rerun.

### Highlights

- added the canonical `/spec-drive:tasks` command surface directly as `commands/tasks.md`
- tightened coordinator conflict detection to reduce false positives from inert quoted or log-like text
- recalibrated architect and task-planner prompts to restore downstream compression without giving up rigor
- updated tests and validation flow to cover the corrected command surface and calibrated behavior
- confirmed the fixes with a full post-fix benchmark rerun and passing local structure/command/schema/smoke validation
