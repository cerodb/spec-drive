# Phase Transition Checklists

Quality gates between phases. Each command validates the relevant checklist before delegating to an agent. If any item fails, the command outputs a specific error and suggests a fix.

Commands read this file at runtime — edit to customize validation rules.

## research -> requirements

Before `/spec-drive:requirements` can proceed:

- [ ] `research.md` exists in the spec directory
- [ ] research.md contains `## Executive Summary` section
- [ ] research.md contains `## Feasibility Assessment` section
- [ ] research.md contains `## Open Questions` section

## requirements -> design

Before `/spec-drive:design` can proceed:

- [ ] `requirements.md` exists in the spec directory
- [ ] requirements.md contains at least one user story with acceptance criteria (AC-X.Y format)
- [ ] requirements.md contains a Functional Requirements table with priority column
- [ ] requirements.md contains `## Out of Scope` section
- [ ] current requirements.md SHA-256 has explicit kernel approval evidence

## design -> tasks

Before `/spec-drive:tasks` can proceed:

- [ ] `design.md` exists in the spec directory
- [ ] design.md contains `## Components` or `## Component` section
- [ ] design.md references acceptance criteria IDs (AC-* pattern)
- [ ] design.md contains `## Technical Decisions` section
- [ ] design.md `requirements_sha` matches the approved requirements SHA-256
- [ ] current design.md SHA-256 has explicit kernel approval evidence

## tasks -> execution

Before `/spec-drive:implement` can proceed:

- [ ] `tasks.md` exists in the spec directory
- [ ] tasks.md contains at least one unchecked task matching `- [ ]`
- [ ] tasks.md contains at least one `[VERIFY]` checkpoint task
- [ ] every task uses a unique canonical ID (`X.Y` or `V#`) and includes Do, Files, Traces, Cwd, Done when, Verify, Timeout, and Commit
- [ ] each `Timeout` is a positive integer number of seconds without a unit
- [ ] checkpoint tasks declare `Files: none` and `Commit: none`
- [ ] tasks.md `requirements_sha` and `design_sha` match the approved upstream SHA-256 values
- [ ] every AC-N.N and NFR-N from requirements.md appears in design coverage and at least one task Traces field
- [ ] current tasks.md SHA-256 has explicit kernel approval evidence
- [ ] execution-kernel `preflight` returns `ok: true` before dispatch

## Validation Algorithm

```
1. Read this file (phase-checklists.md) from skill references
2. Find the section matching the current transition
3. For each checklist item:
   a. File existence: attempt to Read the file
   b. Section/pattern existence: search file content for the required string
4. If any item fails:
   - Output: "Checklist failed: [item description]"
   - Suggest: specific fix action
   - Do NOT proceed to agent delegation
5. If all items pass:
   - Proceed with phase transition and agent delegation
```
