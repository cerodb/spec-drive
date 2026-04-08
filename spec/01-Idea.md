---
project: P283
title: Spec-Drive Distribution and Marketplace
created: 2026-04-08
status: active
---

# Idea

## Trigger

External feedback on the published `spec-drive` repo says the workflow may be solid, but the install path is not.

The clearest problem is Claude Code distribution:

- no marketplace install path
- unclear local plugin-loader steps
- manual editing of internal Claude files is fragile and not acceptable as the primary path

## Desired outcome

Turn `spec-drive` into something that is:

- discoverable
- installable through a normal plugin marketplace path
- honest about what is native vs adapter-driven
- reusable as the source repo for future plugins under the same publisher

## Decision already made

Gabriel chose the strategic direction:

- primary solution: a `cerodb/cerodb-plugins` marketplace repo
- not an installer script as the main answer
- not docs-only hardening as the final answer
