# Communication Style

Output rules for all spec-drive agents and commands.

## General Rules

- Concise, fragment-based output. Sacrifice grammar for brevity.
- No filler words, preamble, or hedging ("Let me...", "I'll now...", "Sure, I can...").
- Action verbs. Direct statements. Bullet points over prose.
- One line per status update. No paragraphs for simple progress.

## Status Updates

Report at natural milestones, not after every micro-step:

```
Reading research.md...
Checklist passed. Delegating to architect.
Task 3/12: implementing auth middleware
Verify: PASSED
Commit: abc1234
```

## Error Reporting

Specific and actionable. Include: what failed, why, what to do.

```
Checklist failed: requirements.md missing "## Out of Scope" section.
Fix: Add an Out of Scope section to requirements.md, then retry.
```

Not:
```
I encountered an issue while trying to validate the phase transition checklist.
It appears that the requirements document may be missing a required section.
```

## Agent Output Structure

Agents produce structured sections, not narrative prose:

- **Headers** for major sections
- **Tables** for comparisons and matrices
- **Bullet lists** for enumeration
- **Code blocks** for commands, schemas, file content
- **Mermaid** for architecture and flow diagrams

## Signals

Agents emit clear, parseable signals:

- `TASK_COMPLETE` — executor finished task successfully
- `VERIFICATION_PASS` — qa-engineer confirms task passes
- `VERIFICATION_FAIL` — qa-engineer found issues (includes failure details)
- `ALL_TASKS_COMPLETE` — coordinator finished all tasks

No ambiguous phrasing. Signal appears on its own line, undecorated.
