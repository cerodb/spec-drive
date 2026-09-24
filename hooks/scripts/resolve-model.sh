#!/usr/bin/env bash
# Resolve a tier to an agent, subprocess, or inherited model mechanism.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/resolve-config.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
tier="${1:-}"
cli_arg="${2:-}"

emit_inherit() { printf 'mechanism=inherit\nmodel=\ncmd=\n'; }
emit_inherit_unresolved() {
    printf 'mechanism=inherit\nmodel=\ncmd=\nnote=model_used: inherit (unresolved:%s)\n' "$1"
}

# Unknown/absent tiers preserve the historical inherit behavior without probing
# configuration, including unrelated CLI configuration.
case "$tier" in light|standard|advanced|frontier) ;; *) emit_inherit; exit 0 ;; esac

detect_cli() {
    if [ -n "$cli_arg" ]; then printf '%s\n' "$cli_arg"; return; fi
    if command -v jq >/dev/null 2>&1; then
        local configured_cli resolve_status
        if configured_cli="$(spec_drive_resolve_value cli "$PWD")"; then
            if [ -n "$configured_cli" ] && [ "$configured_cli" != null ]; then printf '%s\n' "$configured_cli"; return; fi
        else
            resolve_status=$?
            [ "$resolve_status" -ne 3 ] || return 3
        fi
    fi
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || [ -n "${CLAUDECODE:-}" ]; then printf 'claude-code\n';
    elif [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_SANDBOX:-}" ]; then printf 'codex\n';
    else printf 'default\n'; fi
}

config_error() { printf 'error=invalid_profile\nreason=%s: %s\n' "$1" "$2" >&2; exit 1; }
if cli="$(detect_cli)"; then :; else
    detect_status=$?
    [ "$detect_status" -ne 3 ] || exit 3
    config_error resolver "CLI detection failed"
fi
# Validate before using the CLI value to construct a profile path or selector.
case "$cli" in ''|*[!A-Za-z0-9_.-]*) config_error resolver "invalid CLI identifier" ;; esac
command -v jq >/dev/null 2>&1 || config_error resolver "jq is required"

local_profile="${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/profiles.local.json"
cli_profile="$PLUGIN_ROOT/profiles/$cli.json"
default_profile="$PLUGIN_ROOT/profiles/default.json"

escape_controls() {
    # Encode control bytes so metadata and diagnostics remain one physical line.
    LC_ALL=C od -An -v -t u1 | awk '{for(i=1;i<=NF;i++){n=$i+0;if(n==10)printf "\\n";else if(n==13)printf "\\r";else if(n==9)printf "\\t";else if(n<32||n==127)printf "\\x%02x",n;else printf "%c",n}}'
}
safe() { printf '%s' "$1" | escape_controls; }
profile_error() { config_error "$(safe "$1")" "$(safe "$2")"; }

validate_profile_file() {
    local file="$1"
    [ -f "$file" ] || return 1
    jq empty "$file" >/dev/null 2>&1 || profile_error "$file" "invalid JSON"
    jq -e 'type == "object"' "$file" >/dev/null 2>&1 || profile_error "$file" "profile root must be an object"
}

# Prints a JSON value if the selector exists; absence is represented by no
# output. A present null/empty/wrong-typed value is retained for validation at
# selection time, allowing a complete new override to outrank legacy damage.
lookup_profile() {
    local file="$1" selector="$2"
    [ -f "$file" ] || return 1
    validate_profile_file "$file" || return 1
    local result
    result="$(jq -c --arg selector "$selector" '
      def walk($p): if ($p|length)==0 then {state:"found",value:.}
        elif type!="object" then {state:"bad"}
        elif has($p[0]) then .[$p[0]]|walk($p[1:])
        else {state:"absent"} end;
      walk($selector|split("."))
    ' "$file")"
    case "$result" in
        '{"state":"bad"}') profile_error "$file#$selector" "selected profile path has an invalid container type" ;;
        '{"state":"absent"}') return 1 ;;
        *) jq -c '.value' <<<"$result" ;;
    esac
}

local_new="" local_legacy="" cli_entry="" default_entry=""
local_new_source="$local_profile#profiles.$cli.$tier"
local_legacy_source="$local_profile#$tier"
cli_source="$cli_profile#$tier"
default_source="$default_profile#$tier"
if [ -f "$local_profile" ]; then
    validate_profile_file "$local_profile"
    local_new="$(lookup_profile "$local_profile" "profiles.$cli.$tier" || true)"
    local_legacy="$(lookup_profile "$local_profile" "$tier" || true)"
    if [ -n "$local_legacy" ]; then
        printf 'warning=legacy_global_override\n' >&2
        printf 'reason=%s contains a global tier override; convert manually by placing each intended CLI override under profiles.<cli>.<tier>. No values were copied or displayed.\n' "$(safe "$local_profile")" >&2
    fi
fi

# A complete scoped value wins before reading lower-priority profiles. For a
# partial value, lower profiles are read only to find and validate its base.
entry="" source="" base_source=""
if [ -n "$local_new" ] && [ "$(jq -r 'type=="object" and has("model") and ((keys-["model"]|length)==0)' <<<"$local_new")" = true ]; then
    selected_kind=partial
else
    selected_kind=complete
fi
if [ -n "$local_new" ] && [ "$selected_kind" = complete ]; then
    entry="$local_new"; source="$local_new_source"
elif [ -n "$local_new" ]; then
    # Partial overrides require a compatible local legacy, CLI, or default base.
    if [ -n "$local_legacy" ]; then entry="$local_legacy"; base_source="$local_legacy_source"
    else
        cli_entry="$(lookup_profile "$cli_profile" "$tier" || true)"
        if [ -n "$cli_entry" ]; then entry="$cli_entry"; base_source="$cli_source"
        else default_entry="$(lookup_profile "$default_profile" "$tier" || true)"; entry="$default_entry"; base_source="$default_source"; fi
    fi
    source="$local_new_source"
else
    if [ -n "$local_legacy" ]; then entry="$local_legacy"; source="$local_legacy_source"
    else
        cli_entry="$(lookup_profile "$cli_profile" "$tier" || true)"
        if [ -n "$cli_entry" ]; then entry="$cli_entry"; source="$cli_source"
        else default_entry="$(lookup_profile "$default_profile" "$tier" || true)"; entry="$default_entry"; source="$default_source"; fi
    fi
fi
if [ -z "$entry" ]; then emit_inherit_unresolved "$tier"; exit 0; fi

is_model_only() { jq -e 'type=="object" and has("model") and ((keys-["model"]|length)==0)' <<<"$1" >/dev/null 2>&1; }
validate_model() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]] || profile_error "$2" "model must match ^[A-Za-z0-9][A-Za-z0-9._:/-]*$"
}
validate_entry() {
    local value="$1" src="$2" mechanism model cmd
    jq -e 'type=="object" and (.mechanism|type)=="string"' <<<"$value" >/dev/null 2>&1 || profile_error "$src" "entry must be an object with a mechanism"
    mechanism="$(jq -r '.mechanism' <<<"$value")"
    model="$(jq -r '.model // empty' <<<"$value")"
    cmd="$(jq -r '.cmd // empty' <<<"$value")"
    case "$mechanism" in agent|subprocess|inherit) ;; *) profile_error "$src" "unsupported mechanism" ;; esac
    if jq -e 'has("model")' <<<"$value" >/dev/null; then
        jq -e '.model|type=="string"' <<<"$value" >/dev/null 2>&1 || profile_error "$src" "model must be a string"
        validate_model "$model" "$src"
    fi
    if jq -e 'has("cmd")' <<<"$value" >/dev/null; then
        jq -e '.cmd|type=="string"' <<<"$value" >/dev/null 2>&1 || profile_error "$src" "cmd must be a string"
        local control
        control="$(printf '%s' "$cmd" | LC_ALL=C grep -n '[[:cntrl:]]' || true)"
        [ -z "$control" ] || profile_error "$src" "cmd must not contain control characters"
    fi
    if [ "$mechanism" = subprocess ]; then
        case "$cmd" in *'{prompt}'*) profile_error "$src" "inline {prompt} is not supported; use {promptfile}" ;; esac
        case "$cmd" in *'{promptfile}'*) ;; *) profile_error "$src" "subprocess cmd template must consume {promptfile}" ;; esac
        if [[ "$cmd" == *'{promptfile}'* ]]; then
            [[ "$cmd" =~ (^|[[:space:]])\{promptfile\}($|[[:space:]]) ]] || profile_error "$src" "{promptfile} must occupy a complete command argument"
        fi
        if [[ "$cmd" == *'{MODEL}'* ]]; then
            [[ "$cmd" =~ (^|[[:space:]])\{MODEL\}($|[[:space:]]) ]] || profile_error "$src" "{MODEL} must occupy a complete command argument"
            [ -n "$model" ] || profile_error "$src" "{MODEL} requires an explicit model"
            cmd="${cmd//\{MODEL\}/$model}"
        fi
        case "$cmd" in *'{CMD}'*|*'{MODEL}'*) profile_error "$src" "unresolved subprocess placeholder" ;; esac
    elif [[ "$cmd" == *'{'* || "$cmd" == *'}'* ]]; then
        profile_error "$src" "placeholders require a subprocess mechanism"
    fi
    printf '%s\n%s\n%s\n' "$mechanism" "$model" "$cmd"
}

if [ -n "$local_new" ] && [ "$selected_kind" = partial ]; then
    model="$(jq -r '.model' <<<"$local_new")"
    jq -e '.model|type=="string"' <<<"$local_new" >/dev/null 2>&1 || profile_error "$source" "model must be a string"
    validate_model "$model" "$source"
    base_mechanism_raw="$(jq -r '.mechanism // empty' <<<"$entry" 2>/dev/null || true)"
    if [ "$base_mechanism_raw" = subprocess ]; then
        base_cmd_raw="$(jq -r '.cmd // empty' <<<"$entry")"
        [[ "$base_cmd_raw" =~ (^|[[:space:]])\{MODEL\}($|[[:space:]]) ]] || profile_error "$base_source" "partial override requires a standalone {MODEL} argument in its subprocess base"
    fi
    base_mechanism="$base_mechanism_raw"
    case "$base_mechanism" in agent|subprocess) ;; *) profile_error "$base_source" "model-only override cannot inherit mechanism" ;; esac
    base_json="$(jq -c --arg model "$model" '. + {model:$model}' <<<"$entry")"
    resolved="$(validate_entry "$base_json" "$base_source")"
else
    resolved="$(validate_entry "$entry" "$source")"
fi
mechanism="$(printf '%s\n' "$resolved" | sed -n '1p')"
model="$(printf '%s\n' "$resolved" | sed -n '2p')"
cmd="$(printf '%s\n' "$resolved" | sed -n '3p')"
printf 'mechanism=%s\nmodel=%s\ncmd=%s\ncli=%s\ntier=%s\nsource=%s\n' \
    "$(safe "$mechanism")" "$(safe "$model")" "$(safe "$cmd")" \
    "$(safe "$cli")" "$(safe "$tier")" "$(safe "$source")"
[ -z "$base_source" ] || printf 'base_source=%s\n' "$(safe "$base_source")"
