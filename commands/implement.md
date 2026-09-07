---
description: Start or resume kernel-owned task execution
argument-hint: ""
allowed-tools: [Read, Bash, Agent]
---

# /spec-drive:implement

## Select the project runtime first

Before the remaining steps or any state write, locate the existing spec using
the discovery rules below. Send `{"specDir":"<resolved spec directory>"}` on
stdin to `node "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/runtime-route.mjs"` (resolve
the plugin root from this command file if the environment is absent).
If routing fails, stop with its diagnostic and preserve the state.
If `runtime=legacy`, read the returned `commandPath` and follow its **implement**
section instead of the remaining v2 instructions. This branch is the explicit
exception to kernel-only rules below. If `runtime=kernel-v2`, continue below;
a later kernel error must never cause a fallback to legacy.

This command is the execution bridge. It delegates implementation, but every trusted execution decision belongs to `hooks/scripts/execution-kernel.mjs`.

<mandatory>
The kernel is the sole owner of task selection by `taskId`, attempt and budget accounting, dispatch/start classification, reports, authoritative Verify, promotion, commits, tracking projection, pause/resume, and completion. This command never selects an unchecked task by ordinal, edits execution state, stages or commits files, checks a task box, updates progress, or treats an agent sentinel as proof of completion.
</mandatory>

## Resolve the active project

Find the spec directory from cwd, `./spec`, or the parent project's `spec` directory. Refuse ambiguous fallback discovery. Set:

- `specDir` to the directory containing `.spec-drive-state.json`
- `repoRoot` to the Git worktree that contains the project
- `kernel` to `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/execution-kernel.mjs`, resolving the plugin root from this command file when the environment variable is absent

If no project is found, stop with the existing `No active spec-drive project found` guidance.

## Kernel protocol

Send every request as one JSON object on stdin and parse the single JSON response. A non-zero exit or `ok:false` is decisive; do not repair the ledger directly.

### 1. Resume before dispatch

Always begin with:

```json
{"op":"resume","specDir":"<specDir>","repoRoot":"<repoRoot>"}
```

`resume` is idempotent and may finish interrupted Verify, promotion, commit, or tracking. If it returns an acceptance, call `resume` again until it returns a ledger summary. Use `ledger.currentTaskId`, `ledger.currentStage`, and `ledger.budgets`; never derive the current task from checkboxes or `taskIndex`.

If the stage is `completed`, output `ALL_TASKS_COMPLETE` from kernel status and stop. The state file remains the durable completed record.

### 2. Reserve the next task

Request the next kernel-selected task:

```json
{"op":"next","specDir":"<specDir>","repoRoot":"<repoRoot>","actor":"implement"}
```

The response `dispatch` is the complete trusted dispatch envelope. Forward its exact `taskId`, `attemptId`, `taskType`, `worktreePath`, Verify metadata, traces, `mechanism`, `model`, `cmd`, and the matching task block to the adapter. The executor cwd is `worktreePath`, not the target repository.

The kernel serializes `[P]` tasks in this release. Do not construct parallel groups or per-index progress files.

### 3. Dispatch and capture start evidence

For `taskType=regular`, dispatch from the kernel-resolved envelope: use `agents/executor.md` when `mechanism=agent`, `agents/executor-subprocess.md` when `mechanism=subprocess`, and the caller's native execution context when `mechanism=inherit`. `model` and `cmd` are already resolved from `resolve-model.sh`; do not infer a mechanism from the task's optional `model` field or resolve a profile again. For `taskType=verify`, use `agents/qa-engineer.md`.

Capture adapter start evidence independently from executor output:

- `started`: the adapter/API positively confirms the agent or subprocess began running the prompt.
- `not_started`: the adapter/API positively confirms failure occurred before the implementation process started.
- `unknown`: neither fact can be proven, including timeout, lost connection, ambiguous tool error, or missing termination evidence.

An executor's `startedWork` field does not upgrade adapter evidence. A `TASK_COMPLETE`, `VERIFICATION_PASS`, or similar sentinel is compatibility text only and is never sufficient evidence of start, correctness, or acceptance.

For subprocess dispatch, write the CLI-neutral prompt to a mode-0600 temporary file and substitute only its path into the resolved command template. Remove the prompt file after the process is known to have ended. Resolver configuration errors stop before launch and qualify as `not_started`; ambiguous launch errors qualify as `unknown`.

### 4. Submit one structured report

Require an `EXECUTOR_REPORT` JSON object with matching `attemptId` and `taskId`. Map it into the kernel request without placing adapter evidence inside the report:

```json
{
  "op": "report",
  "specDir": "<specDir>",
  "repoRoot": "<repoRoot>",
  "attemptId": "<attemptId>",
  "adapterEvidence": "started|not_started|unknown",
  "report": {
    "attemptId": "<attemptId>",
    "taskId": "<taskId>",
    "outcome": "task_complete|task_blocked|task_indeterminate",
    "startedWork": true,
    "summary": "<bounded factual summary>",
    "failureClass": "<class when blocked>"
  }
}
```

If dispatch fails before any executor report exists, the bridge creates only the minimum transport report:

- proven no-start: `outcome=task_blocked`, `failureClass=dispatch_error`, `startedWork=false`, `adapterEvidence=not_started`
- uncertain start: `outcome=task_indeterminate`, `failureClass=dispatch_error`, `startedWork=false`, `adapterEvidence=unknown`

The kernel refunds the implementation-attempt counter only for proven no-start. Unknown start stays indeterminate and must not be redispatched until an operator calls kernel `recover` with explicit evidence that the old process is terminated and its owned worktree is stable.

### 5. Accept only through the kernel

When `report` returns `state=reported_complete`, request:

```json
{"op":"accept","specDir":"<specDir>","repoRoot":"<repoRoot>","attemptId":"<attemptId>"}
```

Only `accept` may run final Verify, validate declared-file ownership, promote worktree bytes, create the implementation commit, project the checkbox/progress tracking, advance `currentTaskId`, and close the run. Report an accept failure verbatim, then inspect `resume`. A failed test records authoritative evidence and returns the ledger to `ready` for a new budgeted attempt. Timeout, environment failure or candidate mutation requires explicit `recover` evidence after the cause is addressed. Interrupted promotion is reconciled through `resume`. Do not run an alternate Verify or perform partial Git/tracking repair.

For `reported_blocked`, `indeterminate`, budget exhaustion, artifact errors, or external changes, display the kernel error and recovery action. Loop only when the kernel returns `currentStage=ready`.

## Completion and safety

- Completion means kernel status has `currentTaskId:null` and `currentStage:completed`, with all required `taskStates` accepted. Transcript text is not completion evidence.
- Never delete the state file or execution worktrees as part of completion.
- Never use `taskIndex`, checkbox position, array ordinal, or agent output to choose or close a task.
- Never run Git, final Verify, promotion, tracking, pause, recovery, or state mutations outside the kernel.
- Preserve unknown or unexpected kernel fields when displaying them; the command owns no parallel schema.
