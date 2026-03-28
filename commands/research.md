---
description: Run or re-run research phase for current spec
argument-hint: ""
allowed-tools: [Read, Write, Bash, Glob, Agent]
---

Re-run the research phase for the active project. Validates prerequisites, delegates to the researcher agent, and updates state.

## Find Active Project

Locate the project's spec directory by checking two locations in order:

1. **Current working directory**: Check if `./spec/.spec-drive-state.json` exists (user is in project root) or `./.spec-drive-state.json` exists (user is in spec/ directory)
2. **Project root scan**: Read projectRoot from `~/.spec-drive-config.json` (default: `~/spec-drive-projects/`), scan subdirectories for any containing `spec/.spec-drive-state.json`

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

## Delegate to Researcher

<mandatory>
Do NOT implement research directly. Delegate to the researcher agent via Task tool.

Invoke the researcher agent:
```
Task tool:
  subagent_type: spec-drive:researcher
  description: "Run research phase for project <name>"
  prompt: |
    basePath: <basePath>
    projectName: <name>

    Read idea.md at the basePath and produce research.md following your research protocol.
```

Wait for the researcher agent to complete.
</mandatory>

## Update State After Completion

Update `.spec-drive-state.json`:

```bash
jq '.phase = "research"' "$basePath/.spec-drive-state.json" > /tmp/sd-state.json && mv /tmp/sd-state.json "$basePath/.spec-drive-state.json"
```

Check the mode:

**Normal mode**:
1. Set `awaitingApproval = true`:
```bash
jq '.awaitingApproval = true' "$basePath/.spec-drive-state.json" > /tmp/sd-state.json && mv /tmp/sd-state.json "$basePath/.spec-drive-state.json"
```
2. Tell the user:
```
Research complete. Review research.md at $basePath/research.md

When ready, run: /spec-drive:requirements
```

**Auto mode**:
1. Do NOT set awaitingApproval
2. Immediately invoke the next phase:
```
Invoke: /spec-drive:requirements
```
