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
- `phase` -- must be "design" for generation, or "tasks" with `awaitingApproval: true` to resume approval
- `mode` -- "normal" or "auto"
- `awaitingApproval` -- current approval state

If `phase` is `"tasks"`, `awaitingApproval` is true, and `tasks.md` exists, do not regenerate it; resume at
Step 7. For every other phase except `"design"`, reject with:
```
Cannot generate tasks: current phase is "{phase}".
Tasks can only be generated after the design phase completes.
```

### Step 3: Approve the design input

Use the execution kernel as the only approval writer. Requirements approval must already exist and match the
current `{basePath}/requirements.md`. Read the current SHA-256 of `{basePath}/design.md` and compare it with
`state.approvals.design.sha256` and its non-empty `approvalEvidence`.
First confirm both upstream files exist so missing-artifact diagnostics remain actionable.

- If the current design bytes already have matching explicit approval, capture the kernel-owned requirements
  and design approval digests as `approvedRequirementsSha` and `approvedDesignSha`.
- Otherwise ask the user to explicitly approve the current design bytes. Do not infer approval from
  `mode: "auto"`, command invocation, or generation success. On confirmation, send this request on stdin to
  `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/execution-kernel.mjs`:

```json
{
  "op": "approve",
  "specDir": "{basePath}",
  "artifact": "design",
  "expectedSha256": "<current design.md SHA-256>",
  "approvalEvidence": "<explicit user approval>"
}
```

If `approve` fails, stop with its diagnostic. Capture the returned `sha256` as `approvedDesignSha` and the
matching `state.approvals.requirements.sha256` as `approvedRequirementsSha`. Do not recompute either after
approval. Verify `design.md` frontmatter `requirements_sha` equals `approvedRequirementsSha`; otherwise stop
as stale.

### Step 4: Validate Phase Checklist

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

### Step 5: Delegate to Task-Planner Agent

All checklist items passed. Delegate to the `spec-drive:task-planner` agent via the Agent tool:

```
Agent: spec-drive:task-planner

Generate an implementation task plan for the project at basePath: {basePath}

Read the approved {basePath}/requirements.md and {basePath}/design.md, then produce {basePath}/tasks.md with POC-first phased structure, [P] markers for genuinely independent adjacent tasks, canonical V# [VERIFY] checkpoints every 2-3 implementation tasks and at phase boundaries, and each task in Do/Files/Traces/model/Cwd/Done when/Verify/Timeout/Commit format. Use positive integer seconds for Timeout. Set tasks.md frontmatter requirements_sha exactly to {approvedRequirementsSha} and design_sha exactly to {approvedDesignSha}.
```

Wait for the agent to complete and confirm that `{basePath}/tasks.md` was written.

Confirm that both frontmatter hashes equal the captured approved hashes and validate the generated task
grammar, checkpoints, Timeout values, and AC/NFR coverage. Do not approve the generated `tasks.md` yet.

### Step 6: Update State

After the task-planner agent completes successfully:

1. Read the current `.spec-drive-state.json`
2. Update the state:
   - Set `phase` to `"tasks"`
   - Set `awaitingApproval` to `true`
3. Write the updated state back to `{basePath}/.spec-drive-state.json`

### Step 7: Explicit tasks approval and kernel preflight

Check the `mode` field from the state:

When resuming an existing generated plan, load `approvedRequirementsSha` and `approvedDesignSha` from the
matching approval records and, if tasks is already explicitly approved, load `approvedTasksSha` from its
matching record. Any absent or stale record follows the explicit approval path below.

- **normal mode** (`mode: "normal"`): keep `awaitingApproval: true`, show the generated path, and ask the
  user to explicitly approve the current task plan. Only after confirmation, send `op: "approve"`,
  `artifact: "tasks"`, the current tasks SHA-256 as `expectedSha256`, and the user's statement as
  `approvalEvidence` to the execution kernel. Capture its returned `sha256` as `approvedTasksSha`.

- **auto mode** (`mode: "auto"`): keep `awaitingApproval: true` and stop for the same explicit task-plan
  approval. Auto mode never approves generated artifacts and never begins execution from unapproved output.

After explicit tasks approval, invoke the kernel with:

```json
{
  "op": "preflight",
  "specDir": "{basePath}",
  "repoRoot": "<resolved repository root>"
}
```

Run the complete `tasks -> execution` checklist, including its approval item, immediately before this call.
Require `ok: true` and returned hashes matching `approvedRequirementsSha`, `approvedDesignSha`, and
`approvedTasksSha`. Only then set `awaitingApproval: false` and hand off to `/spec-drive:implement`. A missing
approval, stale requirements/design/tasks hash, incomplete coverage, or task grammar error stops before any
dispatch. On a later invocation with `phase: "tasks"` and `awaitingApproval: true`, resume at this explicit
tasks approval step instead of regenerating the plan.

## Error Handling

- If the task-planner agent fails or produces incomplete output, do NOT update the state. Report the error and suggest re-running.
- If design.md is very large (many components), warn that the task plan may be lengthy but proceed.

## Output

On success (normal mode):
```
Phase checklist: PASSED (design -> tasks)
Delegated to: task-planner agent
Output: {basePath}/tasks.md
Status: Kernel preflight passed for the explicitly approved task plan. Ready for /spec-drive:implement.
```

On success (auto mode):
```
Phase checklist: PASSED (design -> tasks)
Delegated to: task-planner agent
Output: {basePath}/tasks.md
Status: Auto mode paused for explicit task-plan approval; after approval and preflight, continuing to execution.
```
