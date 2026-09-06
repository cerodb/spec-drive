---
description: Show kernel-owned workflow and execution status
argument-hint: ""
allowed-tools: [Read, Bash, Glob]
---

# /spec-drive:status

Resolve one cwd-bound spec directory. Refuse ambiguous fallback discovery. For execution information, invoke `hooks/scripts/execution-kernel.mjs` with:

```json
{"op":"status","specDir":"<specDir>"}
```

The returned `status` object is authoritative. Do not count checkboxes or interpret `taskIndex`.

Display:

```text
=== Spec-Drive Status ===

Project:          {name}
Phase:            {phase}
Mode:             {mode}
Current task:     {status.currentTaskId or "none"}
Stage:            {status.currentStage}
Active attempt:   {status.activeAttemptId or "none"}
Last failure:     {status.lastFailureClass or "none"}
Accepted tasks:   {count of status.taskStates with status=accepted}/{status.taskOrder.length}
Dispatch budget:  {current task dispatchFailures}/{status.budgets.maxDispatchFailures}
Attempt budget:   {current task executionAttempts}/{status.budgets.maxExecutionAttempts}
Global budget:    {status.budgets.globalBudgetUsed}/{status.budgets.maxGlobalOperations}
```

`name`, `phase`, `mode`, and `awaitingApproval` may be read for lifecycle presentation from the same state file; they must never override the kernel execution fields above. Show the last three learnings and current blockers as informational projections only.

Stage guidance:

- `ready`: `/spec-drive:implement` can request the next kernel dispatch.
- `dispatching` or `indeterminate`: do not redispatch; inspect the attempt and recover explicitly if start is uncertain.
- `reported_complete` or a promotion stage: run `/spec-drive:implement` so kernel `resume`/`accept` can finish.
- `recovery_required` or `blocked`: show `lastFailureClass` and require the kernel recovery or upstream correction indicated by the error.
- `completed` with `currentTaskId=null`: all required tasks are closed by the kernel.

Never claim completion from transcript sentinels, checkbox counts, or an executor report.
