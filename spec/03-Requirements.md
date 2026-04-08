---
project: P283
title: Spec-Drive Distribution and Marketplace
created: 2026-04-08
status: active
---

# Requirements

## Goal

Make `spec-drive` installable through a proper plugin marketplace path while keeping the source repo honest about current runtime support.

## Functional Requirements

1. There must be a marketplace-based install path for Claude-compatible runtimes.
2. `spec-drive` must remain the source/development repo, not the only distribution repo.
3. A publisher-level plugin marketplace repo must be defined for current and future `cerodb` plugins.
4. The install documentation must clearly distinguish:
   - native Claude-compatible installation
   - manual adapter use for Codex, Kiro, and Globant Coda
5. The distribution model must be reusable for at least:
   - `spec-drive`
   - `think-tank`

## Non-Functional Requirements

1. The installation path must avoid requiring users to hand-edit internal Claude runtime JSON files.
2. The published docs must be explicit about supported vs adapter-driven runtimes.
3. The new distribution approach must not break the current local test suite.
4. The marketplace structure should stay simple enough to maintain without a second large framework.

## Success Criteria

- a concrete marketplace repo plan exists and is accepted as the canonical install strategy
- `spec-drive` docs no longer imply that source-repo cloning is the preferred Claude install path
- a clear separation exists between source repo and distribution repo
- future work can implement marketplace publication without reopening the product decision
