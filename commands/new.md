---
description: Create, adopt or resume a spec-driven project conservatively
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
Enter **Agent Recovery** below; this missing name is an unresolved human decision.

## Recover Input and Resolve Local Identity Before Mutation

The command is an agent-facing protocol, not a reason to make the user repeat
their request. If malformed quoting or a single text block has an unambiguous,
explicitly supplied name and goal, normalize the invocation while preserving the
goal and flags. Never turn an arbitrary description into an invented slug.
If there are multiple plausible interpretations, ask one concise question and
wait before resolving paths or creating files. Retain the information already given.

Apply the active workspace's naming and project-identity conventions before the
scaffold. Use an already authorized full slug, including any locally required
prefix. If identity or reuse of an existing project is unclear, ask before writing;
do not create a short-name project intending to rename it afterward. Local registry
lookup/registration belongs to the authorized local agent workflow, not this
generic plugin; do not hardcode a registry, numbering scheme or database here.

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
Enter **Agent Recovery**: stop filesystem mutations, retain the goal, and ask for a safe name. Do not silently
sanitize unsafe names or bypass the scaffold's validation.
</mandatory>

## Collect Missing Goal Before Mutation

If no goal text was provided, resolve the container read-only using the block
below and inspect the recognized project's existing `spec/idea.md` read-only.
Reuse its unambiguous vision without asking the user to restate it. Do not infer
approval from that text. Ask only if the goal is truly unavailable or ambiguous:
```
No goal text provided. What is the vision for this project?
Write 2-3 sentences describing what it should accomplish.
```
Enter **Agent Recovery** and wait for this unresolved decision before continuing.

<mandatory>
Do not call the scaffold until every required prompt has completed. Read-only
container resolution for goal recovery is permitted before prompting.
</mandatory>

## Agent Recovery

All failures and ambiguities in this command transfer control back to the calling
agent through this protocol. Here, **stop** means stop filesystem mutations and
dependent dispatches; it does not mean end the conversation or merely print a
terminal error.

1. Preserve the real non-zero status, existing artifacts, supplied
   name/goal/flags, and all diagnostics and structured results still available
   to the agent. Preserve captured bytes exactly, but never invent stdout or
   other data that the shell did not retain. Do not convert failure to success,
   reset JSON/state to force progress, roll back valid work, bypass a permission
   or safety boundary, or automatically rerun a failed operation.
2. Inspect the real current state and relevant artifacts read-only. Classify what
   failed and what may already have completed. Resolve only a safe, unequivocal,
   already-authorized correction; uncertain partial work is not permission to
   redelegate or retry.
3. If a decision is still required, ask exactly one concise question for that
   unresolved decision. Include the observed evidence, what is preserved, the
   boundary blocking progress, and the recommended safe action. Never fabricate
   the answer or ask the human to repeat known context. With no response, keep
   the decision pending and do not ask it again without new evidence.
4. After an agent resolution or human answer, reread the actual state and
   artifacts, recompute routing, and continue from the preserved checkpoint.
   Do not reinitialize the project or blindly repeat the resolver, scaffold, or
   researcher dispatch. Before any retry, require evidence that the cause was
   resolved or an explicit decision authorizing a supervised retry. Never enter
   a retry loop; the original permission and safety protections remain in force.

This protocol covers resolver failures, a non-zero scaffold exit, an invalid
`ScaffoldResult`, a structured scaffold conflict, state changed since the result,
an existing `research.md`, and researcher failure (including uncertain partial
research). Diagnostics below identify the recovery edge; they do not authorize a
retry. Human escalation is only for a real unresolved decision.

## Resolve Projects Container

Resolve the configured projects container through the shared resolver. Run this
block from the user's workspace, with `SPEC_DRIVE_PLUGIN_ROOT` set to the absolute
path of the selected plugin core (not a guessed installation). Explicit Bash is required even
when the caller uses zsh; a shebang does not select the shell when sourcing.
Pass paths as positional arguments, never interpolate user input into shell code:

```bash
if PROJECTS_CONTAINER="$(bash -c '
  . "$1"
  spec_drive_resolve_projects_container "$2"
' spec-drive-resolve "$SPEC_DRIVE_PLUGIN_ROOT/hooks/scripts/resolve-config.sh" "$PWD")"; then
  :
else
  exit "$?"
fi
```

If the resolver exits non-zero, preserve its status and stderr unchanged and enter
**Agent Recovery** before any mutation.

## Delegate Project Scaffold

Invoke the executable scaffold in JSON mode. Validate only the structured
`ScaffoldResult` contract and exit status; never parse stderr or Markdown to
classify a destination. The registrar owns identity and artifact coherence checks.

```bash
NEW_ACTION="stop"
CREATE_PROJECT_STDERR="$(mktemp)"
set +e
SCAFFOLD_RESULT="$(bash "$SPEC_DRIVE_PLUGIN_ROOT/hooks/scripts/create-project.sh" \
  --projects-container "$PROJECTS_CONTAINER" \
  --project-slug "$name" \
  --goal "$goal" \
  --mode "$mode" \
  --research-depth "$researchDepth" --result-format json 2>"$CREATE_PROJECT_STDERR")"
CREATE_PROJECT_STATUS=$?
set -e
if [ "$CREATE_PROJECT_STATUS" -ne 0 ] && [ "$CREATE_PROJECT_STATUS" -ne 2 ]; then
  cat "$CREATE_PROJECT_STDERR" >&2
  rm -f "$CREATE_PROJECT_STDERR"
  exit "$CREATE_PROJECT_STATUS"
fi
rm -f "$CREATE_PROJECT_STDERR"
if ! printf '%s' "$SCAFFOLD_RESULT" | jq -e -s --argjson status "$CREATE_PROJECT_STATUS" '
  length == 1 and (.[0] | type == "object" and
  (.path | type == "string" and startswith("/")) and
  (if .outcome == "conflict" then
    $status == 2 and (.error.code | type == "string" and length > 0) and
    (.error.path | type == "string" and length > 0)
  else $status == 0 and
    (.outcome | IN("created", "adopted", "resumable")) and
    (if .outcome == "resumable" then
      (.phase | IN("idea", "research", "requirements", "design", "tasks", "execution", "completed"))
    else true end)
  end))' >/dev/null; then
  printf '%s\n' 'Invalid ScaffoldResult; agent recovery required without delegation.' >&2
  exit 1
fi
OUTCOME="$(printf '%s' "$SCAFFOLD_RESULT" | jq -r '.outcome')"
PROJECT_PATH="$(printf '%s' "$SCAFFOLD_RESULT" | jq -r '.path')"
if [ "$OUTCOME" = conflict ]; then
  printf '%s' "$SCAFFOLD_RESULT" | jq -r '"Scaffold conflict: \(.error.code) at \(.path)/\(.error.path). Agent inspection required before any retry."' >&2
  exit 2
fi
SPEC_PATH="$PROJECT_PATH/spec"
STATE="$(cat "$SPEC_PATH/.spec-drive-state.json")"
PHASE="$(printf '%s' "$STATE" | jq -er '.phase')"
AWAITING_APPROVAL="$(printf '%s' "$STATE" | jq -r '.awaitingApproval // false')"
if [ "$OUTCOME" = resumable ] && [ "$PHASE" != "$(printf '%s' "$SCAFFOLD_RESULT" | jq -r '.phase')" ]; then
  printf 'State changed: inspect %s\n' "$SPEC_PATH/.spec-drive-state.json" >&2
  exit 1
fi
NEW_ACTION=route
NEXT_COMMAND=""
case "$PHASE" in
  idea) NEXT_COMMAND=/spec-drive:research ;;
  research)
    if [ "$AWAITING_APPROVAL" = true ]; then
      NEXT_COMMAND=/spec-drive:requirements
    else
      NEXT_COMMAND=/spec-drive:research
    fi ;;
  requirements) NEXT_COMMAND=/spec-drive:design ;;
  design) NEXT_COMMAND=/spec-drive:tasks ;;
  tasks|execution) NEXT_COMMAND=/spec-drive:implement ;;
  completed) NEW_ACTION=report ;;
  *) printf 'Unknown phase: inspect %s\n' "$SPEC_PATH/.spec-drive-state.json" >&2; exit 1 ;;
esac
if [ "$OUTCOME" = created ] || { [ "$OUTCOME" = adopted ] &&
  printf '%s' "$STATE" | jq -e '.phase == "research" and .awaitingApproval == false and
    .taskIndex == 0 and .totalTasks == 0 and .taskIteration == 1 and
    .globalIteration == 1 and .taskResults == {}' >/dev/null; }; then
  if [ -e "$SPEC_PATH/research.md" ] || [ -L "$SPEC_PATH/research.md" ]; then
    printf 'Research output-path conflict: %s; preserve and inspect before research.\n' "$SPEC_PATH/research.md" >&2
    exit 2
  fi
  NEW_ACTION=research
  researchDepth="$(printf '%s' "$STATE" | jq -r '.researchDepth // "standard"')"
fi
```

- Set `mode` to `"auto"` if `--auto` flag was present, otherwise `"normal"`
- Set `researchDepth` to `"deep"` if `--deep` flag was present, otherwise `"standard"`
- Persist the selected depth in the scaffolded state as `"researchDepth": "<deep|standard>"`.
- The scaffold creates the project root, root `.spec-drive-config.json`, `spec/idea.md`, `spec/.progress.md`, `spec/.spec-drive-state.json`, and initializes the project Git repository.

## Route the Result Before Delegation

On any shell failure, enter **Agent Recovery**. For `conflict`, report the structured error code and
path without interpreting file content or duplicating phase checklists. An
existing research output is preserved; inspect the reported path and ask one
concise question if needed before any later research attempt. Never infer approval.

Only `NEW_ACTION=research` continues to the researcher and After Research steps.
For `NEW_ACTION=route`, report `PROJECT_PATH`, the current phase, approval status,
and `NEXT_COMMAND`, then stop. `awaitingApproval=true` means awaiting human review,
not approved: tell the user to review the current artifact before invoking the
next command. Its existing gate/checklist remains authoritative; do not copy it.
Research with false (including the legacy absent value) routes to research;
research with true routes to requirements after review. Requirements routes to
design, design to tasks, and tasks/execution to implement. There is no idea command:
idea routes to research. Do not tell the user to rerun a completed phase.

For `NEW_ACTION=report`, report that the project is completed and stop without
dispatch. For `resumable`, never write state or automatically delegate any phase,
even with `--auto`; flags do not replace saved mode or depth. The same routing
applies to adopted state that is not initial research. Do not run After Research
for either routing or completion reports.



For every `Agent` or `Task tool` dispatch through Codex, follow the shared Codex adapter's
`Paso 2 - Traducir delegación a subagente` protocol and have the adapter apply it. Normalize role,
resolved prompt, absolute `basePath`, stable `unitKey`, and tier; definition delegations default to
`standard` only when no tier is explicit. Resolve the current candidate through
`resolve-model.sh <tier> codex` immediately before dispatch. Keep after-delegation state changes
behind exit success and required artifact validation.

## Delegate to Researcher

<mandatory>
Do NOT implement research directly. Delegate to the researcher agent only after the scaffold exits `0`
and the result routing selects `NEW_ACTION=research`.

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

If the researcher agent fails after scaffold success, enter **Agent Recovery**.
First inspect `research.md`, state, and the complete delegation result to determine
whether work completed, partially completed, or did not start. Do not redelegate
while the result is uncertain. If a human decision remains, tell the user:
```
Project scaffolded successfully at: <PROJECT_PATH>
Research delegation failed after project creation.

Observed evidence: <status and preserved artifacts>
Recommended safe action: <one action justified by inspection>
Question: <the one unresolved decision>
```
Do not roll back the scaffolded project. After resolution, reread state and
artifacts and resume from them; do not reinitialize or blindly dispatch research.

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
