---
description: Generate implementation task plan from design
argument-hint: ""
allowed-tools: [Read, Write, Bash, Glob, Agent]
---

# /spec-drive:tasks

Generate a phased implementation task plan from the technical design by delegating to the task-planner agent.

## When Invoked

The user has completed the design phase and wants to produce tasks.md.

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

Read `{basePath}/.spec-drive-state.json` using the Read tool. Parse the JSON to extract:
- `phase` -- must be "design" (design completed, ready for task planning)
- `mode` -- "normal" or "auto"
- `awaitingApproval` -- current approval state

If `phase` is not "design", reject with:
```
Cannot generate tasks: current phase is "{phase}".
Tasks can only be generated after the design phase completes.
```

### Step 3: Validate Phase Checklist

Read `skills/spec-workflow/references/phase-checklists.md` from the plugin root.

Validate the **design -> tasks** checklist:

1. **design.md exists**: Read `{basePath}/design.md`. If missing:
   ```
   Checklist failed: design.md does not exist in {basePath}
   Fix: Run /spec-drive:design to generate the technical design first.
   ```

2. **Components section**: Search design.md for `## Components` or `## Component`. If missing:
   ```
   Checklist failed: design.md is missing "## Components" section.
   Fix: Add a Components section defining system building blocks with responsibilities and dependencies.
   ```

3. **AC references**: Search design.md for the `AC-` pattern (acceptance criteria traceability). If no matches:
   ```
   Checklist failed: design.md does not reference any acceptance criteria (AC-* pattern).
   Fix: Add AC-X.Y traceability to components and technical decisions per the architect agent requirements.
   ```

4. **Technical Decisions section**: Search design.md for `## Technical Decisions`. If missing:
   ```
   Checklist failed: design.md is missing "## Technical Decisions" section.
   Fix: Add a Technical Decisions section documenting choices with options, rationale, and AC references.
   ```

<mandatory>
If ANY checklist item fails, stop immediately. Output the specific failure message and suggested fix. Do NOT proceed to agent delegation.
</mandatory>

### Step 4: Delegate to Task-Planner Agent

All checklist items passed. Delegate to the `spec-drive:task-planner` agent via the Agent tool:

```
Agent: spec-drive:task-planner

Generate an implementation task plan for the project at basePath: {basePath}

Read {basePath}/requirements.md and {basePath}/design.md, then produce {basePath}/tasks.md with POC-first phased structure (Phase 1-5), [P] markers for parallel tasks, [VERIFY] checkpoints at phase boundaries, and each task in Do/Files/Done when/Verify/Commit format.
```

Wait for the agent to complete and confirm that `{basePath}/tasks.md` was written.

### Step 5: Update State

After the task-planner agent completes successfully:

1. Read the current `.spec-drive-state.json`
2. Update the state:
   - Set `phase` to `"tasks"`
   - Set `awaitingApproval` to `true`
3. Write the updated state back to `{basePath}/.spec-drive-state.json`

### Step 6: Handle Mode

Check the `mode` field from the state:

- **normal mode** (`mode: "normal"`): Set `awaitingApproval: true` and output:
  ```
  Tasks generated: {basePath}/tasks.md
  Review the task plan, then run /spec-drive:implement to start execution.
  ```

- **auto mode** (`mode: "auto"`): Set `awaitingApproval: false` and immediately invoke `/spec-drive:implement` to begin autonomous task execution. This is the first point where auto mode may continue without an explicit human checkpoint.

## Error Handling

- If the task-planner agent fails or produces incomplete output, do NOT update the state. Report the error and suggest re-running.
- If design.md is very large (many components), warn that the task plan may be lengthy but proceed.

## Output

On success (normal mode):
```
Phase checklist: PASSED (design -> tasks)
Delegated to: task-planner agent
Output: {basePath}/tasks.md
Status: Awaiting approval. Review task plan, then run /spec-drive:implement.
```

On success (auto mode):
```
Phase checklist: PASSED (design -> tasks)
Delegated to: task-planner agent
Output: {basePath}/tasks.md
Status: Auto mode — continuing to execution phase...
```
