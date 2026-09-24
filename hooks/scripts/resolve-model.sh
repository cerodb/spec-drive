#!/usr/bin/env bash
# resolve-model.sh — tier -> {mechanism, model, cmd} resolver
#
# Usage: resolve-model.sh <tier> [cli]
#   tier — light|standard|advanced|frontier. Any other value (unknown/absent)
#          resolves to mechanism=inherit (backward compat, AC-5.1/AC-5.2).
#   cli  — optional CLI id (claude-code|codex|coda|...). If omitted, the CLI
#          is detected from the resolved .spec-drive-config.json `cli` field
#          (see resolve-config.sh), else environment autodetection, else the
#          generic "default" profile.
#
# Resolution order per tier (FR-18):
#   ~/.config/spec-drive/profiles.local.json (XDG override, never committed)
#   -> profiles/<cli>.json                   (shipped per-CLI profile)
#   -> profiles/default.json                 (generic fallback)
#
# Output (key=value stdout, one per line):
#   mechanism=<agent|subprocess|inherit>
#   model=<id or empty>
#   cmd=<template or empty; subprocess templates leave {promptfile} unresolved>
#   cli=<selected CLI>, tier=<tier>, source=<file#selector>, base_source=<inherited base>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/resolve-config.sh"

# profiles/ ships two directories above hooks/scripts/ at the plugin/repo root.
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

tier="${1:-}"
cli_arg="${2:-}"

emit_inherit() {
    printf 'mechanism=inherit\n'
    printf 'model=\n'
    printf 'cmd=\n'
}

# emit_inherit_unresolved — tier was known but no profile (local/CLI/default) had
# an entry for it. Falls back to inherit per FR-18 / design "Error Handling",
# and records a note so callers can tell this apart from the plain
# unknown-tier backward-compat path (which never hard-fails a run).
emit_inherit_unresolved() {
    local t="$1"
    printf 'mechanism=inherit\n'
    printf 'model=\n'
    printf 'cmd=\n'
    printf 'note=model_used: inherit (unresolved:%s)\n' "$t"
}

case "$tier" in
    light|standard|advanced|frontier) ;;
    *)
        emit_inherit
        exit 0
        ;;
esac

# --- CLI detection -----------------------------------------------------
detect_cli() {
    # 1. Explicit arg wins.
    if [ -n "$cli_arg" ]; then
        printf '%s\n' "$cli_arg"
        return 0
    fi

    # 2. `cli` field resolved per key from project/workspace/XDG config.
    if command -v jq >/dev/null 2>&1; then
        local configured_cli resolve_status
        if configured_cli="$(spec_drive_resolve_value cli "$PWD")"; then
            if [ -n "$configured_cli" ] && [ "$configured_cli" != "null" ]; then
                printf '%s\n' "$configured_cli"
                return 0
            fi
        else
            resolve_status=$?
            if [ "$resolve_status" -eq 3 ]; then
                return "$resolve_status"
            fi
        fi
    fi

    # 3. Environment autodetection.
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || [ -n "${CLAUDECODE:-}" ]; then
        printf 'claude-code\n'
        return 0
    fi
    if [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_SANDBOX:-}" ]; then
        printf 'codex\n'
        return 0
    fi

    # 4. Fallback — generic profile.
    printf 'default\n'
}

cli="$(detect_cli)"

# --- Profile lookup ------------------------------------------------------
local_profile="${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/profiles.local.json"
cli_profile="$PLUGIN_ROOT/profiles/$cli.json"
default_profile="$PLUGIN_ROOT/profiles/default.json"

config_error() {
    printf 'error=invalid_profile\n' >&2
    printf 'reason=%s: %s\n' "$1" "$2" >&2
    exit 1
}

# Keep profile ids from becoming path traversal, and require jq for the JSON
# contract rather than silently treating unreadable configuration as absent.
case "$cli" in
    ''|*[!A-Za-z0-9_.-]*) config_error "CLI '$cli'" "invalid CLI identifier" ;;
esac
command -v jq >/dev/null 2>&1 || config_error "resolver" "jq is required"

read_profile() {
    local file="$1" selector="$2" outvar="$3"
    [ -f "$file" ] || return 1
    jq empty "$file" >/dev/null 2>&1 || config_error "$file" "invalid JSON"
    jq -e 'type == "object"' "$file" >/dev/null 2>&1 || config_error "$file" "profile root must be an object"
    if ! jq -e --arg selector "$selector" '
        def haspath($p):
            if ($p | length) == 0 then true
            elif type != "object" then false
            else . as $obj | ($p[0] as $key | ($obj | has($key)) and ($obj[$key] | haspath($p[1:])))
            end;
        haspath($selector | split("."))
    ' "$file" >/dev/null 2>&1; then
        return 1
    fi
    local value
    value="$(jq -c --arg selector "$selector" 'getpath($selector | split("."))' "$file")"
    [ "$value" != "null" ] || config_error "$file#$selector" "explicit null entry"
    printf -v "$outvar" '%s' "$value"
    return 0
}

local_new="" local_legacy="" cli_entry="" default_entry=""
local_new_source="$local_profile#profiles.$cli.$tier"
local_legacy_source="$local_profile#$tier"
cli_source="$cli_profile#$tier"
default_source="$default_profile#$tier"

if [ -f "$local_profile" ]; then
    jq empty "$local_profile" >/dev/null 2>&1 || config_error "$local_profile" "invalid JSON"
    jq -e 'type == "object"' "$local_profile" >/dev/null 2>&1 || config_error "$local_profile" "profile root must be an object"
    # A new override is only considered for the selected CLI/tier.
    if read_profile "$local_profile" "profiles.$cli.$tier" local_new; then :; fi
    if read_profile "$local_profile" "$tier" local_legacy; then :; fi
    if [ -n "$local_legacy" ]; then
        printf 'warning=legacy_global_override\n' >&2
        printf 'reason=%s has a global %s override; copy it to profiles.%s.%s to scope it (no automatic migration)\n' "$local_profile" "$tier" "$cli" "$tier" >&2
    fi
fi
if read_profile "$cli_profile" "$tier" cli_entry; then :; fi
if read_profile "$default_profile" "$tier" default_entry; then :; fi

is_model_only() {
    jq -e 'type == "object" and has("model") and ((keys - ["model"]) | length == 0)' <<<"$1" >/dev/null 2>&1
}
validate_model() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]] || config_error "$2" "model must match ^[A-Za-z0-9][A-Za-z0-9._:/-]*$"
}
validate_entry() {
    local value="$1" source="$2" mechanism model cmd
    jq -e 'type == "object" and ((.mechanism | type) == "string")' <<<"$value" >/dev/null 2>&1 || config_error "$source" "entry must be an object with a mechanism"
    mechanism="$(jq -r '.mechanism' <<<"$value")"
    model="$(jq -r '.model // empty' <<<"$value")"
    cmd="$(jq -r '.cmd // empty' <<<"$value")"
    case "$cmd" in *$'\n'*|*$'\r'*) config_error "$source" "cmd must be a single line" ;; esac
    case "$mechanism" in agent|subprocess|inherit) ;; *) config_error "$source" "unsupported mechanism" ;; esac
    if jq -e 'has("model")' <<<"$value" >/dev/null 2>&1; then validate_model "$model" "$source"; fi
    if [ "$mechanism" = subprocess ]; then
        case "$cmd" in *'{prompt}'*) config_error "$source" "inline {prompt} is not supported; use {promptfile}" ;; esac
        case "$cmd" in *'{promptfile}'*) ;; *) config_error "$source" "subprocess cmd template must consume {promptfile}" ;; esac
        if [[ "$cmd" == *'{MODEL}'* ]]; then
            [[ "$cmd" =~ (^|[[:space:]])\{MODEL\}($|[[:space:]]) ]] || config_error "$source" "{MODEL} must occupy a complete command argument"
            if [ -z "$model" ]; then
                printf 'error=unresolved_placeholder\n' >&2
                printf 'reason=%s still contains {MODEL} without an explicit model\n' "$source" >&2
                exit 1
            fi
            cmd="${cmd//\{MODEL\}/$model}"
        fi
        case "$cmd" in *'{CMD}'*|*'{MODEL}'*) printf 'error=unresolved_placeholder\n' >&2; printf 'reason=%s contains an unresolved subprocess placeholder\n' "$source" >&2; exit 1 ;; esac
    fi
    printf '%s\n' "$mechanism" "$model" "$cmd"
}

entry="" source="" base_source=""
if [ -n "$local_new" ]; then
    source="$local_new_source"
    if is_model_only "$local_new"; then
        model="$(jq -r '.model' <<<"$local_new")"
        validate_model "$model" "$source"
        base_entry="$local_legacy"; base_source="$local_legacy_source"
        if [ -z "$base_entry" ]; then base_entry="$cli_entry"; base_source="$cli_source"; fi
        if [ -z "$base_entry" ]; then base_entry="$default_entry"; base_source="$default_source"; fi
        [ -n "$base_entry" ] || config_error "$source" "model-only override has no compatible base entry"
        base_mechanism="$(jq -r '.mechanism' <<<"$base_entry")"
        base_cmd="$(jq -r '.cmd // empty' <<<"$base_entry")"
        case "$base_mechanism" in
            agent)
                jq -e 'type == "object" and ((.mechanism | type) == "string")' <<<"$base_entry" >/dev/null 2>&1 || config_error "$base_source" "base entry must be an object with a mechanism"
                entry="$(jq -c --arg model "$model" '. + {model:$model}' <<<"$base_entry")"
                ;;
            subprocess)
                jq -e 'type == "object" and ((.mechanism | type) == "string")' <<<"$base_entry" >/dev/null 2>&1 || config_error "$base_source" "base entry must be an object with a mechanism"
                [[ "$base_cmd" =~ (^|[[:space:]])\{MODEL\}($|[[:space:]]) ]] || config_error "$base_source" "model-only override requires a subprocess template with a standalone {MODEL} argument"
                case "$base_cmd" in *'{prompt}'*) config_error "$base_source" "inline {prompt} is not supported; use {promptfile}" ;; esac
                case "$base_cmd" in *'{promptfile}'*) ;; *) config_error "$base_source" "subprocess cmd template must consume {promptfile}" ;; esac
                entry="$(jq -c --arg model "$model" '. + {model:$model}' <<<"$base_entry")"
                ;;
            *) config_error "$base_source" "model-only override cannot inherit mechanism '$base_mechanism'" ;;
        esac
    else
        entry="$local_new"
    fi
elif [ -n "$local_legacy" ]; then entry="$local_legacy"; source="$local_legacy_source"
elif [ -n "$cli_entry" ]; then entry="$cli_entry"; source="$cli_source"
elif [ -n "$default_entry" ]; then entry="$default_entry"; source="$default_source"
else emit_inherit_unresolved "$tier"; exit 0
fi

resolved="$(validate_entry "$entry" "$source")"
mechanism="$(printf '%s\n' "$resolved" | sed -n '1p')"
model="$(printf '%s\n' "$resolved" | sed -n '2p')"
cmd="$(printf '%s\n' "$resolved" | sed -n '3p')"
printf 'mechanism=%s\nmodel=%s\ncmd=%s\ncli=%s\ntier=%s\nsource=%s\n' "$mechanism" "$model" "$cmd" "$cli" "$tier" "$source"
[ -n "$base_source" ] && printf 'base_source=%s\n' "$base_source"
