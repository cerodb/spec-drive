# Existing projects: legacy conductor

This is the shared compatibility conductor for Claude Code, Codex and Coda. Use
it only when `hooks/scripts/runtime-route.mjs` returns `runtime: legacy` for the
selected spec. It replaces the requested command's kernel protocol for that
project. Announce **Legacy mode: continuing the existing plan and progress**.

Legacy execution is coordinated by the calling agent, sequentially. It retains
the old format; it does not provide kernel attempt accounting, isolated promotion
or crash reconciliation. No global installation switch or automatic migration is
needed. Never enter this mode because a kernel operation failed.

## Read before acting

Read the existing state, tasks.md, requirements.md, design.md, .progress.md and
any project checkpoint/conductor instructions. Locate the actual product repo
and inspect its changes. A spec may live outside that repo. Do not assume its
parent is the product. Preserve completed checkboxes, existing approvals,
history, budgets, counters, worktrees and all unknown state fields. Reading
status or selecting a runtime must not write anything.

If the project records another conductor or an active process, inspect its
checkpoint and process evidence first. Never launch a duplicate executor. An
interrupted task retains its partial work. If process termination or task
identity is uncertain, report that concrete uncertainty and stop execution.

## implement: resume existing work

1. Confirm the existing task plan is approved from recorded evidence or the
   current conversation. Respect `awaitingApproval`; an explicit current approval
   can satisfy it. Do not demand new hashes solely because the plugin updated.
   Do not infer approval from mode=auto. If phase is completed, report the
   historical completion and stop. Planning phases must finish planning first;
   `tasks`, `execution` and a documented legacy `ongoing` phase may continue.
2. Identify the current task from the project checkpoint/currentTaskId when
   present; otherwise reconcile the old zero-based taskIndex with the ordered
   task blocks and checkboxes. Use the first unfinished task only when those
   records agree or no cursor exists. `[x]` is historical completion; `[ ]` and
   `[-]` are unfinished. Include [VERIFY] tasks. Never count checkboxes inside
   fenced examples or comments. On disagreement, show the conflicting records
   and reconcile from Git/progress evidence before editing. Never reset to task 0.
3. Inspect the task's partial diff and previous verification. Continue only the
   missing work, preserving unrelated edits. Respect existing per-task and global
   attempt limits; if counters are malformed or their convention cannot be
   established, stop with that diagnostic. Record each new attempt using the existing
   counter convention. A session restart does not refund or reset limits. If no
   limits exist, allow at most one attempt per task per invocation; stop on a
   failed verification. Do not automatically retry an ambiguous previous launch.
4. Use the caller's native execution tools, or delegate one bounded task to a
   general-purpose agent with the task and project context. Do not use the v2
   executor/qa agents or manufacture a kernel dispatch envelope. Keep [P] tasks
   sequential. Follow the existing task's Files, Cwd and Verify when present;
   missing new v2 fields such as Traces or Timeout do not require a plan rewrite.
5. Independently run the declared Verify in its declared Cwd after the worker
   finishes. Where Verify is absent, derive a representative check from the
   task's Done/acceptance criteria and record its command and result. If no
   objective check is available, leave the task unfinished and explain what is
   missing. A worker's success message is not verification. On failure, preserve
   partial work, record the failure, and leave the task open.
6. After verification passes, follow the project's existing commit policy,
   including only its task-owned changes. Mark only that task complete and append
   the verification evidence and next task to .progress.md or its existing
   checkpoint. Update existing cursor/counter fields consistently with the
   original conductor. Preserve every other state field; use an atomic write
   only after confirming the state has not changed since it was read. Do not add
   schemaVersion=2, kernel approvals, attempts or synthetic accepted taskStates.
7. Continue sequentially within the existing authorization and budgets. Close
   only when all planned tasks/checkpoints have historical or current completion
   evidence. Preserve the state file and worktrees at completion. Report this as
   legacy completion, never as kernel acceptance.

## status

Report **Legacy mode**, phase, the reconciled current task, completed/total tasks,
existing attempt limits, partial work, blockers and the next action. Clearly
label historical completion. Do not query kernel status or invent kernel budget
or acceptance figures. Suggest `/spec-drive:implement` to continue this project.

## cancel

Pause scheduling. Confirm any worker is stopped before declaring execution
paused. Preserve its files and counters; atomically set the existing lifecycle
field `awaitingApproval: true` to suppress automatic continuation and record the
pause in progress. Explicit `/spec-drive:implement` may resume after confirming
the plan remains approved and the previous worker has stopped. `--delete` is not
implemented in compatibility mode; leave the project intact and report this.

## research, requirements, design, tasks, refactor

Follow the existing project's document chain, templates, task format and approval
gates. Read predecessor artifacts; retain approved content and completed tasks.
Generate only the requested missing or changed artifact. For refactor, show the
concrete changes before seeking approval; preserve task identities and progress.
Record the phase and pending review with the existing lifecycle fields. Do not
run kernel approve/preflight or retrofit new v2 fields. Previously granted
approval remains valid for unchanged content; changed scope needs fresh approval.

## Later adoption of the kernel

Finish the ongoing spec in legacy mode. A new spec created with 2.1 uses the
kernel automatically. Moving an ongoing spec to the kernel is a separate,
explicit task with a reviewed checkpoint; changing a version field is not a
migration. Existing corrupt or unknown-version state must be recovered from
evidence, not reset or silently treated as legacy.
