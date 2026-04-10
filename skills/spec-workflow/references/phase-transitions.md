# Phase Transitions

Valid state transitions for the spec-drive workflow. Each transition is triggered by a specific command or event.

## Transition Table

| Trigger | From Phase | To Phase | State Changes |
|---------|-----------|----------|---------------|
| `/spec-drive:new` | (none) | research | phase=research, creates idea.md + state file |
| Researcher completes | research | research | awaitingApproval=true (normal mode) |
| `/spec-drive:requirements` | research | requirements | awaitingApproval=false; after PM completes: awaitingApproval=true |
| `/spec-drive:design` | requirements | design | awaitingApproval=false; after architect completes: awaitingApproval=true |
| `/spec-drive:tasks` | design | tasks | awaitingApproval=false; after planner completes: awaitingApproval=true |
| `/spec-drive:implement` | tasks | execution | awaitingApproval=false, taskIndex=0, taskIteration=1, globalIteration=1 |
| Task complete | execution | execution | taskIndex++, taskIteration=1, globalIteration++ |
| Task failure | execution | execution | taskIteration++, globalIteration++ |
| ALL_TASKS_COMPLETE | execution | (done) | State file deleted |

## Auto Mode Transitions

When `mode: "auto"`, automatic continuation is intentionally limited:

| From Phase | Behavior |
|-----------|----------|
| research (complete) | Stop and require review before `/spec-drive:requirements` |
| requirements (complete) | Stop and require review before `/spec-drive:design` |
| design (complete) | Stop and require review before `/spec-drive:tasks` |
| tasks (complete) | `/spec-drive:implement` may start automatically |
| execution | Continue task loop as normal |

Rationale:

- scope clarification is still happening during research, requirements, and design
- phase ownership changes across specialist agents
- auto-chaining definition phases makes it too easy to drift into a wrong project identity before a human notices

Phase checklists are still validated at each transition. If a checklist fails, auto mode stops with an error.

## Invalid Transitions

Commands reject transitions that skip phases or go backwards:

- Cannot run `/spec-drive:design` when phase is "research" (must go through requirements first)
- Cannot run `/spec-drive:requirements` when phase is "idea" (research must complete first)
- Cannot run `/spec-drive:implement` when phase is "design" (tasks must be planned first)

## Refactor

`/spec-drive:refactor` is a cross-cutting command that updates existing spec artifacts in place. It does **not** change the phase counter the same way forward commands do — instead it revises artifacts and then returns control to whichever phase is appropriate.

### Valid Entry States

| Phase | Trigger |
|-------|---------|
| `requirements` | Scope or constraint change discovered after requirements were written |
| `design` | Design flaw discovered before task planning completed |
| `tasks` | Task plan needs regeneration after design/requirement changes |
| `execution` | Mid-cycle discovery — learnings accumulate while tasks are running |
| `completed` | All tasks done; new learnings discovered after the fact |

Any phase `>= requirements` (i.e., `requirements`, `design`, `tasks`, `execution`, or `completed`) is a valid entry point. Running refactor from `research` or `idea` is rejected because no artifact exists yet to update.

### Update Loop

Artifacts are always updated in strict downstream order to avoid forward-reference inconsistencies:

```
requirements.md → design.md → tasks.md → (resume execution)
```

1. **requirements.md** — updated first; incorporates learnings or scope changes
2. **design.md** — updated to reflect revised requirements
3. **tasks.md** — regenerated from the new design; `requirementsSha` and `designSha` rewritten in state
4. **Resume** — if entry phase was `execution`, phase resets to `tasks` so `/spec-drive:implement` re-validates before continuing

Each step is independent: if only design changed, tasks still regenerates (downstream dependency). Skip a step only when the artifact is provably unaffected, and document the rationale in the CHANGELOG.

### Staleness Re-Check Trigger

Staleness is determined by comparing the current file hash against the stored SHA fields in `.spec-drive-state.json`:

- **`requirementsSha`** — SHA of `requirements.md` at the time `tasks.md` was last generated
- **`designSha`** — SHA of `design.md` at the time `tasks.md` was last generated

When either SHA mismatches the current file hash, tasks are considered stale and must regenerate. The hashes are refreshed automatically at the end of each refactor run. This ensures that even a partial refactor (e.g., only requirements updated) will be caught on the next invocation.

SHA generation: `git hash-object <file>` preferred; `sha256sum <file> | cut -c1-64` as fallback.

## Iteration Limits

- `maxTaskIterations` (default: 5): Max retries per individual task. Exceeded = stop with error.
- `maxGlobalIterations` (default: 100): Max total loop iterations. Exceeded = stop with error, suggest manual intervention.
