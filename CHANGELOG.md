# Changelog

## v1.3.4 — 2026-07-20

Cleanliness-gate hardening (test-only; no functional or security change to the plugin).

### Fixed
- `test/test-public-clean.sh` stored the private-identifier deny-list as plaintext pattern
  definitions, so the cleanliness scan (and any external security grep, even for a partial substring
  like `GLM-`) matched the test file itself — a recurring false positive that bit twice during
  development and caused source/marketplace divergence. The deny-list is now stored base64-encoded and
  decoded at runtime, so the file contains no plaintext copy of the terms it screens for. Detection is
  unchanged (verified: an injected `globant_dgx/GLM-4.6` still fails the gate).

## v1.3.3 — 2026-07-17

Subprocess prompt-file hardening release.

### Highlights

- replaced inline subprocess prompt interpolation with `{promptfile}` command templates
- updated coordinator dispatch docs to write the full subprocess prompt to a chmod 600 temp file and pass only the path to the host shell
- updated Codex, Claude frontier, and Coda subprocess profile templates to consume prompt files/stdin instead of inline prompt text
- extended resolver validation so subprocess profiles require `{promptfile}` and reject inline `{prompt}`
- added live security regression coverage for shell metacharacters in task text: prompt content mentioning `$(touch /tmp/pwned)` must not execute on the host

### Scope notes

- Executors remain pure implementers; the coordinator still owns git commits and tracking updates.
- Public subprocess profiles stay sandboxed (`workspace-write` for Codex) and never require full-access defaults.

## v1.3.2 — 2026-07-17

Router activation fix — the model router now actually engages in real runs.

### Fixed
- `commands/implement.md` invoked `hooks/scripts/resolve-model.sh` with a bare relative path. Because
  the coordinator's working directory is the user's project (not the plugin), the script was never
  found and every task silently fell back to the `inherit` mechanism — i.e. the tier router was
  effectively dead code in v1.3.0/v1.3.1. Now invoked via `"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/resolve-model.sh"`
  with the same fallback contract as `agents/coordinator.md`. Caught by a live end-to-end run, not by
  unit tests (which called the resolver with an explicit path).

## v1.3.1 — 2026-07-17

Cross-CLI subprocess reality check release.

### Highlights

- replaced Codex `{MODEL}` placeholders with concrete Dell-verified model IDs: `gpt-5.4-mini`, `gpt-5.4`, `gpt-5.5`, and `gpt-5.6-sol`
- added `agents/executor-subprocess.md`, a CLI-neutral subprocess implementer contract used by `/spec-drive:implement`
- refactored executor contracts so executors are pure implementers and the coordinator owns git commits/tracking
- kept the Coda profile as a documented stub for private/local override on the Mac
- verified real subprocess invocation paths and canary task execution for Codex and Claude frontier under sandboxed subprocess profiles, including coordinator-owned exact commits after `TASK_COMPLETE` parser signals

### Scope notes

- Codex subprocess routing now works out of the box on runtimes with the listed GPT model IDs available.
- Coda and generic default subprocess profiles still require local overrides because their model IDs/commands are deployment-private.
- Subprocess stdout must end in `TASK_COMPLETE` or `TASK_BLOCKED: <reason>` so the existing implement parser can consume it unchanged.
- Public profiles must not ship a full-access sandbox; `test/test-public-clean.sh` now guards against that regression.


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
