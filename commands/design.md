---
description: Generate technical design from requirements
argument-hint: ""
allowed-tools: [Read, Write, Bash, Glob, Agent]
---

# /spec-drive:design

Generate a technical design document from validated requirements by delegating to the architect agent.

## When Invoked

The user has completed the requirements phase and wants to produce design.md.

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
- `phase` -- must be "requirements" (requirements completed, ready for design)
- `mode` -- "normal" or "auto"
- `awaitingApproval` -- current approval state

If `phase` is not "requirements", reject with:
```
Cannot generate design: current phase is "{phase}".
Design can only be generated after the requirements phase completes.
```

### Step 3: Validate Phase Checklist

Read `skills/spec-workflow/references/phase-checklists.md` from the plugin root.

Validate the **requirements -> design** checklist:

1. **requirements.md exists**: Read `{basePath}/requirements.md`. If missing:
   ```
   Checklist failed: requirements.md does not exist in {basePath}
   Fix: Run /spec-drive:requirements to generate requirements first.
   ```

2. **User stories with acceptance criteria**: Search requirements.md for the `AC-` pattern (indicating acceptance criteria in AC-X.Y format). If no matches:
   ```
   Checklist failed: requirements.md has no user stories with acceptance criteria (AC-X.Y format).
   Fix: Add acceptance criteria to each user story using AC-X.Y format.
   ```

3. **Functional Requirements table with priority**: Search requirements.md for `## Functional Requirements` and a table containing `Priority` or `High` or `Medium` or `Low`. If missing:
   ```
   Checklist failed: requirements.md is missing a Functional Requirements table with priority column.
   Fix: Add a Functional Requirements table with ID, Requirement, Priority, and Verification columns.
   ```

4. **Out of Scope section**: Search requirements.md for `## Out of Scope`. If missing:
   ```
   Checklist failed: requirements.md is missing "## Out of Scope" section.
   Fix: Add an Out of Scope section listing excluded features and capabilities.
   ```

<mandatory>
If ANY checklist item fails, stop immediately. Output the specific failure message and suggested fix. Do NOT proceed to agent delegation.
</mandatory>

### Step 4: Delegate to Architect Agent

All checklist items passed. Delegate to the `spec-drive:architect` agent via the Agent tool:

```
Agent: spec-drive:architect

Generate technical design for the project at basePath: {basePath}

Read {basePath}/idea.md, {basePath}/research.md, and {basePath}/requirements.md, then produce {basePath}/design.md with architecture overview (including Mermaid diagram), components (with AC traceability), data flow, technical decisions (with rationale referencing AC-X.Y/NFR-N), technical risks, and error handling sections.
```

Wait for the agent to complete and confirm that `{basePath}/design.md` was written.

### Step 5: Update State

After the architect agent completes successfully:

1. Read the current `.spec-drive-state.json`
2. Update the state:
   - Set `phase` to `"design"`
   - Set `awaitingApproval` to `true`
3. Write the updated state back to `{basePath}/.spec-drive-state.json`

### Step 6: Handle Mode

Check the `mode` field from the state:

- **normal mode** (`mode: "normal"`): Set `awaitingApproval: true` and output:
  ```
  Design generated: {basePath}/design.md
  Review the design, then run /spec-drive:tasks to proceed.
  ```

- **auto mode** (`mode: "auto"`): Still set `awaitingApproval: true` and stop. Auto mode does not bypass review during scope-definition phases. Output:
  ```
  Design generated: {basePath}/design.md
  Auto mode pauses at definition checkpoints.
  Review the design, then run /spec-drive:tasks to proceed.
  ```

## Error Handling

- If the architect agent fails or produces incomplete output, do NOT update the state. Report the error and suggest re-running.
- If requirements.md references external dependencies that may not be available, warn but proceed (architect will document these as risks).

## Output

On success (normal mode):
```
Phase checklist: PASSED (requirements -> design)
Delegated to: architect agent
Output: {basePath}/design.md
Status: Awaiting approval. Review design, then run /spec-drive:tasks.
```

On success (auto mode):
```
Phase checklist: PASSED (requirements -> design)
Delegated to: architect agent
Output: {basePath}/design.md
Status: Auto mode paused at definition checkpoint. Review design, then run /spec-drive:tasks.
```
