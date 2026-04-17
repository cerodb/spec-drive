# Changelog

## v1.2.0 — 2026-04-17

P336 closes as a calibration release that keeps the benchmark research gains while fixing the main regressions exposed by the rerun.

### Highlights

- added the canonical `/spec-drive:tasks` command surface directly as `commands/tasks.md`
- tightened coordinator conflict detection to reduce false positives from inert quoted or log-like text
- recalibrated architect and task-planner prompts to restore downstream compression without giving up rigor
- updated tests and validation flow to cover the corrected command surface and calibrated behavior
- confirmed the fixes with a full post-fix benchmark rerun and passing local structure/command/schema/smoke validation
