---
description: List all spec-drive projects with status and last-activity
argument-hint: ""
allowed-tools: [Read, Bash, Glob]
---

# /spec-drive:list

Inventory all spec-drive projects and display their current status, sorted by most recent activity.

## Steps

### 1. Resolve PROJECT_ROOT

Determine where projects live by reading config (first match wins):
1. `.spec-drive-config.json` at the nearest git root (or cwd if no git root) — use `projectRoot` field
2. `${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/config.json` — use `projectRoot` field
3. Fallback: `$HOME/spec-drive-projects`

If `projectRoot` is a relative path in the config file, resolve it relative to that config file's directory.

Store the resolved path as `PROJECT_ROOT`.

### 2. Enumerate projects

Run:
```bash
find "$PROJECT_ROOT" -maxdepth 2 -name ".spec-drive-state.json" 2>/dev/null
```

For each discovered `.spec-drive-state.json`, read the file and extract:
- `name` — project name
- `phase` — current phase (idea, research, requirements, design, tasks, execution)
- `taskIndex` — current task index (0-based)
- `totalTasks` — total number of tasks
- `basePath` — absolute path to the spec directory

Also determine the last-activity timestamp for each project by checking the modification time of `.spec-drive-state.json`:
```bash
stat -c %Y "$state_file" 2>/dev/null || stat -f %m "$state_file" 2>/dev/null || echo 0
```
Convert the epoch timestamp to a human-readable relative time (e.g., "2h ago", "3d ago", "just now").

If `PROJECT_ROOT` does not exist or contains no projects:
```
No spec-drive projects found under: <PROJECT_ROOT>

To start a new project: /spec-drive:new <name>
```
Stop here.

### 3. Identify active project

Check `~/.spec-drive-active.json` for the currently pinned project:
```bash
cat ~/.spec-drive-active.json 2>/dev/null
```
If the file exists and contains a `name` field, use that as the active project name.

If `~/.spec-drive-active.json` does not exist, fall back to scanning cwd and parent directories for `.spec-drive-state.json` (same logic as `/spec-drive:status` step 1). The first match found this way is the active project.

### 4. Sort by last activity

Sort the collected project entries by their last-activity timestamp, descending (most recently active first).

### 5. Display table

Output:
```
=== Spec-Drive Projects ===

  NAME                  PHASE        TASKS      LAST ACTIVITY
  ──────────────────────────────────────────────────────────────
* my-active-project     execution    3/10       just now
  other-project         design       0/0        2h ago
  old-project           research     0/0        5d ago

* = active project
Total: 3 project(s) | PROJECT_ROOT: <PROJECT_ROOT>
```

Formatting rules:
- Mark the active project with `*` in the first column; use two spaces for inactive projects
- `TASKS` column: show `taskIndex/totalTasks` (e.g., `3/10`); if `totalTasks` is 0, show `0/0`
- `LAST ACTIVITY`: relative time — "just now" (<1 min), "Xm ago" (<1 h), "Xh ago" (<24 h), "Xd ago" (≥24 h)
- Align columns with padding for readability
- If `phase` is `execution` and the project is not the active one, add `(idle)` suffix to phase

### 6. Handle single project

If only one project exists, add a hint at the bottom:
```
Tip: /spec-drive:status for full details on the active project
```
