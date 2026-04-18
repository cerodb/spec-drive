# Changelog

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
