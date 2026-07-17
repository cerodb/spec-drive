# Changelog

## v1.3.0 — 2026-07-16

Adaptive model router release for spec execution.

### Highlights

- added optional `model:` and `model_used:` task metadata while preserving existing task files
- introduced abstract routing tiers (`light`, `standard`, `advanced`, `frontier`) with Claude Code routing and generic cross-CLI profile stubs
- wired `/spec-drive:implement` dispatch through the model resolver with safe inherit fallbacks and fail-fast errors for unresolved subprocess placeholders
- added routing reference fixtures as planner calibration examples, legacy no-model compatibility coverage, schema-stability checks, and a public-repo cleanliness gate
- kept private/local provider details out of the public plugin; Codex/Coda/default subprocess profiles require local `profiles.local.json` overrides before use

### Scope notes

- Out-of-box automatic model routing is supported for Claude Code agent profiles.
- Codex, Coda, and default subprocess profiles are scaffolding stubs; users must provide concrete local commands without `{MODEL}` or `{CMD}`.
- Routing quality remains LLM-driven. The fixtures calibrate the planner prompt and are checked for reference consistency, not deterministic LLM-quality scoring.
- `claude -p --help` confirms `--effort` is accepted for the shipped Claude Code frontier subprocess command.

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
