---
description: Pause active execution while preserving all work and ledger state
argument-hint: "[--delete]"
allowed-tools: [Read, Bash]
---

# /spec-drive:cancel

Cancel means pause, not state deletion.

## Default behavior

Resolve one cwd-bound spec directory using the same safe discovery rules as `/spec-drive:implement`. Read the project name only for display, then send this request to `hooks/scripts/execution-kernel.mjs`:

```json
{"op":"pause","specDir":"<specDir>","reason":"operator requested /spec-drive:cancel"}
```

Only report success when the kernel exits `0` with `ok:true`. The kernel preserves the state file, worktree bytes, `currentTaskId`, `currentStage`, `activeAttemptId`, attempts, task states, and every budget counter.

Output:

```text
Paused: {name}
All work and execution budgets were preserved.
To continue, run /spec-drive:implement; it begins with kernel resume.
```

Do not remove `.spec-drive-state.json`, progress files, locks, worktrees, branches, or commits. Do not edit `phase`, task identity, attempts, budgets, or checkboxes.

## `--delete`

Keep the existing explicit project-removal affordance, but pause successfully first. Then resolve symlinks and require the project directory to be a non-empty child of the configured Spec-Drive projects container. Refuse `/`, `$HOME`, the container itself, or any path outside the approved Spec-Drive root.

Show the full resolved path and require the user to type the exact project name. Check `command -v trash` and prefer `trash` when available; otherwise require a second explicit confirmation before permanent removal. Project deletion is an operator lifecycle action after kernel pause, not an execution-state transition.

If confirmation does not match, leave the paused project untouched.
