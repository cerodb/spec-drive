---
description: Cancel active execution and cleanup state
argument-hint: "[--delete]"
allowed-tools: [Read, Write, Bash]
---

# /spec-drive:cancel

Cancel the active spec-drive execution and clean up state.

## Steps

### 1. Find active project

Look for `.spec-drive-state.json` in:
1. Current working directory
2. `./spec/` subdirectory of cwd
3. Parent directory of cwd (if cwd is `spec/`)

If not found, scan `~/spec-drive-projects/` for any directory containing `.spec-drive-state.json`.

If no active project is found:
```
No active spec-drive project to cancel.
```
Stop here.

### 2. Read state before deletion

Read `.spec-drive-state.json` to get the project name and basePath for confirmation output.

Resolve and validate:
- `projectDir` = parent directory of `basePath`
- Resolve symlinks: `projectDir="$(readlink -f "$projectDir")"`
- approved root = resolve `~/spec-drive-projects/` (or configured `projectRoot` from workspace -> XDG config order) with `readlink -f`
- refuse if `projectDir` is empty, `/`, `$HOME`, or the resolved path is outside the resolved approved root

If the resolved path fails validation:
```
Refusing to cancel/delete: resolved project path is outside the approved Spec-Drive root.
```
Stop here.

### 3. Delete state file

Remove `.spec-drive-state.json`:

```bash
rm -f "{basePath}/.spec-drive-state.json"
```

This stops any execution loop — the stop-watcher hook checks for this file and exits if missing.

### 4. Clean up orphaned progress files

Remove any temporary parallel execution progress files:

```bash
rm -f "{basePath}/.progress-task-"*.md
rm -rf "{basePath}/.execution-state.lock"
```

### 5. Handle --delete flag

Check if the user passed `--delete` as an argument.

**Without --delete** (default):
```
Cancelled: {name}
State file removed. All spec artifacts preserved in {basePath}.
To resume later, run /spec-drive:implement from the project directory.
```

**With --delete**:

First, ask for explicit confirmation:
```
WARNING: This will permanently delete the entire project directory:
  {projectDir}

All spec documents, progress, and generated code will be lost.
Type the project name to confirm deletion: {name}
```

Wait for the user to type the project name. If confirmed:
```bash
if command -v trash >/dev/null 2>&1; then
  trash "{projectDir}"
else
  rm -rf "{projectDir}"
fi
```

Only perform the deletion if the path validation from Step 2 succeeded.

Output:
```
Deleted: {projectDir}
```

If the user cancels or types the wrong name:
```
Deletion cancelled. Project preserved at {projectDir}.
```
