---
project: P283
title: Spec-Drive Distribution and Marketplace
created: 2026-04-08
status: active
---

# Research

## Current repo reality

`spec-drive` currently contains:

- Claude-style plugin metadata:
  - `.claude-plugin/plugin.json`
  - `hooks/hooks.json`
- portable prompts/artifacts for other runtimes
- no native installer for Codex, Kiro, or Globant Coda

## Verified local state

- repo is clean
- recent release/install commits exist:
  - `37b2ea5` `docs(release): align install and portability story`
  - `c650b2d` `fix(release): improve portability and plugin metadata`
  - `aaef199` `docs(readme): add installation guide by runtime`
- local validation passes:
  - `test-structure`
  - `test-hooks`
  - `test-commands`
  - `test-schema`
  - `test-cross-cli`

Working conclusion:

- this is not primarily a code-quality failure
- it is a distribution/installation/discoverability failure

## GitHub issue feedback

Open issue:

- `#1` — `No marketplace install path — proposal: cerodb/cerodb-plugins umbrella marketplace`

Main claims from the issue:

- `spec-drive` is not present in any marketplace
- Claude Code users get stuck on an undocumented/manual path
- the current path implicitly pushes people toward editing `~/.claude/plugins/installed_plugins.json`
- that file is internal, fragile, and easy to corrupt
- `${CLAUDE_PLUGIN_ROOT}` behavior is not clear enough in local installs

## Decision boundary

The issue does not argue that:

- the workflow design is bad
- the plugin repo is structurally broken

It argues that:

- the source repo is not enough as a distribution channel
- a marketplace/distribution layer is missing

## Strategic direction

Chosen direction:

1. create a publisher marketplace repo:
   - `cerodb/cerodb-plugins`
2. keep `spec-drive` as the source/development repo
3. use the marketplace repo as the normal Claude-install surface
4. keep manual-adapter wording for non-Claude runtimes until native installers exist
5. first marketplace wave should include:
   - `spec-drive`
   - `think-tank`

## First implementation scaffold

A first local scaffold now exists at:

- local repo `cerodb-plugins`

Current shape:

- `.claude-plugin/marketplace.json`
- `plugins/spec-drive/`
- `plugins/think-tank/`

The plugin payload for `spec-drive` is currently copied from the source repo as an initial packaging scaffold, not yet a finalized published distribution repo.
