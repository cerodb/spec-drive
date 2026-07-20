# Changelog

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
