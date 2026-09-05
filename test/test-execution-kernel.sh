#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="$ROOT_DIR/hooks/scripts/execution-kernel.mjs"
TMP_ROOT="$ROOT_DIR/test/.tmp-kernel"

fail() {
  echo "ASSERTION FAILED: $*" >&2
  exit 1
}

assert_json_ok() {
  node -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); if (p.ok !== true) process.exit(1)' "$1" \
    || fail "expected ok JSON in $1"
}

assert_json_error_contains() {
  local file="$1"
  local needle="$2"
  node -e '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const text = JSON.stringify(p);
    if (p.ok !== false || !text.includes(process.argv[2]) || Object.prototype.hasOwnProperty.call(p, "dispatch")) {
      process.exit(1);
    }
  ' "$file" "$needle" || fail "expected error containing '$needle' and no dispatch in $file"
}

kernel_json() {
  local input="$1"
  local stdout="$2"
  local stderr="$3"
  set +e
  node "$KERNEL" < "$input" > "$stdout" 2> "$stderr"
  local status=$?
  set -e
  return "$status"
}

sha_file() {
  node -e 'const fs=require("fs"), crypto=require("crypto"); process.stdout.write(crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))' "$1"
}

write_fixture() {
  local dir="$1"
  mkdir -p "$dir/spec" "$dir/repo/src"
  cat > "$dir/spec/requirements.md" <<'EOF_REQ'
---
spec: "fixture"
phase: requirements
status: "complete"
---

# Requirements: fixture

## User Stories

#### US-1: Valid gate
**Acceptance Criteria:**
- [ ] AC-1.1: Valid plans pass preflight.
- [ ] AC-1.2: Invalid references block dispatch.

## Functional Requirements

| ID | Description | Priority | Verification |
|----|-------------|----------|--------------|
| FR-1 | Kernel validates plans before dispatch. | High | Gate fixture |

## Non-Functional Requirements

- NFR-1: Diagnostics remain CLI-portable JSON plus stderr.
EOF_REQ

  local req_sha
  req_sha="$(sha_file "$dir/spec/requirements.md")"
  cat > "$dir/spec/design.md" <<EOF_DESIGN
---
spec: "fixture"
phase: design
status: "complete"
requirements_sha: "$req_sha"
---

# Design: fixture

## Coverage

| Source | Design target |
|---|---|
| AC-1.1 | Artifact Gate |
| AC-1.2 | Artifact Gate |
| FR-1 | Artifact Gate |
| NFR-1 | Portable Protocol |
EOF_DESIGN

  local design_sha
  design_sha="$(sha_file "$dir/spec/design.md")"
  cat > "$dir/spec/tasks.md" <<EOF_TASKS
---
spec: "fixture"
phase: tasks
status: "complete"
requirements_sha: "$req_sha"
design_sha: "$design_sha"
---

# Tasks: fixture

## Phase 1

- [ ] 1.1 Create gate
  - **Do**: Parse artifacts and stop invalid plans before dispatch.
  - **Files**: src/gate.txt
  - **Traces**: AC-1.1, FR-1, NFR-1
  - **model**: advanced
  - **Cwd**: .
  - **Done when**: Valid plan passes.
  - **Verify**: test -f src/gate.txt
  - **Timeout**: 120
  - **Commit**: feat: gate

- [ ] V1 [VERIFY] Check gate
  - **Do**: Check the local gate.
  - **Files**: none
  - **Traces**: AC-1.2
  - **Cwd**: .
  - **Done when**: Invalid plans fail.
  - **Verify**: test ! -f src/dispatch.txt
  - **Timeout**: 120
  - **Commit**: none
EOF_TASKS
}

approve_all() {
  local dir="$1"
  local artifact sha input out err
  for artifact in requirements design tasks; do
    sha="$(sha_file "$dir/spec/$artifact.md")"
    input="$dir/approve-$artifact.json"
    out="$dir/approve-$artifact.out"
    err="$dir/approve-$artifact.err"
    node -e '
      const fs = require("fs");
      fs.writeFileSync(process.argv[1], JSON.stringify({
        op: "approve",
        specDir: process.argv[2],
        artifact: process.argv[3],
        expectedSha256: process.argv[4],
        approvalEvidence: "Gab approved fixture"
      }));
    ' "$input" "$dir/spec" "$artifact" "$sha"
    kernel_json "$input" "$out" "$err" || fail "approve $artifact failed: $(cat "$err")"
    assert_json_ok "$out"
  done
}

run_preflight() {
  local dir="$1"
  local input="$dir/preflight.json"
  node -e '
    const fs = require("fs");
    fs.writeFileSync(process.argv[1], JSON.stringify({
      op: "preflight",
      specDir: process.argv[2],
      repoRoot: process.argv[3]
    }));
  ' "$input" "$dir/spec" "$dir/repo"
  kernel_json "$input" "$dir/preflight.out" "$dir/preflight.err"
}

run_next() {
  local dir="$1"
  local name="$2"
  local input="$dir/next-$name.json"
  node -e '
    const fs = require("fs");
    fs.writeFileSync(process.argv[1], JSON.stringify({
      op: "next",
      specDir: process.argv[2],
      repoRoot: process.argv[3],
      actor: "implement"
    }));
  ' "$input" "$dir/spec" "$dir/repo"
  kernel_json "$input" "$dir/next-$name.out" "$dir/next-$name.err"
}

run_resume() {
  local dir="$1"
  local name="$2"
  local input="$dir/resume-$name.json"
  node -e '
    const fs = require("fs");
    fs.writeFileSync(process.argv[1], JSON.stringify({
      op: "resume",
      specDir: process.argv[2],
      repoRoot: process.argv[3]
    }));
  ' "$input" "$dir/spec" "$dir/repo"
  kernel_json "$input" "$dir/resume-$name.out" "$dir/resume-$name.err"
}

run_report() {
  local dir="$1"
  local name="$2"
  local attempt_id="$3"
  local task_id="$4"
  local outcome="$5"
  local failure_class="$6"
  local adapter_evidence="$7"
  local started_work="$8"
  local input="$dir/report-$name.json"
  node -e '
    const fs = require("fs");
    const failureClass = process.argv[6];
    const report = {
      attemptId: process.argv[3],
      taskId: process.argv[4],
      outcome: process.argv[5],
      startedWork: process.argv[8] === "true",
      summary: "fixture report"
    };
    if (failureClass !== "none") report.failureClass = failureClass;
    fs.writeFileSync(process.argv[1], JSON.stringify({
      op: "report",
      specDir: process.argv[2],
      repoRoot: process.argv[9],
      attemptId: process.argv[3],
      adapterEvidence: process.argv[7],
      report
    }));
  ' "$input" "$dir/spec" "$attempt_id" "$task_id" "$outcome" "$failure_class" "$adapter_evidence" "$started_work" "$dir/repo"
  kernel_json "$input" "$dir/report-$name.out" "$dir/report-$name.err"
}

json_get() {
  node -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const path=process.argv[2].split("."); let v=p; for (const key of path) v=v[key]; process.stdout.write(String(v));' "$1" "$2"
}

assert_state_schema_core() {
  local state_file="$1"
  local schema_file="$ROOT_DIR/schemas/spec-drive.schema.json"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const schema = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    for (const key of schema.required) {
      if (typeof state[key] !== schema.properties[key].type || state[key].trim() === "") {
        process.exit(1);
      }
    }
    const phaseEnum = schema.properties.phase.enum;
    if (!phaseEnum.includes(state.phase)) process.exit(1);
    if (Object.prototype.hasOwnProperty.call(state, "__fresh")) process.exit(1);
    if (state.budgets) {
      for (const [key, def] of Object.entries(schema.properties.budgets.properties)) {
        const value = state.budgets[key];
        if (!Number.isSafeInteger(value) || (def.minimum !== undefined && value < def.minimum)) {
          process.exit(1);
        }
      }
    }
    for (const [taskId, task] of Object.entries(state.taskStates || {})) {
      if (!Number.isSafeInteger(task.dispatchFailures) || task.dispatchFailures < 0) process.exit(1);
      if (!Number.isSafeInteger(task.executionAttempts) || task.executionAttempts < 0) process.exit(1);
      if (!schema.properties.taskStates.additionalProperties.properties.status.enum.includes(task.status)) process.exit(1);
    }
  ' "$state_file" "$schema_file" || fail "state does not satisfy required schema core: $state_file"
}

expect_bad_state_next() {
  local name="$1"
  local mutator="$2"
  local needle="$3"
  local dir="$TMP_ROOT/$name"
  write_fixture "$dir"
  approve_all "$dir"
  node -e "$mutator" "$dir/spec/.spec-drive-state.json"
  if run_next "$dir" "$name"; then
    fail "$name malformed state allowed dispatch"
  fi
  assert_json_error_contains "$dir/next-$name.out" "$needle"
}

expect_invalid_mutation() {
  local name="$1"
  local needle="$2"
  local dir="$TMP_ROOT/$name"
  write_fixture "$dir"
  case "$name" in
    missing-field)
      perl -0pi -e 's/\n  - \*\*Verify\*\*: test -f src\/gate.txt//' "$dir/spec/tasks.md"
      ;;
    invalid-task-id)
      perl -0pi -e 's/- \[ \] 1\.1 Create gate/- [ ] one Create gate/' "$dir/spec/tasks.md"
      ;;
    unknown-trace)
      perl -0pi -e 's/AC-1\.1, FR-1, NFR-1/AC-9.9, FR-1, NFR-1/' "$dir/spec/tasks.md"
      ;;
    coverage-incomplete)
      perl -0pi -e 's/\| NFR-1 \| Portable Protocol \|//' "$dir/spec/design.md"
      ;;
    stale-hash)
      perl -0pi -e 's/design_sha: "[a-f0-9]{64}"/design_sha: "0000000000000000000000000000000000000000000000000000000000000000"/' "$dir/spec/tasks.md"
      ;;
    blocked-artifact)
      perl -0pi -e 's/status: "complete"/status: "blocked"/' "$dir/spec/design.md"
      ;;
    *)
      fail "unknown mutation fixture: $name"
      ;;
  esac
  if [[ "$name" == "coverage-incomplete" || "$name" == "blocked-artifact" ]]; then
    local design_sha
    design_sha="$(sha_file "$dir/spec/design.md")"
    perl -0pi -e "s/design_sha: \"[a-f0-9]{64}\"/design_sha: \"$design_sha\"/" "$dir/spec/tasks.md"
  fi
  approve_all "$dir"
  if run_preflight "$dir"; then
    fail "$name passed unexpectedly"
  fi
  assert_json_error_contains "$dir/preflight.out" "$needle"
  [[ ! -e "$dir/repo/src/dispatch.txt" ]] || fail "$name wrote dispatch sentinel"
  [[ ! -e "$dir/repo/src/generated-code.txt" ]] || fail "$name wrote product code"
}

gate_poc() {
  rm -rf "$TMP_ROOT"
  mkdir -p "$TMP_ROOT"

  local valid="$TMP_ROOT/valid"
  write_fixture "$valid"
  approve_all "$valid"
  assert_state_schema_core "$valid/spec/.spec-drive-state.json"
  run_preflight "$valid" || fail "valid preflight failed: $(cat "$valid/preflight.err")"
  assert_json_ok "$valid/preflight.out"
  node -e '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (p.phase !== "tasks" || p.plan.totalTasks !== 2 || p.plan.taskOrder.join(",") !== "1.1,V1") process.exit(1);
  ' "$valid/preflight.out" || fail "valid plan summary mismatch"
  node -e 'const fs=require("fs"); fs.writeFileSync(process.argv[1], JSON.stringify({op:"status", specDir:process.argv[2]}));' "$valid/status.json" "$valid/spec"
  kernel_json "$valid/status.json" "$valid/status.out" "$valid/status.err" || fail "status failed: $(cat "$valid/status.err")"
  node -e '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (p.ok !== true || p.status.currentStage !== "preflight" || !p.status.approvals.tasks.hasEvidence) process.exit(1);
  ' "$valid/status.out" || fail "status response mismatch"

  expect_invalid_mutation "missing-field" "missing required field 'Verify'"
  expect_invalid_mutation "invalid-task-id" "invalid task id"
  expect_invalid_mutation "unknown-trace" "unknown trace reference"
  expect_invalid_mutation "coverage-incomplete" "coverage incomplete"
  expect_invalid_mutation "stale-hash" "tasks.md design_sha is stale"
  expect_invalid_mutation "blocked-artifact" "artifact is blocked"

  local changed="$TMP_ROOT/changed-after-approve"
  write_fixture "$changed"
  approve_all "$changed"
  printf '\nChanged bytes.\n' >> "$changed/spec/tasks.md"
  if run_preflight "$changed"; then
    fail "changed bytes passed preflight after approval"
  fi
  assert_json_error_contains "$changed/preflight.out" "tasks hash is stale"

  local evidence="$TMP_ROOT/no-evidence"
  write_fixture "$evidence"
  local sha input out err
  sha="$(sha_file "$evidence/spec/requirements.md")"
  input="$evidence/approve-no-evidence.json"
  out="$evidence/approve-no-evidence.out"
  err="$evidence/approve-no-evidence.err"
  node -e 'const fs=require("fs"); fs.writeFileSync(process.argv[1], JSON.stringify({op:"approve", specDir:process.argv[2], artifact:"requirements", expectedSha256:process.argv[3], approvalEvidence:""}));' "$input" "$evidence/spec" "$sha"
  if kernel_json "$input" "$out" "$err"; then
    fail "approve without evidence passed"
  fi
  assert_json_error_contains "$out" "approvalEvidence"
}

ledger_poc() {
  local dir="$TMP_ROOT/ledger"
  write_fixture "$dir"
  approve_all "$dir"
  assert_state_schema_core "$dir/spec/.spec-drive-state.json"

  perl -0pi -e 's/- \[ \] 1\.1 Create gate/- [x] 1.1 Create gate/' "$dir/spec/tasks.md"
  perl -0pi -e 's/(- \[x\] 1\.1 Create gate.*?\n\n)(- \[ \] V1 \[VERIFY\] Check gate.*?Commit\*\*: none\n)/$2\n$1/s' "$dir/spec/tasks.md"
  run_preflight "$dir" || fail "reorder and checkbox-only preflight failed: $(cat "$dir/preflight.err")"
  assert_json_ok "$dir/preflight.out"

  run_next "$dir" "first" || fail "first next failed: $(cat "$dir/next-first.err")"
  assert_json_ok "$dir/next-first.out"
  assert_state_schema_core "$dir/spec/.spec-drive-state.json"
  local attempt task
  attempt="$(json_get "$dir/next-first.out" "dispatch.attemptId")"
  task="$(json_get "$dir/next-first.out" "dispatch.taskId")"
  [[ "$task" == "1.1" ]] || fail "reorder dispatched $task instead of approved first task"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const task = state.taskStates["1.1"];
    if (state.currentTaskId !== "1.1" || state.currentStage !== "dispatching" || task.executionAttempts !== 1 || state.budgets.globalBudgetUsed !== 1) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" || fail "first reservation not persisted"

  mkdir "$dir/spec/.spec-drive-state.json.lock"
  if run_next "$dir" "locked"; then
    fail "second coordinator acquired locked state"
  fi
  rmdir "$dir/spec/.spec-drive-state.json.lock"
  assert_json_error_contains "$dir/next-locked.out" "locked by another coordinator"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (Object.keys(state.attempts).length !== 1 || state.budgets.globalBudgetUsed !== 1) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" || fail "locked next mutated state"

  run_report "$dir" "nostart" "$attempt" "1.1" "task_blocked" "dispatch_error" "not_started" "false" \
    || fail "no-start report failed: $(cat "$dir/report-nostart.err")"
  assert_json_ok "$dir/report-nostart.out"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const task = state.taskStates["1.1"];
    if (task.dispatchFailures !== 1 || task.executionAttempts !== 0 || state.budgets.globalBudgetUsed !== 1 || state.activeAttemptId !== null) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" || fail "no-start budget accounting mismatch"

  run_next "$dir" "unknown" || fail "unknown next failed: $(cat "$dir/next-unknown.err")"
  local unknown_attempt
  unknown_attempt="$(json_get "$dir/next-unknown.out" "dispatch.attemptId")"
  run_report "$dir" "unknown" "$unknown_attempt" "1.1" "task_blocked" "dispatch_error" "unknown" "false" \
    || fail "unknown-start report failed: $(cat "$dir/report-unknown.err")"
  assert_json_ok "$dir/report-unknown.out"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const task = state.taskStates["1.1"];
    if (state.currentStage !== "indeterminate" || state.activeAttemptId !== process.argv[2] || task.executionAttempts !== 1 || task.dispatchFailures !== 1) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" "$unknown_attempt" || fail "unknown-start was treated as free dispatch"
  if run_next "$dir" "after-unknown"; then
    fail "indeterminate attempt allowed automatic redispatch"
  fi
  assert_json_error_contains "$dir/next-after-unknown.out" "active attempt prevents new dispatch"

  local complete="$TMP_ROOT/reported-complete"
  write_fixture "$complete"
  approve_all "$complete"
  run_next "$complete" "first" || fail "complete first next failed: $(cat "$complete/next-first.err")"
  local complete_attempt
  complete_attempt="$(json_get "$complete/next-first.out" "dispatch.attemptId")"
  run_report "$complete" "complete" "$complete_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "complete report failed: $(cat "$complete/report-complete.err")"
  assert_json_ok "$complete/report-complete.out"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const task = state.taskStates["1.1"];
    if (state.currentStage !== "reported_complete" || state.activeAttemptId !== null || task.status !== "promotion_pending") process.exit(1);
    if (task.executionAttempts !== 1 || state.budgets.globalBudgetUsed !== 1 || state.attempts[process.argv[2]].state !== "reported_complete") process.exit(1);
  ' "$complete/spec/.spec-drive-state.json" "$complete_attempt" || fail "reported complete was not held for acceptance"
  if run_next "$complete" "after-complete"; then
    fail "reported_complete allowed redispatch before acceptance"
  fi
  assert_json_error_contains "$complete/next-after-complete.out" "awaiting authoritative acceptance"
  run_resume "$complete" "after-complete" || fail "resume after reported complete failed: $(cat "$complete/resume-after-complete.err")"
  assert_json_ok "$complete/resume-after-complete.out"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (Object.keys(state.attempts).length !== 1 || state.budgets.globalBudgetUsed !== 1 || state.taskStates["1.1"].executionAttempts !== 1) process.exit(1);
  ' "$complete/spec/.spec-drive-state.json" || fail "resume after reported complete changed budgets"

  for evidence in unknown not_started; do
    local conflicting="$TMP_ROOT/conflicting-success-$evidence"
    write_fixture "$conflicting"
    approve_all "$conflicting"
    run_next "$conflicting" "first" || fail "conflicting $evidence next failed: $(cat "$conflicting/next-first.err")"
    local conflicting_attempt
    conflicting_attempt="$(json_get "$conflicting/next-first.out" "dispatch.attemptId")"
    run_report "$conflicting" "$evidence" "$conflicting_attempt" "1.1" "task_complete" "none" "$evidence" "false" \
      || fail "conflicting $evidence report failed: $(cat "$conflicting/report-$evidence.err")"
    assert_json_ok "$conflicting/report-$evidence.out"
    node -e '
      const fs = require("fs");
      const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const task = state.taskStates["1.1"];
      if (state.currentStage !== "indeterminate" || state.activeAttemptId !== process.argv[2] || task.status === "verified_in_worktree" || task.status === "accepted") process.exit(1);
    ' "$conflicting/spec/.spec-drive-state.json" "$conflicting_attempt" || fail "conflicting $evidence success was accepted or verified"
  done

  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    state.activeAttemptId = null;
    state.currentStage = "ready";
    state.taskStates["1.1"].status = "pending";
    fs.writeFileSync(file, JSON.stringify(state, null, 2) + "\n");
  ' "$dir/spec/.spec-drive-state.json"
  for i in 1 2 3 4; do
    run_next "$dir" "logic-$i" || fail "logic next $i failed: $(cat "$dir/next-logic-$i.err")"
    local logic_attempt
    logic_attempt="$(json_get "$dir/next-logic-$i.out" "dispatch.attemptId")"
    run_report "$dir" "logic-$i" "$logic_attempt" "1.1" "task_blocked" "logic_error" "started" "true" \
      || fail "logic report $i failed: $(cat "$dir/report-logic-$i.err")"
  done
  if run_next "$dir" "exhausted"; then
    fail "execution budget reset after process restarts"
  fi
  assert_json_error_contains "$dir/next-exhausted.out" "execution attempt budget exhausted"

  local dispatch="$TMP_ROOT/dispatch-budget"
  write_fixture "$dispatch"
  approve_all "$dispatch"
  for i in 1 2 3; do
    run_next "$dispatch" "dispatch-$i" || fail "dispatch next $i failed: $(cat "$dispatch/next-dispatch-$i.err")"
    local dispatch_attempt
    dispatch_attempt="$(json_get "$dispatch/next-dispatch-$i.out" "dispatch.attemptId")"
    run_report "$dispatch" "dispatch-$i" "$dispatch_attempt" "1.1" "task_blocked" "dispatch_error" "not_started" "false" \
      || fail "dispatch report $i failed: $(cat "$dispatch/report-dispatch-$i.err")"
  done
  if run_next "$dispatch" "dispatch-exhausted"; then
    fail "dispatch budget allowed a fourth no-start"
  fi
  assert_json_error_contains "$dispatch/next-dispatch-exhausted.out" "dispatch failure budget exhausted"

  local global="$TMP_ROOT/global-budget"
  write_fixture "$global"
  approve_all "$global"
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    state.budgets = { maxDispatchFailures: 3, maxExecutionAttempts: 5, maxGlobalOperations: 1, globalBudgetUsed: 0 };
    fs.writeFileSync(file, JSON.stringify(state, null, 2) + "\n");
  ' "$global/spec/.spec-drive-state.json"
  run_next "$global" "global-first" || fail "global first next failed: $(cat "$global/next-global-first.err")"
  local global_attempt
  global_attempt="$(json_get "$global/next-global-first.out" "dispatch.attemptId")"
  run_report "$global" "global-first" "$global_attempt" "1.1" "task_blocked" "dispatch_error" "not_started" "false" \
    || fail "global no-start report failed: $(cat "$global/report-global-first.err")"
  if run_next "$global" "global-exhausted"; then
    fail "global budget allowed second operation"
  fi
  assert_json_error_contains "$global/next-global-exhausted.out" "global operation budget exhausted"

  expect_bad_state_next "bad-budget-string" '
    const fs = require("fs");
    const file = process.argv[1];
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    state.budgets = { maxDispatchFailures: "3", maxExecutionAttempts: 5, maxGlobalOperations: 100, globalBudgetUsed: 0 };
    fs.writeFileSync(file, JSON.stringify(state, null, 2) + "\n");
  ' "budgets.maxDispatchFailures"
  expect_bad_state_next "bad-budget-zero" '
    const fs = require("fs");
    const file = process.argv[1];
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    state.budgets = { maxDispatchFailures: 3, maxExecutionAttempts: 0, maxGlobalOperations: 100, globalBudgetUsed: 0 };
    fs.writeFileSync(file, JSON.stringify(state, null, 2) + "\n");
  ' "budgets.maxExecutionAttempts"
  expect_bad_state_next "bad-counter-negative" '
    const fs = require("fs");
    const file = process.argv[1];
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    state.budgets = { maxDispatchFailures: 3, maxExecutionAttempts: 5, maxGlobalOperations: 100, globalBudgetUsed: 0 };
    state.taskStates = {
      "1.1": { taskId: "1.1", status: "pending", required: true, attempts: [], dispatchFailures: -1, executionAttempts: 0 }
    };
    fs.writeFileSync(file, JSON.stringify(state, null, 2) + "\n");
  ' "taskStates.1.1.dispatchFailures"

  local legacy="$TMP_ROOT/ambiguous-legacy"
  write_fixture "$legacy"
  approve_all "$legacy"
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    delete state.name;
    delete state.basePath;
    delete state.phase;
    state.taskIndex = 0;
    fs.writeFileSync(file, JSON.stringify(state, null, 2) + "\n");
  ' "$legacy/spec/.spec-drive-state.json"
  if run_next "$legacy" "legacy"; then
    fail "ambiguous legacy state was silently migrated"
  fi
  assert_json_error_contains "$legacy/next-legacy.out" "legacy migration is not supported yet"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (state.name !== undefined || state.basePath !== undefined || state.phase !== undefined || state.legacyMigratedAt !== undefined) process.exit(1);
  ' "$legacy/spec/.spec-drive-state.json" || fail "ambiguous legacy state was mutated"

  local semantic="$TMP_ROOT/semantic-change"
  write_fixture "$semantic"
  approve_all "$semantic"
  perl -0pi -e 's/Valid plan passes\./Changed done condition./' "$semantic/spec/tasks.md"
  if run_preflight "$semantic"; then
    fail "semantic task change passed with stale approval"
  fi
  assert_json_error_contains "$semantic/preflight.out" "tasks hash is stale"

  node -e 'const fs=require("fs"); fs.writeFileSync(process.argv[1], JSON.stringify({op:"recover", specDir:process.argv[2], attemptId:"missing", evidence:"fixture"}));' "$dir/recover.json" "$dir/spec"
  if kernel_json "$dir/recover.json" "$dir/recover.out" "$dir/recover.err"; then
    fail "recover unexpectedly succeeded"
  fi
  assert_json_error_contains "$dir/recover.out" "recover is not implemented"
}

all() {
  gate_poc
  ledger_poc
}

if [[ $# -eq 0 ]]; then
  set -- all
fi

for mode in "$@"; do
  case "$mode" in
    gate-poc) gate_poc ;;
    ledger-poc) ledger_poc ;;
    all) all ;;
    *) fail "unknown mode: $mode" ;;
  esac
done
