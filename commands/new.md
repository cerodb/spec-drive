---
description: Create a new spec-driven project with idea.md and start research
argument-hint: "<name> [goal] [--auto] [--deep]"
allowed-tools: [Read, Write, Bash, Glob, Agent]
---

Create a new spec-drive project. Parse arguments, complete any required user interaction, delegate the filesystem scaffold to the executable registrar, then delegate research to the researcher agent.

## Parse Arguments

Extract from `$ARGUMENTS`:
- **name** (required): first token — the project name (e.g., `my-api` or `P300-my-api`)
- **goal** (optional): remaining text before any flags — the project vision
- **--auto** flag: if present, set mode to `auto` (bypass approval gates between phases)
- **--deep** flag: if present, request a deeper research pass during the research phase

If `$ARGUMENTS` is empty or name is missing, tell the user:
```
Usage: /spec-drive:new <name> [goal] [--auto] [--deep]
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

## Collect Missing Goal Before Mutation

If no goal text was provided in arguments, ask the user:
```
No goal text provided. What is the vision for this project?
Write 2-3 sentences describing what it should accomplish.
```
Wait for user response before continuing.

<mandatory>
Do not resolve the projects container or call the scaffold until every required prompt has completed.
</mandatory>

## Resolve Projects Container

Resolve the configured projects container through the shared resolver:

```bash
. hooks/scripts/resolve-config.sh
PROJECTS_CONTAINER="$(spec_drive_resolve_projects_container "$PWD")"
```

If the resolver exits non-zero, stop and surface its stderr unchanged.

## Delegate Project Scaffold

Invoke the executable scaffold and capture the published project path from stdout:

```bash
PROJECT_PATH=""
CREATE_PROJECT_STDERR="$(mktemp)"
set +e
PROJECT_PATH="$(bash hooks/scripts/create-project.sh \
  --projects-container "$PROJECTS_CONTAINER" \
  --project-slug "$name" \
  --goal "$goal" \
  --mode "$mode" \
  --research-depth "$researchDepth" 2>"$CREATE_PROJECT_STDERR")"
CREATE_PROJECT_STATUS=$?
set -e
if [ "$CREATE_PROJECT_STATUS" -eq 2 ]; then
  cat "$CREATE_PROJECT_STDERR" >&2
  rm -f "$CREATE_PROJECT_STDERR"
  exit 2
elif [ "$CREATE_PROJECT_STATUS" -ne 0 ]; then
  cat "$CREATE_PROJECT_STDERR" >&2
  rm -f "$CREATE_PROJECT_STDERR"
  exit "$CREATE_PROJECT_STATUS"
fi
rm -f "$CREATE_PROJECT_STDERR"
SPEC_PATH="$PROJECT_PATH/spec"
```

- Set `mode` to `"auto"` if `--auto` flag was present, otherwise `"normal"`
- Set `researchDepth` to `"deep"` if `--deep` flag was present, otherwise `"standard"`
- The scaffold creates the project root, root `.spec-drive-config.json`, `spec/idea.md`, `spec/.progress.md`, `spec/.spec-drive-state.json`, and initializes the project Git repository.

Handle scaffold exits as follows:

- Exit `0`: continue and use `PROJECT_PATH`/`SPEC_PATH` from stdout.
- Exit `2`: stop and tell the user the destination project already exists; do not delegate Research.
- Any other non-zero exit: stop, surface the scaffold stderr, and do not delegate Research.

## Delegate to Researcher

<mandatory>
Do NOT implement research directly. Delegate to the researcher agent only after the scaffold exits `0`.

Invoke the researcher agent:
```
Task tool:
  subagent_type: spec-drive:researcher
  description: "Run research phase for project <name>"
  prompt: |
    basePath: $SPEC_PATH
    projectName: <name>
    researchDepth: <deep|standard>

    Read idea.md at the basePath and produce research.md following your research protocol.
```

Wait for the researcher agent to complete.
</mandatory>

If the researcher agent fails after scaffold success, stop and tell the user:
```
Project scaffolded successfully at: <PROJECT_PATH>
Research delegation failed after project creation.

Recovery: open the created project and run /spec-drive:research
```
Do not roll back the scaffolded project.

## After Research Completes

Check the mode from state file at `$SPEC_PATH/.spec-drive-state.json`.

**Normal mode** (default):
1. Update state: `awaitingApproval = true`
2. Tell the user:
```
Research complete. Review <PROJECT_PATH>/spec/research.md

When ready, run: /spec-drive:requirements
```

**Auto mode** (`--auto`):
1. Set `awaitingApproval = true`
2. Stop after research exactly like normal mode
3. Tell the user:
```
Research complete. Review <PROJECT_PATH>/spec/research.md

Auto mode does not bypass definition-phase review gates.
When ready, run: /spec-drive:requirements
```
Auto mode only becomes autonomous after a reviewed task plan exists and execution begins.

## Summary

This command creates:
- `<project>/.spec-drive-config.json` — portable project identity
- `<project>/spec/idea.md` — project vision
- `<project>/spec/.progress.md` — progress tracker
- `<project>/spec/.spec-drive-state.json` — execution state
- `<project>/spec/research.md` — via researcher agent delegation after scaffold success

Behavior flags:
- `--auto` — keeps later execution more autonomous, but does **not** bypass definition-phase review gates
- `--deep` — requests a more exhaustive research pass before requirements
