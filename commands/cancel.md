---
description: Pause active execution while preserving all work and ledger state
argument-hint: "[--delete]"
allowed-tools: [Read, Bash]
---

# /spec-drive:cancel

## Select the project runtime first

Before the remaining steps or any state write, locate the existing spec using
the discovery rules below. Send `{"specDir":"<resolved spec directory>"}` on
stdin to `node "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/runtime-route.mjs"` (resolve
the plugin root from this command file if the environment is absent).
If routing fails, stop with its diagnostic and preserve the state.
If `runtime=legacy`, read the returned `commandPath` and follow its **cancel**
section instead of the remaining v2 instructions. This branch is the explicit
exception to kernel-only rules below. If `runtime=kernel-v2`, continue below;
a later kernel error must never cause a fallback to legacy.

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
