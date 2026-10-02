#!/usr/bin/env bash
# create-project.sh — atomically scaffold the required Spec-Drive project core.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: create-project.sh --projects-container PATH --project-slug SLUG --goal TEXT --mode normal|auto --research-depth standard|deep [--created-at ISO8601] [--result-format json]
EOF
}

die_usage() {
  printf 'create-project: %s\n' "$1" >&2
  usage
  exit 64
}

die_operational() {
  printf 'create-project: %s\n' "$1" >&2
  exit 1
}

projects_container=""
project_slug=""
goal=""
mode=""
research_depth=""
created_at=""
result_format="path"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --result-format)
      [ "$#" -ge 2 ] || die_usage "--result-format requires a value"
      [ "$2" = json ] || die_usage "--result-format must be json"
      result_format=json
      shift 2
      ;;
    --projects-container)
      [ "$#" -ge 2 ] || die_usage "--projects-container requires a value"
      projects_container="$2"
      shift 2
      ;;
    --project-slug)
      [ "$#" -ge 2 ] || die_usage "--project-slug requires a value"
      project_slug="$2"
      shift 2
      ;;
    --goal)
      [ "$#" -ge 2 ] || die_usage "--goal requires a value"
      goal="$2"
      shift 2
      ;;
    --mode)
      [ "$#" -ge 2 ] || die_usage "--mode requires a value"
      mode="$2"
      shift 2
      ;;
    --research-depth)
      [ "$#" -ge 2 ] || die_usage "--research-depth requires a value"
      research_depth="$2"
      shift 2
      ;;
    --created-at)
      [ "$#" -ge 2 ] || die_usage "--created-at requires a value"
      created_at="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die_usage "unexpected argument: $1"
      ;;
  esac
done

[ -n "$projects_container" ] || die_usage "missing --projects-container"
[ -n "$project_slug" ] || die_usage "missing --project-slug"
[ -n "$goal" ] || die_usage "missing --goal"
[ -n "$mode" ] || die_usage "missing --mode"
[ -n "$research_depth" ] || die_usage "missing --research-depth"

case "$project_slug" in
  "."|".."|*/*|*\\*|*" "*|*"	"*)
    die_usage "unsafe project slug: $project_slug"
    ;;
esac
case "$project_slug" in
  *[!A-Za-z0-9_.-]*)
    die_usage "unsafe project slug: $project_slug"
    ;;
esac

case "$mode" in
  normal|auto) ;;
  *) die_usage "--mode must be normal or auto" ;;
esac

case "$research_depth" in
  standard|deep) ;;
  *) die_usage "--research-depth must be standard or deep" ;;
esac

if [ -z "$created_at" ]; then
  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
fi

if ! command -v jq >/dev/null 2>&1; then
  die_operational "jq is required"
fi
if ! command -v git >/dev/null 2>&1; then
  die_operational "git is required"
fi
if [ "$result_format" = json ] && ! command -v python3 >/dev/null 2>&1; then
  die_operational "python3 is required for no-clobber publication"
fi

mkdir -p "$projects_container" || die_operational "could not create projects container: $projects_container"
projects_container="$(cd "$projects_container" && pwd -P)" || die_operational "could not resolve projects container"
destination="$projects_container/$project_slug"

if [ "$result_format" = path ] && { [ -e "$destination" ] || [ -L "$destination" ]; }; then
  printf 'create-project: destination already exists: %s\n' "$destination" >&2
  exit 2
fi

emit_result() {
  jq -cn --arg path "$destination" --arg outcome "$1" --arg phase "${2:-}" \
    '{path: $path, outcome: $outcome} + (if $phase == "" then {} else {phase: $phase} end)'
}

conflict() {
  printf 'create-project: %s: %s\n' "$1" "$2" >&2
  jq -cn --arg path "$destination" --arg code "$1" --arg artifact "$2" \
    '{path: $path, outcome: "conflict", error: {code: $code, path: $artifact}}'
  exit 2
}

# Atomic exclusive directory rename on the supported Linux/macOS platforms.
# Plain mv may nest the source in a concurrently created destination directory.
publish_directory() {
  local status=0
  python3 - "$1" "$2" <<'PY' || status=$?
import ctypes, errno, os, sys
libc = ctypes.CDLL(None, use_errno=True)
source, target = map(os.fsencode, sys.argv[1:])
if sys.platform == "darwin":
    result = libc.renamex_np(source, target, 4)  # RENAME_EXCL
elif sys.platform.startswith("linux") and hasattr(libc, "renameat2"):
    result = libc.renameat2(-100, source, -100, target, 1)  # RENAME_NOREPLACE
else:
    sys.exit(1)
if result:
    sys.exit(2 if ctypes.get_errno() in (errno.EEXIST, errno.ENOTEMPTY) else 1)
PY
  case "$status" in
    0) ;;
    2) conflict concurrent-change "$3" ;;
    *) die_operational "could not publish directory: $3" ;;
  esac
}

# Classification is read-only. Reject links before reading canonical paths,
# including dangling links (which test -e alone does not detect).
classify() {
  classification=absent
  phase=""
  [ ! -L "$destination" ] || conflict wrong-path-type .
  [ -e "$destination" ] || return 0
  [ -d "$destination" ] || conflict wrong-path-type .
  classification=adoptable
  local rel root config state initial missing later
  for rel in spec .git; do
    [ ! -L "$destination/$rel" ] || conflict wrong-path-type "$rel"
    if [ -e "$destination/$rel" ] && [ ! -d "$destination/$rel" ] &&
       { [ "$rel" != .git ] || [ ! -f "$destination/$rel" ]; }; then
      conflict wrong-path-type "$rel"
    fi
  done
  for rel in .spec-drive-config.json spec/.spec-drive-state.json spec/idea.md spec/.progress.md \
    spec/research.md spec/requirements.md spec/design.md spec/tasks.md; do
    [ ! -L "$destination/$rel" ] || conflict wrong-path-type "$rel"
    if [ -e "$destination/$rel" ] && [ ! -f "$destination/$rel" ]; then
      conflict wrong-path-type "$rel"
    fi
  done
  root="$(git -C "$destination" rev-parse --show-toplevel 2>/dev/null)" || root=""
  if [ -n "$root" ]; then
    [ "$root" = "$destination" ] || conflict git-root-mismatch .git
  elif [ -e "$destination/.git" ]; then
    conflict git-root-mismatch .git
  fi
  config="$destination/.spec-drive-config.json"
  state="$destination/spec/.spec-drive-state.json"
  if [ -f "$config" ]; then
    jq -e -s 'length == 1 and (.[0] | type == "object" and .scope == "project" and (.projectSlug | type == "string"))' "$config" >/dev/null 2>&1 \
      || conflict invalid-config .spec-drive-config.json
    jq -e --arg slug "$project_slug" '.projectSlug == $slug' "$config" >/dev/null \
      || conflict identity-mismatch .spec-drive-config.json
  fi
  for rel in idea.md .progress.md; do
    if [ -f "$destination/spec/$rel" ]; then
      awk -v slug="$project_slug" 'NR == 1 { if ($0 != "---") exit; next }
        $0 == "---" { exit }
        $0 == "spec: \"" slug "\"" || $0 == "spec: " slug { identity=1 }
        END { exit !identity }' "$destination/spec/$rel" \
        || conflict identity-mismatch "spec/$rel"
    fi
  done
  initial=true
  if [ -f "$state" ]; then
    jq -e -s 'length == 1 and (.[0] | type == "object" and
      (.phase | IN("idea", "research", "requirements", "design", "tasks", "execution", "completed")) and
      (if has("awaitingApproval") then (.awaitingApproval | type == "boolean") else true end) and
      (if has("mode") then (.mode | IN("normal", "auto")) else true end) and
      (if has("researchDepth") then (.researchDepth | IN("standard", "deep")) else true end))' "$state" >/dev/null 2>&1 \
      || conflict invalid-state spec/.spec-drive-state.json
    jq -e --arg slug "$project_slug" --arg base "$destination/spec" '.name == $slug and .basePath == $base' "$state" >/dev/null \
      || conflict identity-mismatch spec/.spec-drive-state.json
    phase="$(jq -r '.phase' "$state")"
    jq -e '(.phase == "idea" or .phase == "research") and .awaitingApproval == false and
      .taskIndex == 0 and .totalTasks == 0 and .taskIteration == 1 and .globalIteration == 1 and .taskResults == {}' "$state" >/dev/null \
      || initial=false
    rel=""
    case "$phase" in
      # Historical default is false; use it only for routing, never persist it.
      research) if jq -e '.awaitingApproval // false' "$state" >/dev/null; then rel=research.md; fi ;;
      requirements|design|tasks) rel="$phase.md" ;;
      execution|completed) rel=tasks.md ;;
    esac
    if [ -n "$rel" ] && [ ! -f "$destination/spec/$rel" ]; then
      conflict phase-artifact-missing "spec/$rel"
    fi
  fi
  missing=false
  for rel in .spec-drive-config.json spec/idea.md spec/.progress.md spec/.spec-drive-state.json .git; do
    [ -e "$destination/$rel" ] || missing=true
  done
  if [ "$missing" = false ]; then
    classification=resumable
    return
  fi
  [ "$initial" = true ] || conflict phase-artifact-missing spec
  # Later canonical work with incomplete identity/state must never be reset to
  # initial research. Standalone research in an otherwise uninitialized folder
  # is background material, not evidence of approval.
  later=false
  for rel in requirements.md design.md tasks.md; do
    [ ! -f "$destination/spec/$rel" ] || later=true
  done
  if [ -f "$destination/spec/research.md" ] && { [ -f "$config" ] || [ -f "$state" ] ||
    [ -f "$destination/spec/idea.md" ] || [ -f "$destination/spec/.progress.md" ]; }; then
    later=true
  fi
  [ "$later" = false ] || conflict invalid-state spec/.spec-drive-state.json
  for rel in idea.md .progress.md; do
    if [ -f "$destination/spec/$rel" ]; then
      # Only initial frontmatter establishes identity for an auto-completable
      # partial; the body is user material and is never compared to a template.
      awk -v slug="$project_slug" 'NR == 1 { if ($0 != "---") exit; next }
        $0 == "---" { exit }
        $0 == "spec: \"" slug "\"" || $0 == "spec: " slug { identity=1 }
        $0 == "phase: idea" { initial=1 }
        END { exit !(identity && initial) }' "$destination/spec/$rel" \
        || conflict identity-mismatch "spec/$rel"
    fi
  done
}

classification=absent
if [ "$result_format" = json ]; then
  classify
  if [ "$classification" = resumable ]; then
    emit_result resumable "$phase"
    exit 0
  fi
fi

staging=""
temporary=""
cleanup() {
  if [ -n "$temporary" ]; then rm -f "$temporary"; fi
  if [ -n "$staging" ] && [ -d "$staging" ]; then
    rm -rf "$staging"
  fi
}
trap cleanup EXIT HUP INT TERM

staging="$(mktemp -d "$projects_container/.spec-drive-new.XXXXXXXX")" || die_operational "could not create staging directory"
spec_dir="$staging/spec"
mkdir -p "$spec_dir" || die_operational "could not create staged spec directory"

jq -n \
  --arg scope "project" \
  --arg projectSlug "$project_slug" \
  '{scope: $scope, projectSlug: $projectSlug}' >"$staging/.spec-drive-config.json" \
  || die_operational "could not write project config"

cat >"$spec_dir/idea.md" <<EOF
---
spec: "$project_slug"
phase: idea
created: "$created_at"
---

# Idea: $project_slug

## Vision

$goal

## Constraints

<!-- User should fill constraints. Leave section with placeholder comment for now. -->
EOF

cat >"$spec_dir/.progress.md" <<EOF
---
spec: "$project_slug"
phase: idea
created: "$created_at"
---

# Progress: $project_slug

## Original Goal

$goal

## Completed Tasks

## Current Task

Research phase starting

## Learnings

## Blockers

None currently

## Next

Research phase
EOF

jq -n \
  --arg name "$project_slug" \
  --arg basePath "$destination/spec" \
  --arg phase "research" \
  --arg mode "$mode" \
  --arg researchDepth "$research_depth" \
  '{
    name: $name,
    basePath: $basePath,
    phase: $phase,
    mode: $mode,
    researchDepth: $researchDepth,
    taskIndex: 0,
    totalTasks: 0,
    taskIteration: 1,
    maxTaskIterations: 5,
    globalIteration: 1,
    maxGlobalIterations: 100,
    awaitingApproval: false,
    taskResults: {}
  }' >"$spec_dir/.spec-drive-state.json" \
  || die_operational "could not write state file"

if [ "${SPEC_DRIVE_CREATE_PROJECT_FAIL_AFTER:-}" = "write" ]; then
  die_operational "injected failure after write"
fi

jq -e 'keys == ["projectSlug", "scope"] and .scope == "project" and (.projectSlug | type == "string" and length > 0)' "$staging/.spec-drive-config.json" >/dev/null \
  || die_operational "project config validation failed"
jq empty "$spec_dir/.spec-drive-state.json" >/dev/null \
  || die_operational "state JSON validation failed"
jq -e --arg name "$project_slug" --arg basePath "$destination/spec" --arg mode "$mode" --arg researchDepth "$research_depth" \
  '.name == $name and .basePath == $basePath and .phase == "research" and .mode == $mode and .researchDepth == $researchDepth and .awaitingApproval == false and (.taskResults | type == "object")' \
  "$spec_dir/.spec-drive-state.json" >/dev/null \
  || die_operational "state contract validation failed"

grep -q '^spec: "' "$spec_dir/idea.md" || die_operational "idea frontmatter validation failed"
grep -q '^phase: idea$' "$spec_dir/idea.md" || die_operational "idea phase validation failed"
grep -q '^spec: "' "$spec_dir/.progress.md" || die_operational "progress frontmatter validation failed"
grep -q '^phase: idea$' "$spec_dir/.progress.md" || die_operational "progress phase validation failed"

for optional_dir in audit input output; do
  if [ -e "$staging/$optional_dir" ]; then
    die_operational "optional directory was created unexpectedly: $optional_dir"
  fi
done

if [ "${SPEC_DRIVE_CREATE_PROJECT_FAIL_AFTER:-}" = "validate" ]; then
  die_operational "injected failure after validate"
fi

(cd "$staging" && git init -q) || die_operational "git initialization failed"

if [ "${SPEC_DRIVE_CREATE_PROJECT_FAIL_AFTER:-}" = "git" ]; then
  die_operational "injected failure after git"
fi

if [ "$classification" = adoptable ]; then
  # Recheck just before publishing, then link sibling temporary files to their
  # exact final names. link() cannot overwrite a file, directory or symlink.
  classify
  [ "$classification" = adoptable ] || conflict concurrent-change .
  missing_artifacts=""
  missing_git=false
  [ -e "$destination/.git" ] || missing_git=true
  for rel in .spec-drive-config.json spec/idea.md spec/.progress.md spec/.spec-drive-state.json; do
    if [ ! -e "$destination/$rel" ]; then missing_artifacts="$missing_artifacts $rel"; fi
  done
  if [ ! -d "$destination/spec" ]; then
    mkdir "$destination/spec" || conflict concurrent-change spec
  fi
  for rel in $missing_artifacts; do
      [ ! -L "$destination" ] && [ ! -L "$destination/spec" ] || conflict concurrent-change spec
      parent="$destination"
      case "$rel" in spec/*) parent="$destination/spec" ;; esac
      temporary="$(mktemp "$parent/.spec-drive-file.XXXXXXXX")" || die_operational "could not create artifact temporary"
      cat "$staging/$rel" >"$temporary" || die_operational "could not prepare artifact: $rel"
      python3 - "$temporary" "$destination/$rel" <<'PY' || conflict concurrent-change "$rel"
import os, sys
os.link(sys.argv[1], sys.argv[2], follow_symlinks=False)
PY
      rm -f "$temporary"
      temporary=""
  done
  if [ "$missing_git" = true ]; then
    publish_directory "$staging/.git" "$destination/.git" .git
  fi
  emit_result adopted
  exit 0
fi

if [ -e "$destination" ] || [ -L "$destination" ]; then
  if [ "$result_format" = json ]; then conflict concurrent-change .; fi
  printf 'create-project: destination already exists: %s\n' "$destination" >&2
  exit 2
fi

if [ "$result_format" = path ]; then
  printf '%s\n' "$destination" || die_operational "could not write published project path"
fi
if [ "$result_format" = json ]; then
  publish_directory "$staging" "$destination" .
else
  mv "$staging" "$destination" || die_operational "could not publish project"
fi
staging=""
if [ "$result_format" = json ]; then emit_result created; fi
trap - EXIT HUP INT TERM
