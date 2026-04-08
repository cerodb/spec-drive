---
description: Create a new spec-driven project with idea.md and start research
argument-hint: "<name> [goal] [--auto]"
allowed-tools: [Read, Write, Bash, Glob, Agent]
---

Create a new spec-drive project. Parse arguments, scaffold the project directory, write initial artifacts, then delegate research to the researcher agent.

## Parse Arguments

Extract from `$ARGUMENTS`:
- **name** (required): first token — the project name (e.g., `my-api` or `P300-my-api`)
- **goal** (optional): remaining text before any flags — the project vision
- **--auto** flag: if present, set mode to `auto` (bypass approval gates between phases)

If `$ARGUMENTS` is empty or name is missing, tell the user:
```
Usage: /spec-drive:new <name> [goal] [--auto]
Example: /spec-drive:new my-api Build a REST API for user management
```
Stop and wait for user input.

## Validate Project Name

<mandatory>
The project name MUST be validated before use in any path. Reject and stop if:
- Name contains `/` or `..` (path traversal)
- Name contains whitespace
- Name does not match `^[a-zA-Z0-9_.-]+$`

On rejection, tell the user:
```
Invalid project name: "<name>"
Names must contain only letters, numbers, hyphens, underscores, and dots.
No slashes, spaces, or path traversal (../) allowed.
```
</mandatory>

## Resolve Project Root

Determine where projects live:

```bash
# Config resolution (first match wins):
# 1. .spec-drive-config.json at nearest git root (or cwd if no git root)
# 2. ${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/config.json
# 3. $HOME/.spec-drive-config.json
#
# If projectRoot is relative, resolve it relative to the config file location.
PROJECT_ROOT="<resolved project root or $HOME/spec-drive-projects fallback>"
```

Full project path: `$PROJECT_ROOT/<name>/`
Spec path: `$PROJECT_ROOT/<name>/spec/`

## Create Project Structure

1. Create the directory:
```bash
mkdir -p "$PROJECT_ROOT/<name>/spec"
```

2. Initialize git repo if not already one:
```bash
cd "$PROJECT_ROOT/<name>" && git init 2>/dev/null
```

## Write idea.md

Read the template from the plugin's `templates/idea.md`. Replace placeholders and fill in content:

```markdown
---
spec: "<name>"
phase: idea
created: "<ISO timestamp>"
---

# Idea: <name>

## Vision

<goal text from arguments — paste verbatim>

## Constraints

<!-- User should fill constraints. Leave section with placeholder comment for now. -->
```

Write to `$PROJECT_ROOT/<name>/spec/idea.md`.

If no goal text was provided in arguments, ask the user:
```
No goal text provided. What is the vision for this project?
Write 2-3 sentences describing what it should accomplish.
```
Wait for user response, then write idea.md with their answer.

## Write .progress.md

Read the template from `templates/progress.md`. Create the initial progress file:

```markdown
---
spec: "<name>"
phase: idea
created: "<ISO timestamp>"
---

# Progress: <name>

## Original Goal

<goal text — same as idea.md Vision>

## Completed Tasks

## Current Task

Research phase starting

## Learnings

## Blockers

None currently

## Next

Research phase
```

Write to `$PROJECT_ROOT/<name>/spec/.progress.md`.

## Write .spec-drive-state.json

Create the initial state file:

```json
{
  "name": "<name>",
  "basePath": "$PROJECT_ROOT/<name>/spec",
  "phase": "research",
  "mode": "<auto|normal>",
  "taskIndex": 0,
  "totalTasks": 0,
  "taskIteration": 1,
  "maxTaskIterations": 5,
  "globalIteration": 1,
  "maxGlobalIterations": 100,
  "awaitingApproval": false,
  "taskResults": {}
}
```

- Set `mode` to `"auto"` if `--auto` flag was present, otherwise `"normal"`
- Write to `$PROJECT_ROOT/<name>/spec/.spec-drive-state.json`

## Delegate to Researcher

<mandatory>
Do NOT implement research directly. Delegate to the researcher agent via Task tool.

Invoke the researcher agent:
```
Task tool:
  subagent_type: spec-drive:researcher
  description: "Run research phase for project <name>"
  prompt: |
    basePath: $PROJECT_ROOT/<name>/spec
    projectName: <name>

    Read idea.md at the basePath and produce research.md following your research protocol.
```

Wait for the researcher agent to complete.
</mandatory>

## After Research Completes

Check the mode from state file:

**Normal mode** (default):
1. Update state: `awaitingApproval = true`
2. Tell the user:
```
Research complete. Review spec/<name>/spec/research.md

When ready, run: /spec-drive:requirements
```

**Auto mode** (`--auto`):
1. Do NOT set awaitingApproval
2. Immediately invoke the next phase:
```
Invoke: /spec-drive:requirements
```
This continues the autonomous chain through all phases.

## Summary

This command creates:
- `<project>/spec/idea.md` — project vision
- `<project>/spec/.progress.md` — progress tracker
- `<project>/spec/.spec-drive-state.json` — execution state
- `<project>/spec/research.md` — via researcher agent delegation
