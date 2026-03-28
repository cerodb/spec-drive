#!/bin/bash
# SessionStart Hook for Spec-Drive
# Detects active project on session start and outputs context to stderr
# 1. Finds active project (cwd or ~/spec-drive-projects/)
# 2. Outputs phase, task progress, approval status
# 3. Suggests next command if awaiting approval
# 4. Shows original goal from .progress.md

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

# Default project root (overridable via config)
CONFIG_FILE="${HOME}/.spec-drive-config.json"
if [ -f "$CONFIG_FILE" ] && jq empty "$CONFIG_FILE" 2>/dev/null; then
    PROJECT_ROOT=$(jq -r '.projectRoot // "'"${HOME}/spec-drive-projects"'"' "$CONFIG_FILE" 2>/dev/null || echo "${HOME}/spec-drive-projects")
else
    PROJECT_ROOT="${HOME}/spec-drive-projects"
fi

# --- Project Discovery (same as stop-watcher) ---
SPEC_PATH=""
STATE_FILE=""

# Check if cwd IS the spec dir
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
elif [ -d "$PROJECT_ROOT" ]; then
    # Find any project with a state file (not just execution phase)
    for dir in "$PROJECT_ROOT"/*/spec; do
        state="$dir/.spec-drive-state.json"
        if [ -f "$state" ] && jq empty "$state" 2>/dev/null; then
            SPEC_PATH="$dir"
            STATE_FILE="$state"
            break
        fi
    done
fi

# No active project found
if [ -z "$SPEC_PATH" ] || [ -z "$STATE_FILE" ]; then
    exit 0
fi

# Validate state file
if ! jq empty "$STATE_FILE" 2>/dev/null; then
    echo "[spec-drive] WARNING: Corrupt .spec-drive-state.json detected. Run /spec-drive:status for recovery." >&2
    exit 0
fi

# --- Read State ---
NAME=$(jq -r '.name // "unknown"' "$STATE_FILE")
PHASE=$(jq -r '.phase // "unknown"' "$STATE_FILE")
MODE=$(jq -r '.mode // "normal"' "$STATE_FILE")
TASK_INDEX=$(jq -r '.taskIndex // 0' "$STATE_FILE")
TOTAL_TASKS=$(jq -r '.totalTasks // 0' "$STATE_FILE")
AWAITING=$(jq -r '.awaitingApproval // false' "$STATE_FILE")

# --- Output Status ---
echo "[spec-drive] Active project: $NAME" >&2
echo "[spec-drive] Phase: $PHASE | Mode: $MODE" >&2

if [ "$PHASE" = "execution" ]; then
    echo "[spec-drive] Task progress: $((TASK_INDEX + 1))/$TOTAL_TASKS" >&2
fi

echo "[spec-drive] Awaiting approval: $AWAITING" >&2

# --- Suggest Next Command ---
if [ "$AWAITING" = "true" ]; then
    case "$PHASE" in
        idea)
            echo "[spec-drive] Idea ready for review. Run /spec-drive:research to continue." >&2
            ;;
        research)
            echo "[spec-drive] Research complete. Run /spec-drive:requirements to continue." >&2
            ;;
        requirements)
            echo "[spec-drive] Requirements complete. Run /spec-drive:design to continue." >&2
            ;;
        design)
            echo "[spec-drive] Design complete. Run /spec-drive:tasks to continue." >&2
            ;;
        tasks)
            echo "[spec-drive] Tasks planned. Run /spec-drive:implement to start execution." >&2
            ;;
    esac
elif [ "$PHASE" = "execution" ] && [ "$TASK_INDEX" -lt "$TOTAL_TASKS" ]; then
    echo "[spec-drive] Execution in progress. Run /spec-drive:implement to continue." >&2
fi

# --- Output Original Goal from .progress.md ---
PROGRESS_FILE="$SPEC_PATH/.progress.md"
if [ -f "$PROGRESS_FILE" ]; then
    # Extract goal: first non-empty line after "## Original Goal"
    GOAL=$(awk '/^## Original Goal/{found=1; next} found && /^[^ \t#]/{print; exit} found && /^## /{exit}' "$PROGRESS_FILE" 2>/dev/null || true)
    if [ -n "$GOAL" ]; then
        echo "[spec-drive] Goal: $GOAL" >&2
    fi
fi

exit 0
