---
project: P283
title: Spec-Drive Distribution and Marketplace
created: 2026-04-08
status: active
---

# Project Log

## 2026-04-08 — Canonical home fixed inside the repo

- Gabriel confirmed that the canonical home of `P283` should be the `spec-drive` repo itself.
- Created `spec/` inside the repo and moved the older spec materials under `spec/legacy-spec/`.
- Opened a new canonical spec-drive track in `spec/` for the marketplace/distribution problem.

## 2026-04-08 — Product decision taken

- The main remediation path is now fixed:
  - create `cerodb/cerodb-plugins` as a marketplace/distribution repo
- Rejected as the primary answer:
  - installer script as the main long-term path
  - docs-only hardening as a sufficient fix

## 2026-04-08 — Current reading of the issue

- The open GitHub issue is valid and focused on installation/distribution, not on core workflow correctness.
- Local tests passing means the repo is publishable as source, but not yet good enough as a clean install product for Claude-compatible users.

## 2026-04-08 — Marketplace scaffold + transition docs

- Created a first local scaffold for the future distribution repo:
  - local repo `cerodb-plugins`
- Added:
  - `.claude-plugin/marketplace.json`
  - `plugins/spec-drive/` as the initial packaged plugin directory
- Updated `README.md` and `INSTALL.md` in `spec-drive` so they no longer imply that the source-repo path is the polished end-user install story.
- This does not finish the work yet:
  - the marketplace repo is local only
  - fresh install validation is still pending
  - `spec/legacy-spec/` still carries historical local-path references and should be sanitized before any future publication from this repo

## 2026-04-08 — First marketplace wave widened to two plugins

- Gabriel decided that the first marketplace wave should include both:
  - `spec-drive`
  - `think-tank`
- Updated the local marketplace scaffold accordingly.
- `think-tank` was copied into the scaffold from the committed `HEAD` state of its source repo to avoid packaging local dirty changes by accident.

## 2026-04-08 — Issue #2 implemented

- Implemented the config resolution chain requested in GitHub issue `#2`:
  - workspace `.spec-drive-config.json` at nearest git root (or cwd if no git root)
  - XDG config at `${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/config.json`
- Added a shared helper script so both hooks resolve config the same way instead of duplicating the logic.
- Added support for relative `projectRoot` values, resolved from the config file location.
- Updated `README.md`, `INSTALL.md`, and command guidance so the new contract is documented consistently.
- Validated with:
  - `bash test/test-hooks.sh`
  - `bash test/test-commands.sh`

## 2026-04-08 — Legacy fallback removed

- Gabriel decided there is no need to preserve `~/.spec-drive-config.json` fallback compatibility.
- Removed home-dotfile fallback from runtime resolution and docs.
- `spec-drive` now resolves config only from:
  - workspace `.spec-drive-config.json`
  - XDG config at `${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/config.json`

## 2026-04-09 — Process quality issue: over-eager phase execution

- Gabriel flagged an important process problem in the plugin workflow:
  - `spec-drive` can push through idea → research → requirements → design → tasks too aggressively without enough scope validation
  - and it may not be respecting the right "agent hat" or phase discipline at each step
- Current interpretation:
  - this is not just a user-preference issue
  - it is a real workflow quality problem when project scope is still ambiguous
- Practical rule captured from this discussion:
  - when scope is still being defined, the system should not run multiple spec phases in one uninterrupted burst without explicit alignment on project identity
  - phase advancement speed must depend on scope clarity, not only on the presence of enough text to keep writing
- This issue strengthens the case for a proper coordinator discipline in spec-drive / `P291`:
  - clearer phase ownership
  - clearer role separation
  - explicit checkpoints before continuing into downstream artifacts

## 2026-04-09 — Canon tightened: auto mode must not skip definition checkpoints

- Documented a stricter interpretation of `--auto` across the operational docs:
  - research, requirements, and design must still pause for review
  - only the transition from task plan into execution may continue autonomously
- Reason for the change:
  - the old wording made it too easy for one runtime to sprint through multiple specialist phases while project identity was still being clarified
  - that is exactly the failure mode Gabriel flagged in live use
- This update is the canonical process correction first.
- Runtime enforcement can be hardened next, but the docs and command contract should no longer imply that full-definition auto-chaining is desirable.

## 2026-04-09 — Marketplace sync pending from corrected auto-mode canon

- The source repo now carries a corrected process contract for `--auto`:
  - definition phases do not auto-chain blindly
  - execution may still continue autonomously after task planning
- The packaged marketplace copy in `cerodb-plugins` was found to be stale and still described `--auto` as a full uninterrupted chain.
- Next release action:
  - publish the corrected source as `1.0.2`
  - sync the packaged plugin in `cerodb-plugins`
  - keep source and marketplace copies aligned again
