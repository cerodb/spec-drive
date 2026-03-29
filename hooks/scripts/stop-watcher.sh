#!/bin/bash
# Stop Hook for Spec-Drive
# Execution loop driver — detects active projects and outputs continuation prompts
# 1. Finds active project (cwd or ~/spec-drive-projects/)
# 2. Validates state file integrity
# 3. Checks for completion / iteration limits
# 4. Outputs continuation prompt for execution or auto mode
# 5. Cleans up orphaned temp progress files

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Bail out cleanly if jq is unavailable
command -v jq >/dev/null 2>&1 || exit 0

# Get working directory (guard against parse failures)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -z "$CWD" ]; then
    exit 0
fi

# Get transcript path for completion check
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)

# Default project root (overridable via config)
CONFIG_FILE="${HOME}/.spec-drive-config.json"
if [ -f "$CONFIG_FILE" ] && jq empty "$CONFIG_FILE" 2>/dev/null; then
    PROJECT_ROOT=$(jq -r '.projectRoot // "'"${HOME}/spec-drive-projects"'"' "$CONFIG_FILE" 2>/dev/null || echo "${HOME}/spec-drive-projects")
else
    PROJECT_ROOT="${HOME}/spec-drive-projects"
fi

PROJECT_ROOT_REAL="$(readlink -f "$PROJECT_ROOT" 2>/dev/null || echo "$PROJECT_ROOT")"

is_safe_spec_path() {
    local candidate="$1"
    [ -n "$candidate" ] || return 1
    [ -d "$candidate" ] || return 1
    local resolved
    resolved="$(readlink -f "$candidate" 2>/dev/null || echo "$candidate")"
    case "$resolved" in
        "$PROJECT_ROOT_REAL"/*/spec) return 0 ;;
        *) return 1 ;;
    esac
}

# --- Project Discovery ---
# Primary: check if cwd itself has a spec/ subdir with state
SPEC_PATH=""
STATE_FILE=""

# Also check if cwd IS the spec dir
if [ -f "$CWD/.spec-drive-state.json" ]; then
    SPEC_PATH="$CWD"
    STATE_FILE="$SPEC_PATH/.spec-drive-state.json"
elif [ -f "$CWD/spec/.spec-drive-state.json" ]; then
    SPEC_PATH="$CWD/spec"
    STATE_FILE="$SPEC_PATH/.spec-drive-state.json"
# Check parent dir (user might be in spec/ subdir)
elif [ -f "$(dirname "$CWD")/spec/.spec-drive-state.json" ] 2>/dev/null; then
    SPEC_PATH="$(dirname "$CWD")/spec"
    STATE_FILE="$SPEC_PATH/.spec-drive-state.json"
# Secondary: scan configured project root for active execution
elif [ -d "$PROJECT_ROOT" ]; then
    EXECUTION_MATCHES=()
    for dir in "$PROJECT_ROOT"/*/spec; do
        state="$dir/.spec-drive-state.json"
        if is_safe_spec_path "$dir" && [ -f "$state" ] && jq -e '.phase == "execution" and .awaitingApproval == false' "$state" >/dev/null 2>&1; then
            EXECUTION_MATCHES+=("$dir")
        fi
    done

    if [ "${#EXECUTION_MATCHES[@]}" -eq 1 ]; then
        SPEC_PATH="${EXECUTION_MATCHES[0]}"
        STATE_FILE="$SPEC_PATH/.spec-drive-state.json"
    elif [ "${#EXECUTION_MATCHES[@]}" -gt 1 ]; then
        cat <<EOF
## Ambiguous Active Spec

Multiple execution-phase specs were found under $PROJECT_ROOT_REAL.
Refusing to auto-resume the first match.

Use a cwd inside the intended project or narrow project discovery before resuming.
EOF
        exit 0
    fi

    # If no execution project found, check for auto mode in analysis phases
    if [ -z "$SPEC_PATH" ]; then
        AUTO_MATCHES=()
        for dir in "$PROJECT_ROOT"/*/spec; do
            state="$dir/.spec-drive-state.json"
            if is_safe_spec_path "$dir" && [ -f "$state" ] && jq -e '.mode == "auto" and .awaitingApproval == false' "$state" >/dev/null 2>&1; then
                AUTO_MATCHES+=("$dir")
            fi
        done

        if [ "${#AUTO_MATCHES[@]}" -eq 1 ]; then
            SPEC_PATH="${AUTO_MATCHES[0]}"
            STATE_FILE="$SPEC_PATH/.spec-drive-state.json"
        elif [ "${#AUTO_MATCHES[@]}" -gt 1 ]; then
            cat <<EOF
## Ambiguous Auto Spec

Multiple auto-mode specs were found under $PROJECT_ROOT_REAL.
Refusing to auto-continue without an explicit cwd-bound project.
EOF
            exit 0
        fi
    fi
fi

# No active project found — nothing to do
if [ -z "$SPEC_PATH" ] || [ -z "$STATE_FILE" ]; then
    exit 0
fi

if ! is_safe_spec_path "$SPEC_PATH"; then
    cat <<EOF
## Unsafe Spec Path

Resolved spec path is outside the approved project root:
$SPEC_PATH
EOF
    exit 0
fi

# --- State Validation ---
if ! jq empty "$STATE_FILE" 2>/dev/null; then
    cat <<'RECOVERY'
## Corrupt State Detected

The file `.spec-drive-state.json` is invalid JSON.

### Recovery Steps
1. Check git history: `git log --oneline -5 -- .spec-drive-state.json`
2. Restore last good version: `git checkout HEAD -- .spec-drive-state.json`
3. If no git history, manually reconstruct from `.progress.md` task checkmarks
4. Run `/spec-drive:status` to verify state after recovery
RECOVERY
    exit 0
fi

# --- Read State ---
NAME=$(jq -r '.name // "unknown"' "$STATE_FILE")
PHASE=$(jq -r '.phase // "unknown"' "$STATE_FILE")
MODE=$(jq -r '.mode // "normal"' "$STATE_FILE")
TASK_INDEX=$(jq -r '.taskIndex // 0' "$STATE_FILE")
TOTAL_TASKS=$(jq -r '.totalTasks // 0' "$STATE_FILE")
TASK_ITERATION=$(jq -r '.taskIteration // 1' "$STATE_FILE")
MAX_TASK_ITER=$(jq -r '.maxTaskIterations // 5' "$STATE_FILE")
GLOBAL_ITERATION=$(jq -r '.globalIteration // 1' "$STATE_FILE")
MAX_GLOBAL_ITER=$(jq -r '.maxGlobalIterations // 100' "$STATE_FILE")
AWAITING=$(jq -r '.awaitingApproval // false' "$STATE_FILE")

# --- Check transcript for ALL_TASKS_COMPLETE ---
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    if tail -100 "$TRANSCRIPT_PATH" 2>/dev/null | grep -q "ALL_TASKS_COMPLETE"; then
        exit 0
    fi
fi

# --- Check global iteration limit ---
if [ "$GLOBAL_ITERATION" -ge "$MAX_GLOBAL_ITER" ]; then
    cat <<EOF
## Iteration Limit Reached

Spec **$NAME** hit the global iteration cap ($GLOBAL_ITERATION/$MAX_GLOBAL_ITER).

This safety limit prevents infinite token burn. To continue:
1. Review .progress.md for stuck tasks
2. Increase maxGlobalIterations in .spec-drive-state.json if needed
3. Run /spec-drive:implement to resume
EOF
    exit 0
fi

# --- Skip if awaiting approval ---
if [ "$AWAITING" = "true" ]; then
    exit 0
fi

# --- Execution phase: output continuation prompt ---
if [ "$PHASE" = "execution" ] && [ "$TASK_INDEX" -lt "$TOTAL_TASKS" ]; then
    cat <<EOF
Continue spec: $NAME (Task $((TASK_INDEX + 1))/$TOTAL_TASKS, Iter $GLOBAL_ITERATION)

## State
Path: $SPEC_PATH | Index: $TASK_INDEX | Iteration: $TASK_ITERATION/$MAX_TASK_ITER

## Resume
1. Read $SPEC_PATH/.spec-drive-state.json and $SPEC_PATH/tasks.md
2. Delegate task $TASK_INDEX to executor (or qa-engineer for [VERIFY])
3. On TASK_COMPLETE: update state, advance
4. If taskIndex >= totalTasks: output ALL_TASKS_COMPLETE

## Critical
- Delegate via Task tool — do NOT implement yourself
- On failure: increment taskIteration, retry up to max
EOF
fi

# --- Auto mode: continue analysis phases ---
if [ "$MODE" = "auto" ] && [ "$PHASE" != "execution" ]; then
    # Determine next phase command
    NEXT_PHASE=""
    case "$PHASE" in
        idea)       NEXT_PHASE="research" ;;
        research)   NEXT_PHASE="requirements" ;;
        requirements) NEXT_PHASE="design" ;;
        design)     NEXT_PHASE="tasks" ;;
        tasks)      NEXT_PHASE="implement" ;;
    esac

    if [ -n "$NEXT_PHASE" ]; then
        cat <<EOF
Continue spec: $NAME (Auto mode — phase: $PHASE)

## Resume
1. Read $SPEC_PATH/.spec-drive-state.json
2. Run /spec-drive:$NEXT_PHASE to continue auto cycle
3. Validate phase checklist before proceeding
EOF
    fi
fi

# --- Cleanup orphaned .progress-task-*.md files older than 60 min ---
if is_safe_spec_path "$SPEC_PATH"; then
    find "$SPEC_PATH" -name ".progress-task-*.md" -mmin +60 -delete 2>/dev/null || true
fi

exit 0
