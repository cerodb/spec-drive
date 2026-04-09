---
description: Iterate coherently on spec artifacts after discovering design flaws during execution
argument-hint: ""
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# /spec-drive:refactor

Refactor spec artifacts after execution learnings reveal design flaws. Updates requirements → design → tasks in sequence, recording all changes in `.progress.md`.

## Steps

### 1. Find active project

Locate the spec directory:
1. Check if the current working directory contains `.spec-drive-state.json`
2. If not, scan for a `spec/` subdirectory containing `.spec-drive-state.json`
3. If not found, check the parent directory for a project root with `spec/.spec-drive-state.json`
4. If still not found, check `~/.spec-drive-active.json` → use `activePath`

If no active project is found:
```
No active spec-drive project found.
Run /spec-drive:new <name> to create one, or cd into the project directory.
```
Stop here.

Set `basePath` to the directory containing `.spec-drive-state.json`.

### 2. Read execution learnings from .progress.md

Read `{basePath}/.progress.md`. Extract the **Learnings** section — any notes the executor recorded about flaws, surprises, or mismatches between the spec and reality.

If `.progress.md` does not exist or has no Learnings section:
```
No execution learnings found in .progress.md.
Run /spec-drive:implement first to accumulate learnings before refactoring.
```
Stop here.

Summarize the learnings you will address:
```
=== Execution Learnings ===
<bullet-point summary of learnings from .progress.md>
```

### 3. Read current state and validate phase

Read `.spec-drive-state.json`. Extract:
- `phase` — current phase
- `requirementsSha` — SHA of requirements.md when tasks.md was last generated (may be absent)
- `designSha` — SHA of design.md when tasks.md was last generated (may be absent)

Check phase validity against `skills/spec-workflow/references/phase-transitions.md`.

Refactor is valid from any phase after **requirements** (requirements, design, tasks, or execution).

If phase is "idea" or "research":
```
Cannot refactor: no requirements exist yet (current phase: {phase}).
Complete research and generate requirements first.
```
Stop here.

### 4. Detect staleness via requirementsSha and designSha

Compute current SHAs of the existing artifacts:
```bash
git hash-object "{basePath}/requirements.md" 2>/dev/null || sha256sum "{basePath}/requirements.md" 2>/dev/null | cut -c1-64
git hash-object "{basePath}/design.md" 2>/dev/null || sha256sum "{basePath}/design.md" 2>/dev/null | cut -c1-64
```

Compare against stored values in `.spec-drive-state.json`:
- If `requirementsSha` is set and differs from current SHA → requirements.md has changed since tasks were generated → mark as **stale**
- If `designSha` is set and differs from current SHA → design.md has changed since tasks were generated → mark as **stale**
- If either SHA field is absent → cannot determine staleness → treat as **unknown** (proceed with refactor anyway)

Report staleness:
```
Staleness check:
  requirements.md: [stale | unchanged | unknown]
  design.md:       [stale | unchanged | unknown]
```

### 5. Update requirements.md

Read `{basePath}/requirements.md` in full.

For each learning from step 2, determine whether it requires a requirements change (scope change, missing edge case, incorrect assumption about user needs).

Present a diff of proposed changes. Ask for confirmation before writing if in normal mode. In auto mode (state `mode: "auto"`), apply directly.

Apply approved changes and save `{basePath}/requirements.md`.

If no requirements changes are needed:
```
requirements.md: no changes needed
```

### 6. Update design.md

Read `{basePath}/design.md` in full.

For each learning from step 2, and taking into account any requirements changes from step 5, determine whether it requires a design change (wrong component boundary, missing data flow, incorrect API contract, performance concern discovered during implementation).

Present a diff of proposed changes. Ask for confirmation before writing if in normal mode.

Apply approved changes and save `{basePath}/design.md`.

If no design changes are needed:
```
design.md: no changes needed
```

### 7. Update tasks.md

Read `{basePath}/tasks.md` in full.

Identify tasks that are now incorrect, missing, or superseded due to changes in requirements or design. Also incorporate any tasks explicitly flagged in `.progress.md` as incomplete or requiring re-work.

Apply targeted updates:
- Add new tasks for gaps discovered during execution
- Remove or rewrite tasks made obsolete by design changes
- Keep already-completed tasks (marked `[x]`) intact — do not reopen them

Present a diff. Ask for confirmation before writing if in normal mode.

Apply approved changes and save `{basePath}/tasks.md`.

If no tasks changes are needed:
```
tasks.md: no changes needed
```

### 8. Record changes in .progress.md CHANGELOG section

Append a CHANGELOG entry to `{basePath}/.progress.md`:

```markdown
## CHANGELOG — {ISO 8601 timestamp}

### Trigger
Refactor initiated after execution learnings revealed:
- <learning 1>
- <learning 2>

### requirements.md
<summary of changes made, or "no changes">

### design.md
<summary of changes made, or "no changes">

### tasks.md
<summary of changes made, or "no changes">

### Rationale
<brief explanation of why these changes were necessary based on the learnings>
```

### 9. Update .spec-drive-state.json

Recompute SHAs for the updated artifacts and write back to state:
```bash
git hash-object "{basePath}/requirements.md" 2>/dev/null || sha256sum "{basePath}/requirements.md" | cut -c1-64
git hash-object "{basePath}/design.md" 2>/dev/null || sha256sum "{basePath}/design.md" | cut -c1-64
```

Update `.spec-drive-state.json`:
- `requirementsSha` → new SHA of requirements.md
- `designSha` → new SHA of design.md

If phase was "execution" and tasks.md changed, set phase back to "tasks" so `/spec-drive:implement` re-validates the plan before continuing.

Use atomic write pattern (write to temp, then rename):
```bash
tmp=$(mktemp "{basePath}/.spec-drive-state.json.XXXXXX")
# write updated JSON
mv "$tmp" "{basePath}/.spec-drive-state.json"
```

### 10. Confirm completion

Output:
```
=== Spec Refactor Complete ===

  requirements.md: [updated | unchanged]
  design.md:       [updated | unchanged]
  tasks.md:        [updated | unchanged]
  CHANGELOG:       appended to .progress.md

Next steps:
  - Review changes: cat {basePath}/.progress.md
  - Resume execution: /spec-drive:implement
  - View task plan: cat {basePath}/tasks.md
```

See `skills/spec-workflow/references/phase-transitions.md` for valid next phase navigation.
