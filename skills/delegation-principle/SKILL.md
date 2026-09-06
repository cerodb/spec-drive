# Delegation Principle

The `/spec-drive:implement` coordinator delegates task work and acts only as an adapter to the execution kernel.

## Ownership

`hooks/scripts/execution-kernel.mjs` is the sole authority for:

1. validating the approved plan
2. selecting the next stable `taskId`
3. reserving attempts and charging budgets
4. classifying dispatch/start evidence through `report`
5. running authoritative final Verify
6. promoting isolated work, committing, and projecting tracking
7. pause, resume, recovery, and completed closure

The coordinator discovers the project, invokes kernel operations, dispatches the exact returned envelope, records adapter start evidence independently, and forwards one identity-bound structured executor report. It never creates a second ledger.

## Implementer boundary

Regular tasks go to the executor; checkpoint tasks go to the QA engineer. Both operate with the kernel-provided `taskId`, `attemptId`, and worktree. They may inspect and implement within their declared scope, but they do not run Git, final Verify, state updates, tracking, or closure.

Agent sentinels are compatibility text only. `TASK_COMPLETE` and `VERIFICATION_PASS` cannot prove process start, correctness, or completion. Acceptance requires all three independent inputs:

- positive adapter evidence that dispatch started
- a matching `EXECUTOR_REPORT`
- successful kernel `accept`, including authoritative Verify

Proven no-start is reported with `adapterEvidence=not_started` and does not consume an implementation attempt. Unknown start is reported with `adapterEvidence=unknown`, remains indeterminate, and requires explicit kernel recovery before redispatch.

## Coordinator must never

- select or advance tasks by `taskIndex`, checkbox position, or array ordinal
- write attempts, task states, budgets, stage, progress, or checkboxes directly
- run Git, final Verify, promotion, commit, pause/resume, recovery, or closure outside the kernel
- convert an executor sentinel into acceptance
- reset or discard work, attempts, or budgets on cancel/resume

Fresh context isolation remains useful, but it is subordinate to the kernel's durable task identity and ownership protocol.
