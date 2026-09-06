#!/bin/bash
# Stop Hook for Spec-Drive
# Execution loop driver — detects active projects and outputs continuation prompts
# 1. Finds active project (cwd or ~/spec-drive-projects/)
# 2. Validates state file integrity
# 3. Checks for completion / iteration limits
# 4. Outputs continuation prompt for execution or auto mode
# 5. Cleans up orphaned temp progress files

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

# --- Read lifecycle metadata ---
NAME=$(jq -r '.name // "unknown"' "$STATE_FILE")
PHASE=$(jq -r '.phase // "unknown"' "$STATE_FILE")
MODE=$(jq -r '.mode // "normal"' "$STATE_FILE")
AWAITING=$(jq -r '.awaitingApproval // false' "$STATE_FILE")

# --- Skip if awaiting approval ---
if [ "$AWAITING" = "true" ]; then
    exit 0
fi

# --- Execution phase: ask the kernel to resume and describe its ledger ---
if [ "$PHASE" = "execution" ]; then
    # A pause only suppresses auto-resume while its ledger snapshot is current.
    # Explicit implementation may advance the ledger without deleting the historical marker.
    if jq -e '
        .paused != null
        and .paused.currentTaskId == (.currentTaskId // null)
        and .paused.currentStage == (.currentStage // "preflight")
        and .paused.activeAttemptId == (.activeAttemptId // null)
    ' "$STATE_FILE" >/dev/null 2>&1; then
        exit 0
    fi

    if [ ! -f "$KERNEL" ]; then
        echo "Spec-Drive execution kernel is unavailable at $KERNEL. Refusing legacy fallback."
        exit 0
    fi

    PROJECT_DIR="$(dirname "$SPEC_PATH")"
    REPO_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
    if [ -z "$REPO_ROOT" ]; then
        echo "Spec-Drive cannot resume $NAME: project is not inside a Git worktree."
        exit 0
    fi

    set +e
    RESUME_JSON=$(jq -n --arg specDir "$SPEC_PATH" --arg repoRoot "$REPO_ROOT" \
        '{op:"resume", specDir:$specDir, repoRoot:$repoRoot}' | node "$KERNEL" 2>/dev/null)
    RESUME_CODE=$?
    set -e
    if [ "$RESUME_CODE" -ne 0 ] || ! printf '%s' "$RESUME_JSON" | jq -e '.ok == true' >/dev/null 2>&1; then
        echo "Spec-Drive kernel resume requires attention for $NAME. Run /spec-drive:status, then /spec-drive:implement."
        exit 0
    fi

    # Resume may have completed one interrupted acceptance. Query status rather
    # than inferring completion or task identity from transcript/checkmarks.
    set +e
    STATUS_JSON=$(jq -n --arg specDir "$SPEC_PATH" '{op:"status", specDir:$specDir}' | node "$KERNEL" 2>/dev/null)
    STATUS_CODE=$?
    set -e
    if [ "$STATUS_CODE" -ne 0 ] || ! printf '%s' "$STATUS_JSON" | jq -e '.ok == true' >/dev/null 2>&1; then
        echo "Spec-Drive kernel status is unavailable for $NAME. Run /spec-drive:status."
        exit 0
    fi

    CURRENT_TASK=$(printf '%s' "$STATUS_JSON" | jq -r '.status.currentTaskId // "none"')
    CURRENT_STAGE=$(printf '%s' "$STATUS_JSON" | jq -r '.status.currentStage // "preflight"')
    GLOBAL_USED=$(printf '%s' "$STATUS_JSON" | jq -r '.status.budgets.globalBudgetUsed // 0')
    GLOBAL_MAX=$(printf '%s' "$STATUS_JSON" | jq -r '.status.budgets.maxGlobalOperations // 100')

    if [ "$CURRENT_STAGE" = "completed" ] && [ "$CURRENT_TASK" = "none" ]; then
        exit 0
    fi

    case "$CURRENT_STAGE" in
        indeterminate|recovery_required|blocked)
            cat <<EOF
Spec-Drive execution for $NAME requires recovery.

Kernel task: $CURRENT_TASK | Stage: $CURRENT_STAGE | Global budget: $GLOBAL_USED/$GLOBAL_MAX
Run /spec-drive:status. Do not redispatch until the kernel permits it.
EOF
            ;;
        *)
            cat <<EOF
Continue spec: $NAME

Kernel task: $CURRENT_TASK | Stage: $CURRENT_STAGE | Global budget: $GLOBAL_USED/$GLOBAL_MAX

Run /spec-drive:implement. It must continue with kernel resume/next/report/accept, use the returned taskId, and treat agent sentinels as non-authoritative.
EOF
            ;;
    esac
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
# Portable: avoid GNU-only find -mmin (not available on macOS/BSD).
# Strategy: list matching files, check mtime via python3 (preferred) or stat,
# fall through silently if neither is available.
if is_safe_spec_path "$SPEC_PATH"; then
    _cleanup_old_progress_files() {
        local spec_path="$1"
        local max_age_seconds=3600
        local file mtime now age

        # python3 path: most reliable cross-platform
        if command -v python3 >/dev/null 2>&1; then
            python3 - "$spec_path" "$max_age_seconds" <<'PYEOF' 2>/dev/null || true
import os, sys, glob, time
spec_path, max_age = sys.argv[1], int(sys.argv[2])
now = time.time()
for f in glob.glob(os.path.join(spec_path, ".progress-task-*.md")):
    try:
        if now - os.path.getmtime(f) > max_age:
            os.remove(f)
    except OSError:
        pass
PYEOF
            return
        fi

        # stat fallback: Linux uses -c %Y, macOS uses -f %m
        local stat_fmt
        if stat -c '%Y' /dev/null >/dev/null 2>&1; then
            stat_fmt="-c"
            stat_arg="%Y"
        elif stat -f '%m' /dev/null >/dev/null 2>&1; then
            stat_fmt="-f"
            stat_arg="%m"
        else
            return  # no supported mtime tool — skip gracefully
        fi

        now=$(date +%s 2>/dev/null) || return
        for file in "$spec_path"/.progress-task-*.md; do
            [ -f "$file" ] || continue
            mtime=$(stat "$stat_fmt" "$stat_arg" "$file" 2>/dev/null) || continue
            age=$(( now - mtime ))
            if [ "$age" -gt "$max_age_seconds" ]; then
                rm -f "$file" 2>/dev/null || true
            fi
        done
    }
    _cleanup_old_progress_files "$SPEC_PATH"
fi

exit 0
