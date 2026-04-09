---
description: Switch the active spec-drive project without changing directories
argument-hint: "[name-or-number]"
allowed-tools: [Read, Bash, Glob]
---

# /spec-drive:switch

Explicitly set the active spec-drive project and record it in `~/.spec-drive-active.json`.

## Steps

### 1. Resolve PROJECT_ROOT

Determine where projects live by reading config (first match wins):
1. `.spec-drive-config.json` at the nearest git root (or cwd if no git root) — use `projectRoot` field
2. `${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/config.json` — use `projectRoot` field
3. Fallback: `$HOME/spec-drive-projects`

If `projectRoot` is a relative path in the config file, resolve it relative to that config file's directory.

Store the resolved path as `PROJECT_ROOT`.

### 2. Enumerate all spec projects

Run:
```bash
find "$PROJECT_ROOT" -maxdepth 2 -name ".spec-drive-state.json" 2>/dev/null
```

For each discovered `.spec-drive-state.json`, read and extract:
- `name` — project name
- `phase` — current phase
- `basePath` — absolute path to the spec directory

Sort results by last-activity timestamp descending:
```bash
stat -c %Y "$state_file" 2>/dev/null || stat -f %m "$state_file" 2>/dev/null || echo 0
```

If no projects are found:
```
No spec-drive projects found under: <PROJECT_ROOT>

To start a new project: /spec-drive:new <name>
```
Stop here.

### 3. Present selection menu

If the user provided a name or number argument, skip to step 4 using that value.

Otherwise display a numbered list:
```
=== Switch Active Spec-Drive Project ===

  1. my-active-project   [execution]   3/10 tasks   just now
  2. other-project       [design]      0/0  tasks   2h ago
  3. old-project         [research]    0/0  tasks   5d ago

Enter number or project name (or q to cancel):
```

Wait for user input.

### 4. Resolve selection

Accept either:
- A **number** (1-based index from the displayed list)
- A **project name** (exact or case-insensitive prefix match)

If the input does not match any project:
```
No project found matching: <input>
Run /spec-drive:list to see all projects.
```
Stop here.

If the user enters `q` or presses Ctrl-C, output:
```
Switch cancelled.
```
Stop here.

### 5. Write active registry

Write `~/.spec-drive-active.json` with the following structure:
```json
{
  "activePath": "<basePath of selected project>",
  "name": "<name of selected project>",
  "switchedAt": "<ISO 8601 timestamp>"
}
```

Example:
```json
{
  "activePath": "/home/user/spec-drive-projects/my-project/spec",
  "name": "my-project",
  "switchedAt": "2026-04-09T14:30:00.000Z"
}
```

Use atomic write (write to a temp file, then rename):
```bash
tmp=$(mktemp ~/.spec-drive-active.json.XXXXXX)
echo '{"activePath":"...","name":"...","switchedAt":"..."}' > "$tmp"
mv "$tmp" ~/.spec-drive-active.json
```

### 6. Confirm the switch

Output:
```
Switched active project to: <name>
  Path:       <activePath>
  Phase:      <phase>
  Switched:   <human-readable time>

Run /spec-drive:status for full details.
```

### 7. Compatibility fallback (no registry)

Other spec-drive commands (`status`, `implement`, `research`, etc.) detect the active project using the following precedence:

1. **Registry file**: Read `~/.spec-drive-active.json` → use `activePath`
2. **cwd scan**: Walk cwd and parent directories looking for `.spec-drive-state.json`; use the first match found

This means `/spec-drive:switch` is optional — all commands work without it via cwd detection. Use `/spec-drive:switch` when you need to work on a project that is not in your current directory tree.

### Active Registry Format Reference

File: `~/.spec-drive-active.json`

| Field        | Type   | Description                                      |
|--------------|--------|--------------------------------------------------|
| `activePath` | string | Absolute path to the spec directory (basePath)   |
| `name`       | string | Project name from `.spec-drive-state.json`       |
| `switchedAt` | string | ISO 8601 timestamp of when the switch was made   |

The registry is user-scoped (home directory) and shared across all terminal sessions and CLIs. It is overwritten on each `/spec-drive:switch` call and may be deleted to revert to cwd detection.
