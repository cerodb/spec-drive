---
description: Start autonomous task execution loop
argument-hint: ""
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent]
---

# /spec-drive:implement

The coordinator command. Orchestrates autonomous task execution by delegating each task to the appropriate agent. Never implements tasks directly.

<mandatory>
This command follows the delegation principle: it NEVER implements tasks directly. It ALWAYS delegates via the Task tool (Agent invocation). The coordinator reads state, determines the next action, delegates, and updates state. That is all.
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

### Step 6: Detect Task Type and Dispatch

Inspect the task description to determine the type:

#### Regular Task (no marker)

Delegate to the `spec-drive:executor` agent via Task tool:

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

Delegate to the `spec-drive:qa-engineer` agent via Task tool:

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
5. After ALL parallel tasks complete, merge isolated progress files into `.progress.md`
6. Clear `parallelGroup` from state
7. Advance `taskIndex` past the entire batch

### Step 7: Handle Agent Result

After the delegated agent completes:

#### On TASK_COMPLETE (or VERIFICATION_PASS)

1. Advance `taskIndex` by 1 (or by batch size for parallel)
2. Reset `taskIteration` to 1
3. Increment `globalIteration` by 1
4. Record success in `taskResults`:
   ```json
   { "<taskIndex>": { "status": "success" } }
   ```
5. Write updated state to `.spec-drive-state.json`
6. Loop back to Step 5 for the next task

#### On Failure (or VERIFICATION_FAIL)

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
