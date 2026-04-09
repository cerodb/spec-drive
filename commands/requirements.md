---
description: Generate requirements from research findings
argument-hint: ""
allowed-tools: [Read, Write, Bash, Glob, Agent]
---

# /spec-drive:requirements

Generate structured requirements from research findings by delegating to the product-manager agent.

## When Invoked

The user has completed the research phase and wants to produce requirements.md.

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
- `phase` -- must be "research" (research completed, ready for requirements)
- `mode` -- "normal" or "auto"
- `awaitingApproval` -- current approval state

If `phase` is not "research", reject with:
```
Cannot generate requirements: current phase is "{phase}".
Requirements can only be generated after the research phase completes.
```

### Step 3: Validate Phase Checklist

Read `skills/spec-workflow/references/phase-checklists.md` from the plugin root.

Validate the **research -> requirements** checklist:

1. **research.md exists**: Read `{basePath}/research.md`. If missing:
   ```
   Checklist failed: research.md does not exist in {basePath}
   Fix: Run /spec-drive:new or manually create research.md with research findings.
   ```

2. **Executive Summary section**: Search research.md for `## Executive Summary`. If missing:
   ```
   Checklist failed: research.md is missing "## Executive Summary" section.
   Fix: Add an Executive Summary section summarizing key research findings.
   ```

3. **Feasibility Assessment section**: Search research.md for `## Feasibility Assessment`. If missing:
   ```
   Checklist failed: research.md is missing "## Feasibility Assessment" section.
   Fix: Add a Feasibility Assessment section evaluating technical and resource feasibility.
   ```

4. **Open Questions section**: Search research.md for `## Open Questions`. If missing:
   ```
   Checklist failed: research.md is missing "## Open Questions" section.
   Fix: Add an Open Questions section listing unresolved items (can be empty if all resolved).
   ```

<mandatory>
If ANY checklist item fails, stop immediately. Output the specific failure message and suggested fix. Do NOT proceed to agent delegation.
</mandatory>

### Step 4: Delegate to Product-Manager Agent

All checklist items passed. Delegate to the `spec-drive:product-manager` agent via the Agent tool:

```
Agent: spec-drive:product-manager

Generate requirements for the project at basePath: {basePath}

Read {basePath}/idea.md and {basePath}/research.md, then produce {basePath}/requirements.md following the requirements template structure with user stories, acceptance criteria (AC-X.Y format), functional requirements, non-functional requirements, out of scope, and glossary sections.
```

Wait for the agent to complete and confirm that `{basePath}/requirements.md` was written.

### Step 5: Update State

After the product-manager agent completes successfully:

1. Read the current `.spec-drive-state.json`
2. Update the state:
   - Set `phase` to `"requirements"`
   - Set `awaitingApproval` to `true`
3. Write the updated state back to `{basePath}/.spec-drive-state.json`

### Step 6: Handle Mode

Check the `mode` field from the state:

- **normal mode** (`mode: "normal"`): Set `awaitingApproval: true` and output:
  ```
  Requirements generated: {basePath}/requirements.md
  Review the requirements, then run /spec-drive:design to proceed.
  ```

- **auto mode** (`mode: "auto"`): Still set `awaitingApproval: true` and stop. Auto mode does not bypass review during scope-definition phases. Output:
  ```
  Requirements generated: {basePath}/requirements.md
  Auto mode pauses at definition checkpoints.
  Review the requirements, then run /spec-drive:design to proceed.
  ```

## Error Handling

- If the product-manager agent fails or produces incomplete output, do NOT update the state. Report the error and suggest re-running.
- If research.md exists but is suspiciously short (under 100 words), warn the user but proceed (it may be a minimal research phase).

## Output

On success (normal mode):
```
Phase checklist: PASSED (research -> requirements)
Delegated to: product-manager agent
Output: {basePath}/requirements.md
Status: Awaiting approval. Review requirements, then run /spec-drive:design.
```

On success (auto mode):
```
Phase checklist: PASSED (research -> requirements)
Delegated to: product-manager agent
Output: {basePath}/requirements.md
Status: Auto mode paused at definition checkpoint. Review requirements, then run /spec-drive:design.
```
