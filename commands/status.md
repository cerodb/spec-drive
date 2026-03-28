---
description: Show current spec status and progress
argument-hint: ""
allowed-tools: [Read, Bash, Glob]
---

# /spec-drive:status

Show the current state of a spec-drive project.

## Steps

### 1. Find active project

Look for `.spec-drive-state.json` in:
1. Current working directory
2. `./spec/` subdirectory of cwd
3. Parent directory of cwd (if cwd is `spec/`)

If not found, scan `~/spec-drive-projects/` for any directory containing `.spec-drive-state.json`.

If no active project is found:
```
No active spec-drive project found.

To start a new project: /spec-drive:new
To resume from a spec directory: cd into the project and run /spec-drive:status again
```
Stop here.

### 2. Read state

Read `.spec-drive-state.json` and extract all fields:
- `name` — project name
- `phase` — current phase (idea, research, requirements, design, tasks, execution)
- `mode` — normal or auto
- `taskIndex` — current task (0-based)
- `totalTasks` — total tasks count
- `taskIteration` — retry count for current task
- `globalIteration` — total loop iterations
- `awaitingApproval` — whether waiting for user approval

### 3. Display status

Output in this format:

```
=== Spec-Drive Status ===

Project:    {name}
Phase:      {phase}
Mode:       {mode}
Tasks:      {taskIndex}/{totalTasks} completed
Iteration:  {globalIteration} (task retry: {taskIteration})
```

### 4. Handle awaitingApproval

If `awaitingApproval` is `true`, append:

```
>> Awaiting approval: {phase} phase completed.
   Next: /spec-drive:{next-phase-command} to continue
```

Map the completed phase to the next command:
- research → `/spec-drive:requirements`
- requirements → `/spec-drive:design`
- design → `/spec-drive:tasks`
- tasks → `/spec-drive:implement`

### 5. Handle active execution

If `phase` is `execution` and `awaitingApproval` is `false`, append:

```
>> Executing task {taskIndex + 1} of {totalTasks} (retry {taskIteration}/{maxTaskIterations})
```

### 6. Show recent learnings

Read `.progress.md` from the project's spec directory (`basePath`). Extract the last 3 entries from the `## Learnings` section.

If learnings exist, append:

```
Recent learnings:
- {learning 1}
- {learning 2}
- {learning 3}
```

### 7. Show blockers

Read the `## Blockers` section from `.progress.md`. If any blockers are listed (other than "None"), append:

```
!! Blockers:
- {blocker 1}
- {blocker 2}
```
