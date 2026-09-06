#!/usr/bin/env bash
# test-schema.sh — Validate spec-drive state and config schemas
set -euo pipefail


echo "-- Model-router schema stability (PG115)..."
if jq -e '((.properties // {}) | has("model") or has("model_used") or has("modelRouter") or has("modelProfiles") or has("routingProfiles") or has("profiles")) | not' schemas/spec-drive.schema.json >/dev/null; then
  echo "  OK: model routing does not add state-schema properties"
else
  echo "  FAIL: model routing must not add state-schema properties"
  exit 1
fi

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

SCHEMA="schemas/spec-drive.schema.json"
CONFIG_SCHEMA="schemas/spec-drive-config.schema.json"
PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  echo "  OK: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

assert_runtime_config_status() {
  local path="$1"
  local expected_status="$2"
  local label="$3"
  local output status

  set +e
  output="$(bash -c '. hooks/scripts/resolve-config.sh; spec_drive_validate_config_file "$1"' bash "$path" 2>&1)"
  status=$?
  set -e

  if [ "$status" -eq "$expected_status" ]; then
    ok "$label"
  else
    fail "$label (expected exit $expected_status, got $status)"
    if [ -n "$output" ]; then
      printf '    %s\n' "$output"
    fi
  fi
}

echo "=== Spec-Drive Schema Test ==="

# 1. Schema is valid JSON
echo "-- JSON validity..."
if jq empty "$SCHEMA" 2>/dev/null; then
  ok "schema is valid JSON"
else
  fail "schema is not valid JSON"
  echo "Passed: $PASS | Failed: $FAIL"
  exit 1
fi

# 2. Has "properties" key
echo "-- Required keys..."
if jq -e '.properties' "$SCHEMA" >/dev/null 2>&1; then
  ok "has 'properties' key"
else
  fail "missing 'properties' key"
fi

# 3. Has "phase" property with enum
echo "-- Phase property..."
if jq -e '.properties.phase' "$SCHEMA" >/dev/null 2>&1; then
  ok "has 'phase' property"
else
  fail "missing 'phase' property"
fi

if jq -e '.properties.phase.enum' "$SCHEMA" >/dev/null 2>&1; then
  ok "phase has enum"
  # Verify all expected phases
  PHASES=$(jq -r '.properties.phase.enum[]' "$SCHEMA" | sort | tr '\n' ' ')
  echo "    phases: $PHASES"
if jq -e '.properties.phase.enum | index("completed")' "$SCHEMA" >/dev/null 2>&1; then
    ok "phase enum includes completed"
  else
    fail "phase enum missing completed"
  fi
else
  fail "phase missing enum"
fi

if jq -e '.properties.researchDepth.type == "string" and (.properties.researchDepth.enum | index("standard")) and (.properties.researchDepth.enum | index("deep")) and .properties.researchDepth.default == "standard"' "$SCHEMA" >/dev/null 2>&1; then
  ok "researchDepth documents standard/deep scaffold defaults"
else
  fail "researchDepth missing or does not match scaffold defaults"
fi

# 4. Has "mode" property
echo "-- Mode property..."
if jq -e '.properties.mode' "$SCHEMA" >/dev/null 2>&1; then
  ok "has 'mode' property"
else
  fail "missing 'mode' property"
fi

# 5. Has taskIndex, totalTasks, awaitingApproval
echo "-- Execution state properties..."
for prop in taskIndex totalTasks awaitingApproval; do
  if jq -e ".properties.$prop" "$SCHEMA" >/dev/null 2>&1; then
    ok "has '$prop' property"
  else
    fail "missing '$prop' property"
  fi
done

# 6. Has requirementsSha and designSha staleness fields
echo "-- Staleness SHA fields..."
if jq -e '.properties.requirementsSha' "$SCHEMA" >/dev/null 2>&1; then
  ok "has 'requirementsSha' property"
else
  fail "missing 'requirementsSha' property"
fi

if jq -e '.properties.requirementsSha.type == "string"' "$SCHEMA" >/dev/null 2>&1; then
  ok "requirementsSha is type string"
else
  fail "requirementsSha is not type string"
fi

if jq -e '.properties.requirementsSha.description | test("requirements\\.md")' "$SCHEMA" >/dev/null 2>&1; then
  ok "requirementsSha description references requirements.md"
else
  fail "requirementsSha description missing requirements.md reference"
fi

if jq -e '.properties.designSha' "$SCHEMA" >/dev/null 2>&1; then
  ok "has 'designSha' property"
else
  fail "missing 'designSha' property"
fi

if jq -e '.properties.designSha.type == "string"' "$SCHEMA" >/dev/null 2>&1; then
  ok "designSha is type string"
else
  fail "designSha is not type string"
fi

if jq -e '.properties.designSha.description | test("design\\.md")' "$SCHEMA" >/dev/null 2>&1; then
  ok "designSha description references design.md"
else
  fail "designSha description missing design.md reference"
fi

# 7. requirementsSha and designSha are NOT in required array (optional fields)
echo "-- SHA fields are optional..."
if jq -e '.required | index("requirementsSha") | not' "$SCHEMA" >/dev/null 2>&1; then
  ok "requirementsSha is optional (not in required)"
else
  fail "requirementsSha should not be in required array"
fi

if jq -e '.required | index("designSha") | not' "$SCHEMA" >/dev/null 2>&1; then
  ok "designSha is optional (not in required)"
else
  fail "designSha should not be in required array"
fi

# 8. Existing required properties unchanged
echo "-- Existing required properties unchanged..."
for prop in name basePath phase; do
  if jq -e ".required | index(\"$prop\")" "$SCHEMA" >/dev/null 2>&1; then
    ok "required still includes '$prop'"
  else
    fail "required missing '$prop'"
  fi
done

# 9. Coordinator state is optional but well-shaped
echo "-- Coordinator state..."
if jq -e '.properties.coordinator' "$SCHEMA" >/dev/null 2>&1; then
  ok "has optional coordinator property"
else
  fail "missing optional coordinator property"
fi

if jq -e '.properties.coordinator.properties.active.type == "boolean"' "$SCHEMA" >/dev/null 2>&1; then
  ok "coordinator.active is boolean"
else
  fail "coordinator.active missing or wrong type"
fi

if jq -e '.properties.coordinator.properties.mode.enum | index("clarification")' "$SCHEMA" >/dev/null 2>&1; then
  ok "coordinator.mode enum includes clarification"
else
  fail "coordinator.mode missing clarification"
fi

echo "-- Execution ledger persisted shapes..."
for stage in recovery_required blocked indeterminate intent_recorded target_verified_clean patch_applied target_verified target_committed completed; do
  if jq -e --arg stage "$stage" '.properties.currentStage.enum | index($stage)' "$SCHEMA" >/dev/null 2>&1; then
    ok "currentStage includes '$stage'"
  else
    fail "currentStage missing '$stage'"
  fi
done

if jq -e '."$defs".ownershipManifest.required == ["candidate", "status", "index"]' "$SCHEMA" >/dev/null 2>&1; then
  ok "ownership manifest requires candidate/status/index"
else
  fail "ownership manifest contract is incomplete"
fi

if jq -e '.properties.attempts.additionalProperties.properties.ownership.properties.beforeDispatch."$ref" == "#/$defs/ownershipManifest" and .properties.attempts.additionalProperties.properties.ownership.properties.afterReport."$ref" == "#/$defs/ownershipManifest"' "$SCHEMA" >/dev/null 2>&1; then
  ok "attempt ownership records beforeDispatch and afterReport manifests"
else
  fail "attempt ownership manifest properties are missing"
fi

if jq -e '.properties.attempts.additionalProperties.required | index("actor") and index("adapterStart")' "$SCHEMA" >/dev/null 2>&1; then
  ok "attempt schema requires real dispatch actor and adapterStart fields"
else
  fail "attempt schema does not require actor and adapterStart"
fi

if jq -e '.properties.attempts.additionalProperties.properties.report."$ref" == "#/$defs/reportRecord" and .properties.attempts.additionalProperties.properties.recovery."$ref" == "#/$defs/recoveryRecord"' "$SCHEMA" >/dev/null 2>&1; then
  ok "attempt schema documents report and recovery records"
else
  fail "attempt schema missing report or recovery records"
fi

if jq -e '."$defs".recoveryRecord.properties.previousState.enum | index("indeterminate") and index("reported_blocked")' "$SCHEMA" >/dev/null 2>&1; then
  ok "recovery record allows recovered indeterminate and env-blocked stages"
else
  fail "recovery record previousState enum is incomplete"
fi

if jq -e '.properties.paused."$ref" == "#/$defs/pausedState" and .properties.trackingProjection."$ref" == "#/$defs/trackingProjection"' "$SCHEMA" >/dev/null 2>&1; then
  ok "schema documents pause and tracking projection records"
else
  fail "schema missing paused or trackingProjection"
fi

if jq -e '.properties.approvals.additionalProperties.properties.taskDigests.additionalProperties.type == "string" and .properties.approvals.additionalProperties.properties.taskChecks.additionalProperties.type == "boolean"' "$SCHEMA" >/dev/null 2>&1; then
  ok "tasks approval metadata records per-task digests and checkbox state"
else
  fail "tasks approval metadata missing digest/check maps"
fi

if node - "$SCHEMA" <<'EOF_NODE'
const fs = require("fs");
const schema = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const props = schema.properties;
const defs = schema.$defs;
const representative = {
  dispatch: {
    currentTaskId: "1.1",
    currentStage: "dispatching",
    activeAttemptId: "attempt-1",
    taskOrder: ["1.1", "V1"],
    taskStates: {
      "1.1": {
        taskId: "1.1",
        status: "in_progress",
        required: true,
        attempts: ["attempt-1"],
        latestAttemptId: "attempt-1",
        dispatchFailures: 0,
        executionAttempts: 1,
      },
    },
    attempts: {
      "attempt-1": {
        attemptId: "attempt-1",
        taskId: "1.1",
        sequence: 1,
        dispatchBudgetUsed: 0,
        executionBudgetUsed: 1,
        globalBudgetUsed: 1,
        state: "dispatching",
        actor: "implement",
        adapterStart: "started",
        worktree: { path: "/tmp/wt", branch: "attempt-1", targetHeadAtCreate: "abc", files: ["src/a.txt"] },
      },
    },
  },
  report: {
    currentStage: "reported_complete",
    attempts: {
      "attempt-1": {
        report: {
          attemptId: "attempt-1",
          taskId: "1.1",
          outcome: "task_complete",
          startedWork: true,
          summary: "fixture report",
        },
      },
    },
  },
  recovery: {
    currentStage: "ready",
    attempts: {
      "attempt-1": {
        recovery: {
          evidence: "executor process tree confirmed ended",
          recoveredAt: "2026-09-06T00:00:00.000Z",
          previousState: "indeterminate",
          failureClass: "unknown_start",
        },
      },
    },
  },
  pause: {
    paused: {
      reason: "operator cancelled without deleting work",
      pausedAt: "2026-09-06T00:00:00.000Z",
      activeAttemptId: "attempt-1",
      currentTaskId: "1.1",
      currentStage: "dispatching",
    },
  },
};
if (!props.currentTaskId || !props.taskOrder || !props.taskStates || !props.attempts || !props.paused) process.exit(1);
if (!props.currentStage.enum.includes(representative.dispatch.currentStage)) process.exit(1);
if (!props.currentStage.enum.includes(representative.report.currentStage)) process.exit(1);
const taskProps = props.taskStates.additionalProperties.properties;
if (!taskProps.status.enum.includes(representative.dispatch.taskStates["1.1"].status)) process.exit(1);
if (taskProps.latestAttemptId.type !== "string") process.exit(1);
const attemptProps = props.attempts.additionalProperties.properties;
if (!attemptProps.state.enum.includes(representative.dispatch.attempts["attempt-1"].state)) process.exit(1);
if (attemptProps.report.$ref !== "#/$defs/reportRecord") process.exit(1);
if (attemptProps.recovery.$ref !== "#/$defs/recoveryRecord") process.exit(1);
if (props.paused.$ref !== "#/$defs/pausedState") process.exit(1);
if (!defs.reportRecord.properties.outcome.enum.includes(representative.report.attempts["attempt-1"].report.outcome)) process.exit(1);
if (!defs.recoveryRecord.properties.previousState.enum.includes(representative.recovery.attempts["attempt-1"].recovery.previousState)) process.exit(1);
if (!defs.recoveryRecord.properties.failureClass.enum.includes(representative.recovery.attempts["attempt-1"].recovery.failureClass)) process.exit(1);
for (const key of defs.pausedState.required) {
  if (!Object.prototype.hasOwnProperty.call(representative.pause.paused, key)) process.exit(1);
}
EOF_NODE
then
  ok "schema covers representative emitted dispatch/report/recovery/pause state fields"
else
  fail "schema does not cover representative emitted execution state fields"
fi

if jq -e '.required | index("coordinator") | not' "$SCHEMA" >/dev/null 2>&1; then
  ok "coordinator is optional"
else
  fail "coordinator should not be in required array"
fi

# 10. Backward-compatible state schema: no routing/model fields added
echo "-- Backward-compatible state schema..."
for prop in model model_used profile router; do
  if jq -e ".properties | has(\"$prop\") | not" "$SCHEMA" >/dev/null 2>&1; then
    ok "state schema does not add '$prop'"
  else
    fail "state schema should not add '$prop'"
  fi
done

# 11. Config schema is valid JSON and documents scoped shapes
echo "-- Config schema JSON validity..."
if jq empty "$CONFIG_SCHEMA" 2>/dev/null; then
  ok "config schema is valid JSON"
else
  fail "config schema is not valid JSON"
  echo "Passed: $PASS | Failed: $FAIL"
  exit 1
fi

echo "-- Config schema documented scopes..."
if jq -e '.oneOf | length == 3' "$CONFIG_SCHEMA" >/dev/null 2>&1; then
  ok "config schema documents three approved shapes"
else
  fail "config schema must document project, workspace, and legacy shapes"
fi

if jq -e '."$defs".projectConfig.required == ["scope", "projectSlug"]' "$CONFIG_SCHEMA" >/dev/null 2>&1; then
  ok "project scope requires scope and projectSlug"
else
  fail "project scope required fields are incorrect"
fi

if jq -e '."$defs".workspaceConfig.required == ["scope", "workspaceRoot", "projectsPath"]' "$CONFIG_SCHEMA" >/dev/null 2>&1; then
  ok "workspace scope requires scope, workspaceRoot, and projectsPath"
else
  fail "workspace scope required fields are incorrect"
fi

if jq -e '."$defs".legacyConfig.anyOf | length == 2' "$CONFIG_SCHEMA" >/dev/null 2>&1; then
  ok "legacy unscoped config requires projectRoot or cli"
else
  fail "legacy unscoped config contract is incomplete"
fi

echo "-- Config schema field restrictions..."
if jq -e '."$defs".projectConfig.additionalProperties == false' "$CONFIG_SCHEMA" >/dev/null 2>&1; then
  ok "project scope forbids undeclared fields"
else
  fail "project scope must forbid undeclared fields"
fi

if jq -e '."$defs".workspaceConfig.additionalProperties == false and ."$defs".legacyConfig.additionalProperties == false' "$CONFIG_SCHEMA" >/dev/null 2>&1; then
  ok "workspace and legacy scopes forbid undeclared fields"
else
  fail "workspace and legacy scopes must forbid undeclared fields"
fi

if jq -e '."$defs".projectConfig.properties | has("workspaceRoot") or has("projectsPath") or has("projectRoot") | not' "$CONFIG_SCHEMA" >/dev/null 2>&1; then
  ok "project scope omits non-portable topology keys"
else
  fail "project scope must not allow workspaceRoot, projectsPath, or projectRoot"
fi

if jq -e '
  ."$defs".safeProjectSlug.pattern as $pattern
  | ("P354b" | test($pattern))
    and ("portable.slug-1" | test($pattern))
    and ("." | test($pattern) | not)
    and (".." | test($pattern) | not)
    and ("bad slug" | test($pattern) | not)
' "$CONFIG_SCHEMA" >/dev/null 2>&1; then
  ok "projectSlug uses the safe ASCII slug contract"
else
  fail "projectSlug safe pattern does not enforce the documented contract"
fi

if jq -e '
  ."$defs".relativeProjectsPath.pattern as $pattern
  | ("." | test($pattern))
    and ("Projects" | test($pattern))
    and ("groups/Projects" | test($pattern))
    and ("/Projects" | test($pattern) | not)
    and ("../escape" | test($pattern) | not)
    and ("Projects/../escape" | test($pattern) | not)
    and ("Projects/.." | test($pattern) | not)
' "$CONFIG_SCHEMA" >/dev/null 2>&1; then
  ok "projectsPath pattern accepts normal relative paths and rejects lexical '..' escapes"
else
  fail "projectsPath pattern does not enforce the documented relative non-escaping contract"
fi

echo "-- Config schema sample shapes..."
if jq -e '
  .oneOf[0]."$ref" == "#/$defs/projectConfig"
  and .oneOf[1]."$ref" == "#/$defs/workspaceConfig"
  and .oneOf[2]."$ref" == "#/$defs/legacyConfig"
' "$CONFIG_SCHEMA" >/dev/null 2>&1; then
  ok "config schema root references the approved shape definitions"
else
  fail "config schema root shape references are incorrect"
fi

# Canonicalize: on macOS mktemp -d returns a /var symlink path, while the
# resolver reports the physical /private/var path it resolves to.
TMP_CONFIG_DIR="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP_CONFIG_DIR"' EXIT

WORKSPACE_ROOT="$TMP_CONFIG_DIR/workspace"
mkdir -p "$WORKSPACE_ROOT/Projects/P354b"

cat >"$TMP_CONFIG_DIR/project-valid.json" <<'EOF'
{"scope":"project","projectSlug":"P354b","cli":"codex"}
EOF
cat >"$TMP_CONFIG_DIR/project-invalid-topology.json" <<'EOF'
{"scope":"project","projectSlug":"P354b","workspaceRoot":"/tmp/workspace"}
EOF
cat >"$TMP_CONFIG_DIR/project-invalid-slug.json" <<'EOF'
{"scope":"project","projectSlug":"bad slug"}
EOF
cat >"$TMP_CONFIG_DIR/project-invalid-unknown.json" <<'EOF'
{"scope":"project","projectSlug":"safe-slug","unexpected":true}
EOF
cat >"$TMP_CONFIG_DIR/project-output-portable.json" <<'EOF'
{"scope":"project","projectSlug":"portable-slug"}
EOF
cat >"$TMP_CONFIG_DIR/legacy-valid.json" <<'EOF'
{"projectRoot":"./spec-drive-projects","cli":"claude-code"}
EOF
cat >"$TMP_CONFIG_DIR/legacy-invalid-empty-root.json" <<'EOF'
{"projectRoot":""}
EOF
cat >"$TMP_CONFIG_DIR/legacy-invalid-scope.json" <<'EOF'
{"scope":"legacy","projectRoot":"./spec-drive-projects"}
EOF
cat >"$TMP_CONFIG_DIR/legacy-invalid-empty.json" <<'EOF'
{}
EOF
cat >"$TMP_CONFIG_DIR/legacy-invalid-cli-type.json" <<'EOF'
{"cli":42}
EOF

cat >"$TMP_CONFIG_DIR/workspace-valid.json" <<EOF
{"scope":"workspace","workspaceRoot":"$WORKSPACE_ROOT","projectsPath":"Projects","cli":"codex"}
EOF
cat >"$TMP_CONFIG_DIR/workspace-valid-flat.json" <<EOF
{"scope":"workspace","workspaceRoot":"$WORKSPACE_ROOT","projectsPath":"."}
EOF
cat >"$TMP_CONFIG_DIR/workspace-invalid-absolute.json" <<EOF
{"scope":"workspace","workspaceRoot":"$WORKSPACE_ROOT","projectsPath":"/Projects"}
EOF
cat >"$TMP_CONFIG_DIR/workspace-invalid-escape.json" <<EOF
{"scope":"workspace","workspaceRoot":"$WORKSPACE_ROOT","projectsPath":"../escape"}
EOF
cat >"$TMP_CONFIG_DIR/workspace-invalid-root-type.json" <<'EOF'
{"scope":"workspace","workspaceRoot":42,"projectsPath":"Projects"}
EOF
cat >"$TMP_CONFIG_DIR/workspace-invalid-dotdot-segment.json" <<EOF
{"scope":"workspace","workspaceRoot":"$WORKSPACE_ROOT","projectsPath":"Projects/../elsewhere"}
EOF
cat >"$TMP_CONFIG_DIR/workspace-valid-nested.json" <<EOF
{"scope":"workspace","workspaceRoot":"$WORKSPACE_ROOT","projectsPath":"groups/Projects"}
EOF

if jq -e '.scope == "project" and .projectSlug == "P354b" and .cli == "codex"' "$TMP_CONFIG_DIR/project-valid.json" >/dev/null 2>&1; then
  ok "project sample JSON matches the documented portable shape"
else
  fail "project sample JSON does not match the documented portable shape"
fi

if jq -e 'keys == ["projectSlug", "scope"] and (. | has("workspaceRoot") or has("projectsPath") or has("projectRoot") | not)' "$TMP_CONFIG_DIR/project-output-portable.json" >/dev/null 2>&1; then
  ok "portable project output omits workspaceRoot, projectsPath, and projectRoot"
else
  fail "portable project output should contain only scope and projectSlug"
fi

if jq -e '.scope == "workspace" and .workspaceRoot == $root and .projectsPath == "Projects"' --arg root "$WORKSPACE_ROOT" "$TMP_CONFIG_DIR/workspace-valid.json" >/dev/null 2>&1; then
  ok "workspace sample JSON matches the documented scoped topology"
else
  fail "workspace sample JSON does not match the documented scoped topology"
fi

if jq -e '.projectRoot == "./spec-drive-projects" and .cli == "claude-code" and (has("scope") | not)' "$TMP_CONFIG_DIR/legacy-valid.json" >/dev/null 2>&1; then
  ok "legacy sample JSON stays unscoped"
else
  fail "legacy sample JSON should remain unscoped"
fi

echo "-- jq-based runtime validator enforcement..."
assert_runtime_config_status "$TMP_CONFIG_DIR/project-valid.json" 0 "runtime accepts scoped project config with portable override"
assert_runtime_config_status "$TMP_CONFIG_DIR/workspace-valid.json" 0 "runtime accepts scoped workspace config"
assert_runtime_config_status "$TMP_CONFIG_DIR/workspace-valid-flat.json" 0 "runtime accepts projectsPath='.' for flat workspaces"
assert_runtime_config_status "$TMP_CONFIG_DIR/workspace-valid-nested.json" 0 "runtime accepts nested relative projectsPath values"
assert_runtime_config_status "$TMP_CONFIG_DIR/legacy-valid.json" 0 "runtime accepts supported legacy unscoped config"
assert_runtime_config_status "$TMP_CONFIG_DIR/project-invalid-topology.json" 3 "runtime rejects project-scope topology keys"
assert_runtime_config_status "$TMP_CONFIG_DIR/project-invalid-slug.json" 3 "runtime rejects unsafe projectSlug values"
assert_runtime_config_status "$TMP_CONFIG_DIR/project-invalid-unknown.json" 3 "runtime rejects undeclared project fields"
assert_runtime_config_status "$TMP_CONFIG_DIR/workspace-invalid-absolute.json" 3 "runtime rejects absolute projectsPath values"
assert_runtime_config_status "$TMP_CONFIG_DIR/workspace-invalid-escape.json" 3 "runtime rejects projectsPath values that escape workspaceRoot"
assert_runtime_config_status "$TMP_CONFIG_DIR/workspace-invalid-root-type.json" 3 "runtime rejects non-string workspaceRoot values"
assert_runtime_config_status "$TMP_CONFIG_DIR/workspace-invalid-dotdot-segment.json" 3 "runtime rejects lexical '..' projectsPath segments"
assert_runtime_config_status "$TMP_CONFIG_DIR/legacy-invalid-empty-root.json" 3 "runtime rejects empty legacy projectRoot"
assert_runtime_config_status "$TMP_CONFIG_DIR/legacy-invalid-scope.json" 3 "runtime rejects unsupported scope values"
assert_runtime_config_status "$TMP_CONFIG_DIR/legacy-invalid-empty.json" 3 "runtime rejects empty legacy config"
assert_runtime_config_status "$TMP_CONFIG_DIR/legacy-invalid-cli-type.json" 3 "runtime rejects non-string legacy cli values"

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
