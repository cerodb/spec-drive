---
description: Run or re-run research phase for current spec
argument-hint: ""
allowed-tools: [Read, Write, Bash, Glob, Agent]
---

Re-run the research phase for the active project. Validates prerequisites, delegates to the researcher agent, and updates state.

## Find Active Project

Locate the project's spec directory by checking two locations in order:

1. **Current working directory**: Check if `./spec/.spec-drive-state.json` exists (user is in project root) or `./.spec-drive-state.json` exists (user is in spec/ directory)
2. **Project root scan**: Resolve config using workspace -> XDG order, then read `projectRoot` (default: `~/spec-drive-projects/`) and scan subdirectories for any containing `spec/.spec-drive-state.json`

If multiple projects found during scan, list them and ask user to cd into the desired project.

If no project found:
```
No active project found. Run /spec-drive:new <name> to create one.
```
Stop.

Set `basePath` to the resolved spec directory path.

## Validate Prerequisites

<mandatory>
idea.md MUST exist before research can run.

Check:
```bash
test -f "$basePath/idea.md"
```

If missing:
```
Error: idea.md not found at $basePath/idea.md
Run /spec-drive:new <name> to create a project with an idea first.
```
Stop.
</mandatory>

## Read Current State

Read `.spec-drive-state.json` from basePath:
```bash
jq '.' "$basePath/.spec-drive-state.json"
```

Extract `name`, `mode`, and current `phase`.

Note: If research.md already exists, it will be overwritten. This is intentional — the command explicitly supports re-running research.

## Coordinator Preflight

Before delegating to the researcher, run a lightweight coordinator preflight to decide whether this research pass should run as a normal single invocation or as a fan-out with enforcement.

Delegate the preflight to the `spec-drive:coordinator` agent via the Agent tool:

```
Agent: spec-drive:coordinator

Run a coordinator preflight for the project at basePath: <basePath>
phase: research

Read idea.md and .spec-drive-state.json. Apply the fan-out signal scoring and
return the structured COORDINATOR_OUTCOME block. If the outcome is
coordinate_research, include the researcher enforcement brief inside a fenced
markdown block. If the outcome is clarify_first, run the clarification subphase
and record results in .progress.md per the D2 block format before returning.
```

Parse the coordinator output. Three outcomes matter for this command:

1. **`continue_sequential`** — the researcher runs with its default protocol. Proceed to the Delegate to Researcher step below with no brief additions. State is already updated with `coordinator.active=false, mode=sequential`.

2. **`coordinate_research`** — the researcher runs with the enforcement brief the coordinator returned. Pass that brief verbatim as additional prompt content in the Delegate to Researcher step. State is already updated with `coordinator.active=true, mode=research`.

3. **`clarify_first`** or **`block_and_escalate`** — the coordinator already wrote the clarification block to `.progress.md`. Stop and tell the user:
   ```
   Coordinator blocked research phase before researcher could run.
   Reason: <reason from coordinator output>
   Clarification block written to: <basePath>/.progress.md
   Resolve the remaining items, then re-run: /spec-drive:research
   ```
   Do NOT delegate to the researcher in these cases.

## Delegate to Researcher

<mandatory>
Do NOT implement research directly. Delegate to the researcher agent via Task tool.

Build the researcher prompt:

- Always include: basePath, projectName, and the standard instruction to read idea.md and produce research.md following the research protocol.
- If the coordinator returned `coordinate_research` with an enforcement brief, append that brief verbatim as additional instructions so the researcher knows it must hit the three evidence sub-section bars.

Invoke the researcher agent:
```
Task tool:
  subagent_type: spec-drive:researcher
  description: "Run research phase for project <name>"
  prompt: |
    basePath: <basePath>
    projectName: <name>

    Read idea.md at the basePath and produce research.md following your research protocol.

    <if coordinator fan-out enforcement brief exists, paste it here verbatim>
```

Wait for the researcher agent to complete.
</mandatory>

## Post-Validate Fan-out (only if coordinator requested it)

If the coordinator returned `coordinate_research`, after the researcher completes, delegate a post-validation call back to the `spec-drive:coordinator` agent:

```
Agent: spec-drive:coordinator

Post-validate the fresh research.md at basePath: <basePath>
phase: research
postValidate: true

Check the three evidence sub-sections per D3 enforcement contract and return a
verdict: pass, retry (with specific feedback), or degrade.
```

Outcomes:

- **`pass`** — continue to Update State After Completion below
- **`retry`** — re-invoke the researcher one more time with the coordinator's feedback appended to the prompt, then re-run post-validation. If the second attempt also fails, treat as `degrade`.
- **`degrade`** — the coordinator will set `coordinator.degraded=true` in state and record the gap in `.progress.md`. Continue to Update State After Completion. Do not retry a third time. Inform the user that fan-out enforcement was not met and the research.md may need manual review.

## Update State After Completion

Update `.spec-drive-state.json`:

```bash
state_file="$basePath/.spec-drive-state.json"
tmpfile=$(mktemp "${state_file}.XXXXXX")
jq '.phase = "research"' "$state_file" > "$tmpfile" && mv "$tmpfile" "$state_file"
```

Check the mode:

**Normal mode**:
1. Set `awaitingApproval = true`:
```bash
state_file="$basePath/.spec-drive-state.json"
tmpfile=$(mktemp "${state_file}.XXXXXX")
jq '.awaitingApproval = true' "$state_file" > "$tmpfile" && mv "$tmpfile" "$state_file"
```
2. Tell the user:
```
Research complete. Review research.md at $basePath/research.md

When ready, run: /spec-drive:requirements
```

**Auto mode**:
1. Set `awaitingApproval = true`
2. Stop after research exactly like normal mode
3. Tell the user:
```
Research complete. Review research.md at $basePath/research.md

Auto mode does not bypass definition-phase review gates.
When ready, run: /spec-drive:requirements
```
