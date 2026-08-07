#!/usr/bin/env bash
# create-project.sh — atomically scaffold the required Spec-Drive project core.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: create-project.sh --projects-container PATH --project-slug SLUG --goal TEXT --mode normal|auto --research-depth standard|deep [--created-at ISO8601]
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

while [ "$#" -gt 0 ]; do
  case "$1" in
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

mkdir -p "$projects_container" || die_operational "could not create projects container: $projects_container"
projects_container="$(cd "$projects_container" && pwd -P)" || die_operational "could not resolve projects container"
destination="$projects_container/$project_slug"

if [ -e "$destination" ]; then
  printf 'create-project: destination already exists: %s\n' "$destination" >&2
  exit 2
fi

staging=""
cleanup() {
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

if [ -e "$destination" ]; then
  printf 'create-project: destination already exists: %s\n' "$destination" >&2
  exit 2
fi

mv "$staging" "$destination" || die_operational "could not publish project"
staging=""
trap - EXIT HUP INT TERM
printf '%s\n' "$destination"
