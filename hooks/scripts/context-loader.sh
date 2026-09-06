#!/bin/bash
# SessionStart Hook for Spec-Drive
# Detects active project on session start and outputs context to stderr
# 1. Finds active project (cwd or ~/spec-drive-projects/)
# 2. Outputs phase, task progress, approval status
# 3. Suggests next command if awaiting approval
# 4. Shows original goal from .progress.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/resolve-config.sh"
KERNEL="$SCRIPT_DIR/execution-kernel.mjs"

# Read hook input from stdin
INPUT=$(cat)

# Bail out cleanly if jq is unavailable
command -v jq >/dev/null 2>&1 || exit 0

# Get working directory (guard against parse failures)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -z "$CWD" ]; then
    exit 0
fi

# Default project root (overridable via workspace or XDG config)
PROJECT_ROOT="$(spec_drive_resolve_project_root "$CWD")"

PROJECT_ROOT_REAL="$(portable_realpath "$PROJECT_ROOT")"

is_safe_spec_path() {
    local candidate="$1"
    [ -n "$candidate" ] || return 1
    [ -d "$candidate" ] || return 1
    local resolved
    resolved="$(portable_realpath "$candidate")"
    case "$resolved" in
        "$PROJECT_ROOT_REAL"/*/spec) return 0 ;;
        *) return 1 ;;
    esac
}

# --- Project Discovery (same guards as stop-watcher) ---
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
    # Find projects with state files — detect ambiguity
    MATCHES=()
    for dir in "$PROJECT_ROOT"/*/spec; do
        state="$dir/.spec-drive-state.json"
        if is_safe_spec_path "$dir" && [ -f "$state" ] && jq empty "$state" 2>/dev/null; then
            MATCHES+=("$dir")
        fi
    done

    if [ "${#MATCHES[@]}" -eq 1 ]; then
        SPEC_PATH="${MATCHES[0]}"
        STATE_FILE="$SPEC_PATH/.spec-drive-state.json"
    elif [ "${#MATCHES[@]}" -gt 1 ]; then
        echo "[spec-drive] WARNING: Multiple active projects found. Use cwd inside a specific project." >&2
        for m in "${MATCHES[@]}"; do
            local_name=$(jq -r '.name // "unknown"' "$m/.spec-drive-state.json" 2>/dev/null || echo "unknown")
            echo "[spec-drive]   - $local_name ($m)" >&2
        done
        exit 0
    fi
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

# --- Read lifecycle metadata and kernel-owned execution status ---
NAME=$(jq -r '.name // "unknown"' "$STATE_FILE")
PHASE=$(jq -r '.phase // "unknown"' "$STATE_FILE")
MODE=$(jq -r '.mode // "normal"' "$STATE_FILE")
AWAITING=$(jq -r '.awaitingApproval // false' "$STATE_FILE")

KERNEL_STATUS=""
if [ -f "$KERNEL" ]; then
    set +e
    KERNEL_STATUS=$(jq -n --arg specDir "$SPEC_PATH" '{op:"status", specDir:$specDir}' | node "$KERNEL" 2>/dev/null)
    KERNEL_STATUS_CODE=$?
    set -e
    if [ "$KERNEL_STATUS_CODE" -ne 0 ] || ! printf '%s' "$KERNEL_STATUS" | jq -e '.ok == true and (.status | type == "object")' >/dev/null 2>&1; then
        echo "[spec-drive] WARNING: Execution status unavailable from kernel. Run /spec-drive:status." >&2
        KERNEL_STATUS=""
    fi
fi

# --- Output Status ---
echo "[spec-drive] Active project: $NAME" >&2
echo "[spec-drive] Phase: $PHASE | Mode: $MODE" >&2

if [ "$PHASE" = "execution" ]; then
    if [ -z "$KERNEL_STATUS" ]; then
        echo "[spec-drive] Execution status unavailable; refusing ordinal fallback." >&2
    else
        CURRENT_TASK=$(printf '%s' "$KERNEL_STATUS" | jq -r '.status.currentTaskId // "none"')
        CURRENT_STAGE=$(printf '%s' "$KERNEL_STATUS" | jq -r '.status.currentStage // "preflight"')
        ACCEPTED_TASKS=$(printf '%s' "$KERNEL_STATUS" | jq '[.status.taskStates[]? | select(.status == "accepted")] | length')
        TOTAL_TASKS=$(printf '%s' "$KERNEL_STATUS" | jq '.status.taskOrder | length')
        GLOBAL_USED=$(printf '%s' "$KERNEL_STATUS" | jq -r '.status.budgets.globalBudgetUsed // 0')
        GLOBAL_MAX=$(printf '%s' "$KERNEL_STATUS" | jq -r '.status.budgets.maxGlobalOperations // 100')
        echo "[spec-drive] Task: $CURRENT_TASK | Stage: $CURRENT_STAGE | Accepted: $ACCEPTED_TASKS/$TOTAL_TASKS" >&2
        echo "[spec-drive] Global budget: $GLOBAL_USED/$GLOBAL_MAX" >&2
    fi
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
elif [ "$PHASE" = "execution" ] && [ -n "$KERNEL_STATUS" ]; then
    if [ "$CURRENT_STAGE" = "completed" ] && [ "$CURRENT_TASK" = "none" ]; then
        echo "[spec-drive] Execution completed by kernel." >&2
    elif [ "$CURRENT_STAGE" = "indeterminate" ] || [ "$CURRENT_STAGE" = "recovery_required" ]; then
        echo "[spec-drive] Execution requires explicit recovery. Run /spec-drive:status." >&2
    else
        echo "[spec-drive] Execution in progress. Run /spec-drive:implement to resume through the kernel." >&2
    fi
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
