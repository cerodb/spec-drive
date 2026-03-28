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

When `mode: "auto"`, the stop-watcher hook continues through phase transitions automatically:

| From Phase | Behavior |
|-----------|----------|
| research (complete) | Immediately invoke `/spec-drive:requirements` |
| requirements (complete) | Immediately invoke `/spec-drive:design` |
| design (complete) | Immediately invoke `/spec-drive:tasks` |
| tasks (complete) | Immediately invoke `/spec-drive:implement` |
| execution | Continue task loop as normal |

Phase checklists are still validated at each transition. If a checklist fails, auto mode stops with an error.

## Invalid Transitions

Commands reject transitions that skip phases or go backwards:

- Cannot run `/spec-drive:design` when phase is "research" (must go through requirements first)
- Cannot run `/spec-drive:requirements` when phase is "idea" (research must complete first)
- Cannot run `/spec-drive:implement` when phase is "design" (tasks must be planned first)

## Iteration Limits

- `maxTaskIterations` (default: 5): Max retries per individual task. Exceeded = stop with error.
- `maxGlobalIterations` (default: 100): Max total loop iterations. Exceeded = stop with error, suggest manual intervention.
