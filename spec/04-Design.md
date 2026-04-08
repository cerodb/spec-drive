---
project: P283
title: Spec-Drive Distribution and Marketplace
created: 2026-04-08
status: active
---

# Design

## Canonical model

Use a two-repo model:

1. `cerodb/spec-drive`
   - source repo
   - development
   - tests
   - prompts, commands, hooks, schemas

2. `cerodb/cerodb-plugins`
   - distribution repo
   - one subdirectory per published plugin
   - marketplace registration target

## Why this model

It cleanly separates:

- source truth for development
- distribution/install truth for users

This directly addresses the current issue:

- cloning the source repo is not the same thing as having a supported install path

## Scope for the first fix

The first delivery does not need to solve every runtime.

It needs to solve:

- Claude-compatible marketplace installability

And it needs to state clearly:

- Codex/Kiro/Coda remain adapter-driven until native installers exist

## Marketplace scaffold

The initial marketplace repo should look like:

```text
cerodb-plugins/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/
    └── spec-drive/
        ├── .claude-plugin/
        ├── agents/
        ├── commands/
        ├── hooks/
        ├── skills/
        ├── templates/
        ├── schemas/
        ├── README.md
        └── LICENSE
```

This keeps the marketplace repo self-contained for installer consumption while preserving `spec-drive` as the source repo.

## Fresh install validation

The first real acceptance test should be:

1. register the marketplace in a fresh Claude-compatible runtime
2. install `spec-drive` from the marketplace, not from the source repo
3. verify plugin discovery and hook loading
4. run a disposable smoke project:
   - `/spec-drive:new test-project ...`
   - `/spec-drive:research`
5. verify:
   - project scaffold appears
   - `research.md` appears
   - state/progress files update

This is the real bar for closing the installation gap.

## Transitional rule

Until the marketplace repo exists:

- docs may still mention manual/source-repo paths
- but they must be explicitly labeled as temporary or developer-oriented
- they must not be presented as the preferred end-user path

## Legacy note

Older `P283` materials remain preserved under:

- `spec/legacy-spec/`

They are historical context, not the canonical source of truth for this new distribution track.
