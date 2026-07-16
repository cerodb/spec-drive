# Changelog

## v1.3.0 — 2026-07-16

Adaptive model router release for spec execution.

### Highlights

- added optional `model:` and `model_used:` task metadata while preserving existing task files
- introduced abstract routing tiers (`light`, `standard`, `advanced`, `frontier`) with generic per-CLI profile files
- wired `/spec-drive:implement` dispatch through the model resolver with safe inherit fallbacks
- added routing-quality fixtures, legacy no-model compatibility coverage, schema-stability checks, and a public-repo cleanliness gate
- kept private/local provider details out of the public plugin; local deployments can layer private profiles outside the repo

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
