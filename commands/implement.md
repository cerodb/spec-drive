---
description: Start autonomous task execution loop
argument-hint: ""
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent]
---

# /spec-drive:implement

The coordinator command. Orchestrates autonomous task execution by delegating each task to the appropriate agent. Never implements tasks directly.

<mandatory>
This command follows the delegation principle: it NEVER implements task code directly. It delegates implementation to an executor, then owns all trusted git/state transitions itself. The coordinator reads state, preflights task files, delegates implementation, re-runs Verify, commits implementation files, commits Spec-Drive tracking, and updates state.
</mandatory>

## When Invoked

The user has a tasks.md ready for execution, or execution is resuming after a session restart.

## Execution Flow

### Step 1: Find Active Project

Locate the spec directory:

1. Check if the current working directory contains `.spec-drive-state.json`
2. If not, scan for a `spec/` subdirectory containing `.spec-drive-state.json`
3. If not found, check the parent directory for a project root with `spec/.spec-drive-state.json`

If no active project is found, output an error:
```
No active spec-drive project found.
Run /spec-drive:new <name> to create one, or cd into the project directory.
```

Set `basePath` to the directory containing `.spec-drive-state.json`.

### Step 2: Read State

Read `{basePath}/.spec-drive-state.json`. Parse:
- `phase` -- if not "tasks" or "execution", reject
- `taskIndex` -- current task position (0-based)
- `totalTasks` -- total task count
- `taskIteration` -- retry count for current task
- `maxTaskIterations` -- max retries per task (default: 5)
- `globalIteration` -- total loop iterations
- `maxGlobalIterations` -- safety cap (default: 100)

If `phase` is not "tasks" and not "execution", reject with:
```
Cannot start execution: current phase is "{phase}".
Execution requires phase "tasks" or "execution".
Run /spec-drive:tasks first to generate the task plan.
```

### Step 3: Validate Phase Checklist (first run only)

If `phase` is "tasks" (first invocation), validate the **tasks -> execution** checklist by reading `skills/spec-workflow/references/phase-checklists.md`:

1. **tasks.md exists**: Read `{basePath}/tasks.md`. If missing:
   ```
   Checklist failed: tasks.md does not exist in {basePath}
   Fix: Run /spec-drive:tasks to generate the task plan.
   ```

2. **Has unchecked tasks**: Search for `- [ ]` pattern. If no matches:
   ```
   Checklist failed: tasks.md has no unchecked tasks (all already completed or empty).
   ```

3. **Has [VERIFY] checkpoint**: Search for `[VERIFY]`. If no matches:
   ```
   Checklist failed: tasks.md has no [VERIFY] checkpoint tasks.
   Fix: Add quality checkpoint tasks at phase boundaries.
   ```

4. **Tasks have Verify fields**: Search for `Verify:` or `**Verify**:`. If no matches:
   ```
   Checklist failed: Task entries are missing Verify fields.
   Fix: Each task must include a Verify command that exits 0 on success.
   ```

<mandatory>
If ANY checklist item fails, stop immediately. Do NOT proceed to execution.
</mandatory>

### Step 4: Initialize Execution State

If `phase` is "tasks" (first run):

1. Count total tasks: count all lines matching `^- \[ \]` in tasks.md
2. If count is 0, stop with error: "No unchecked tasks found in tasks.md. Nothing to execute."
3. Update state:
   - `phase` = `"execution"`
   - `taskIndex` = `0`
   - `totalTasks` = counted value
   - `taskIteration` = `1`
   - `globalIteration` = `1`
   - `awaitingApproval` = `false`
4. Write updated state to `.spec-drive-state.json`

If `phase` is already "execution" (resuming):
1. Recount unchecked tasks from tasks.md
2. If the count differs from `totalTasks` in state, update `totalTasks` and warn:
   "tasks.md was modified since last run. totalTasks updated: {old} → {new}"
3. Use updated state values.

### Step 5: Parse Current Task

Read `{basePath}/tasks.md`. Extract the task block at position `taskIndex`:

1. Find all unchecked task lines matching `- [ ] X.Y`
2. Index to `taskIndex` (0-based)
3. Extract the full task block: the task line plus all indented content below it until the next task line or end of file
4. Parse the block to extract: Do, Files, Done when, Verify, Commit fields

If `taskIndex >= totalTasks`, go to Step 9 (all tasks complete).

### Step 6: Coordinator Pre-flight and Dispatch

The coordinator owns git and Spec-Drive tracking state. Executors are pure implementers.

Before dispatching a Regular Task or `[P]` task:

1. Parse the task block's `Files` field into explicit repo-relative paths.
2. Check whether any listed file already has uncommitted changes (`git status --porcelain -- <files>`).
3. If any listed file is dirty before dispatch, stop before invoking an executor:
   ```
   TASK_BLOCKED: dirty task files before dispatch: <paths>
   ```
4. Do not stash, reset, clean, or overwrite dirty user work automatically.

This dirty-file check moved here from the executors so every dispatch mechanism has the same trusted preflight.

#### Detect Task Type and Dispatch

Inspect the task description to determine the type.

#### Resolve Model Tier (pre-dispatch, Regular Tasks only)

Before delegating a Regular Task, resolve its `model:` tier to a concrete dispatch mechanism:

1. Parse the `model:` field from the task block (e.g. `model: standard`, placed after `Traces:` and
   before `Cwd:`). If the field is absent, treat the tier as empty -- the resolver's inherit fallback
   handles this case.
2. Run the resolver via the Bash tool as `"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/resolve-model.sh" <tier>`.
   `CLAUDE_PLUGIN_ROOT` points at this plugin's root. Do NOT use a bare relative path such as
   `hooks/scripts/resolve-model.sh`: the coordinator's working directory is the user's project, not the
   plugin, so a relative path is not found and every task would silently fall back to `inherit`. If
   `CLAUDE_PLUGIN_ROOT` is not set in your runtime, resolve the plugin root from the path of this
   command file (same fallback contract as `agents/coordinator.md`). `<tier>` may be empty for tasks
   with no `model:` field. Capture stdout and parse the three `key=value` lines it always emits:
   - `mechanism=` -- one of `agent`, `subprocess`, `inherit`
   - `model=` -- concrete model id (set only when `mechanism=agent`)
   - `cmd=` -- command template with `{promptfile}` placeholder (set only when
     `mechanism=subprocess`; shipped `{MODEL}`/`{CMD}` profile stubs must be overridden before use)
3. Branch the dispatch on `mechanism`:
   - **`mechanism=agent`** -- invoke `spec-drive:executor` via the Agent tool WITH the resolved
     `model` added as a parameter: `Agent(subagent_type: "spec-drive:executor", model: <resolved
     model>, prompt: <executor contract>)`. Same call as the inherit case below, one field added.
   - **`mechanism=subprocess`** -- read `agents/executor-subprocess.md`, write the full CLI-neutral
     subprocess implementer prompt to a secure temporary file, and run the profile's `cmd` template via
     the Bash tool after substituting `{promptfile}` with that file path. Never substitute prompt
     content into the shell command line. Capture the subprocess's stdout and parse the trailing
     `TASK_COMPLETE` / `TASK_BLOCKED` line exactly as Step 7 parses agent results today.
   - **`mechanism=inherit`** -- current behavior: invoke `spec-drive:executor` via the Agent tool with
     no `model` parameter (the agent runs on whatever model the coordinator itself is running on).
     This is the fallback for tasks with no `model:` field and unknown/unresolvable tiers.
     Missing resolver tooling may still fall back to inherit, but explicit resolver configuration errors
     such as `error=unresolved_placeholder` must stop dispatch with the resolver stderr so the user can
     fix `profiles.local.json` instead of running a literal placeholder command.

#### Regular Task (no marker)

Delegate to the `spec-drive:executor` agent via Task tool, dispatched per the resolved mechanism from
the resolution step above:

- **`mechanism=agent`**:
  ```
  Agent tool: spec-drive:executor
  model: <resolved model>

  Execute this task:

  basePath: {basePath}

  Task Block:
  {full task block text}

  Progress:
  {contents of basePath/.progress.md}
  ```

- **`mechanism=subprocess`**:
  ```
  promptFile="$(mktemp "${TMPDIR:-/tmp}/spec-drive-subprocess-prompt.XXXXXX")"
  chmod 600 "$promptFile"
  cat >"$promptFile" <<'SPEC_DRIVE_PROMPT'
  <CLI-neutral subprocess implementer contract (agents/executor-subprocess.md instructions)>

  Execute this task:

  basePath: {basePath}

  Task Block:
  {full task block text}

  Progress:
  {contents of basePath/.progress.md}
  SPEC_DRIVE_PROMPT
  Bash: <profile cmd template, {promptfile} substituted with "$promptFile">
  rm -f "$promptFile"
  ```
  Parse the subprocess's stdout for a trailing `TASK_COMPLETE` or `TASK_BLOCKED` line, same as Step 7.
  Do not put the prompt content directly on the shell command line. Do not send `agents/executor.md` verbatim to subprocess runtimes; that contract is optimized for
  Claude Code's Agent-tool execution surface and may mention tool names or delegation patterns that
  other CLIs do not implement.

- **`mechanism=inherit`** (no `model:` field, unknown tier, or resolver failure -- current/default
  behavior):
  ```
  Task tool: spec-drive:executor

  Execute this task:

  basePath: {basePath}

  Task Block:
  {full task block text}

  Progress:
  {contents of basePath/.progress.md}
  ```

#### [VERIFY] Task

`[VERIFY]` tasks are NOT routed through `resolve-model.sh` (MVP scope) -- they always run on the
session model, regardless of any `model:` field on the task block. Delegate to the
`spec-drive:qa-engineer` agent via Task tool:

```
Task tool: spec-drive:qa-engineer

Run this verification task:

basePath: {basePath}

Task Block:
{full task block text}

Progress:
{contents of basePath/.progress.md}
```

#### [P] Parallel Batch

When the current task has a `[P]` marker:

1. Collect all consecutive `[P]` tasks starting from the current taskIndex
2. Determine batch size (respect `maxConcurrency` from config, default: 2)
3. For each task in the batch, delegate to `spec-drive:executor` via Task tool with an isolated `progressFile`:
   ```
   Agent: spec-drive:executor

   Execute this task:

   basePath: {basePath}
   progressFile: .progress-task-{taskIndex}.md

   Task Block:
   {task block for this specific task}

   Progress:
   {contents of basePath/.progress.md}
   ```
4. Update state with `parallelGroup`:
   ```json
   {
     "startIndex": <first task index>,
     "endIndex": <last task index>,
     "taskIndices": [<all indices>],
     "isParallel": true
   }
   ```
5. After each parallel executor returns `TASK_COMPLETE`, the coordinator serializes trusted post-processing under the existing `.execution-state.lock`:
   - re-run that task's Verify command in the trusted coordinator context
   - `git add` only that task's declared Files
   - `git commit -m "<exact Commit message>"`
   - update that task's checkbox / `model_used:` field and merge its isolated progress notes
6. After ALL parallel tasks complete and their implementation commits succeed, commit the merged tracking update separately
7. Clear `parallelGroup` from state
8. Advance `taskIndex` past the entire batch

### Step 7: Handle Executor Result and Own Git

After the delegated executor completes, parse the final decisive line from its response/stdout:

- `TASK_COMPLETE`
- `TASK_BLOCKED: <reason>`
- `VERIFICATION_PASS` / `VERIFICATION_FAIL` for QA tasks

#### On TASK_COMPLETE (or VERIFICATION_PASS)

The coordinator must perform the trusted post-processing. Do not trust the executor's success signal alone.

1. Re-run the task's exact Verify command in the trusted coordinator context. This is the authoritative check before any commit.
2. If Verify fails, treat the task as failed: append the failure to `.progress.md`, increment iteration counters, and retry/stop per limits below. Do not commit.
3. Stage ONLY the task's declared `Files` paths:
   ```bash
   git add <files from Files field>
   ```
4. Commit implementation changes with the exact message from the task's `Commit` line:
   ```bash
   git commit -m "<exact Commit message>"
   ```
   If the task explicitly says "only if fixes needed" and no files changed, skip only this implementation commit and continue to tracking.
5. Mark the task as `[x]` in `{basePath}/tasks.md`.
6. Append `model_used: <tier-or-mechanism>` to the completed task's block, where the value reflects the tier/mechanism that actually executed the implementation.
7. Update the progress file (`progressFile` if provided, else `{basePath}/.progress.md`):
   - add task to Completed Tasks
   - set Current Task to "Awaiting next task"
   - append concrete learnings from the executor output when useful
8. Commit tracking state separately:
   ```bash
   git add {basePath}/tasks.md {basePath}/<progressFile or .progress.md>
   git commit -m "chore(spec-drive): update progress for task <task-id>"
   ```
9. Advance `taskIndex` by 1 (or by batch size for parallel)
10. Reset `taskIteration` to 1
11. Increment `globalIteration` by 1
12. Record success in `taskResults`:
   ```json
   { "<taskIndex>": { "status": "success" } }
   ```
13. Write updated state to `.spec-drive-state.json`
14. Loop back to Step 5 for the next task

#### On TASK_BLOCKED / Failure (or VERIFICATION_FAIL)

1. Increment `taskIteration` by 1
2. Increment `globalIteration` by 1
3. Record failure in `taskResults`:
   ```json
   { "<taskIndex>": { "status": "failed", "error": "<failure details>" } }
   ```
4. Append failure details to `{basePath}/.progress.md` Learnings section

**Check iteration limits:**

- If `taskIteration > maxTaskIterations`:
  ```
  Task {taskIndex} failed after {maxTaskIterations} attempts.
  Last error: {error details}
  Manual intervention required. Fix the issue and re-run /spec-drive:implement.
  ```
  STOP execution.

- If `globalIteration > maxGlobalIterations`:
  ```
  Global iteration limit ({maxGlobalIterations}) exceeded.
  Current task: {taskIndex}/{totalTasks}
  This is a safety cap to prevent infinite token burn.
  Review .progress.md for failure patterns and re-run /spec-drive:implement.
  ```
  STOP execution.

- Otherwise: write updated state and retry by looping back to Step 5

### Step 8: Continue Loop

After processing the current task result, check if there are more tasks:

- If `taskIndex < totalTasks`: loop back to Step 5
- If `taskIndex >= totalTasks`: proceed to Step 9

### Step 9: All Tasks Complete

When `taskIndex >= totalTasks`:

1. Output:
   ```
   ALL_TASKS_COMPLETE

   Project: {name}
   Tasks completed: {totalTasks}/{totalTasks}
   Global iterations used: {globalIteration}
   ```

2. Archive state (do NOT delete):
   - Set `phase` to `"completed"` in `.spec-drive-state.json`
   - Remove any `.progress-task-*.md` temp files
   - Remove `.execution-state.lock` directory if present: `rmdir {basePath}/.execution-state.lock 2>/dev/null || true`

3. Output final summary with any learnings from `.progress.md`

## State Persistence

The coordinator writes state after every significant event (task completion, failure, retry). This ensures the stop-watcher hook can resume execution after a session restart by re-invoking `/spec-drive:implement`.

## Constraints

<mandatory>
- NEVER read project source files (only tasks.md, .progress.md, state file)
- NEVER run git commands (add, commit, push) -- that is the executor's job
- NEVER write application code -- that is the executor's job
- NEVER run verification commands -- that is the executor's or qa-engineer's job
- NEVER make implementation decisions -- delegate and let the agent decide
- ONLY orchestrate: read state, parse task, delegate, update state
</mandatory>

## Error Handling

- If Task tool invocation fails (agent not found, tool error): log error, increment taskIteration, retry
- If state file becomes corrupted: attempt to reconstruct from tasks.md checkmarks and .progress.md
- If tasks.md is deleted during execution: stop with error, suggest re-running /spec-drive:tasks
