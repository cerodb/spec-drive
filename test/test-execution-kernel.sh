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
  # These fixtures exercise the shipped Codex subprocess contract. Select it
  # explicitly so CI does not depend on the coordinator's environment.
  local fixture_config="$TMP_ROOT/.routing-config"
  mkdir -p "$fixture_config/spec-drive"
  printf '{"cli":"codex"}\n' > "$fixture_config/spec-drive/config.json"
  set +e
  XDG_CONFIG_HOME="$fixture_config" node "$KERNEL" < "$input" > "$stdout" 2> "$stderr"
  local status=$?
  set -e
  return "$status"
}

sha_file() {
  node -e 'const fs=require("fs"), crypto=require("crypto"); process.stdout.write(crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))' "$1"
}

fixture_git() {
  local repo="$1"
  shift
  git -C "$repo" "$@"
}

init_fixture_repo() {
  local repo="$1"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Spec Drive Fixture"
  git -C "$repo" config user.email "spec-drive-fixture@example.invalid"
  git -C "$repo" config gpg.format openpgp
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" config tag.gpgSign false
  git -C "$repo" add .
  git -C "$repo" commit --allow-empty -q -m "fixture baseline"
}

assert_file_changed() {
  local file="$1"
  local before_sha="$2"
  local label="$3"
  local after_sha
  after_sha="$(sha_file "$file")"
  [[ "$after_sha" != "$before_sha" ]] || fail "$label did not mutate $file"
}

write_fixture() {
  local dir="$1"
  rm -rf "$dir"
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
  init_fixture_repo "$dir/repo"
}

write_contract_fixture() {
  local dir="$1"
  write_fixture "$dir"
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const reqSha = process.argv[2];
    const designSha = process.argv[3];
    const text = `---
spec: "fixture"
phase: tasks
status: "complete"
requirements_sha: "${reqSha}"
design_sha: "${designSha}"
---

# Tasks: fixture

<!--
- [ ] 9.9 Commented task must not parse
  - **Unknown**: ignored
-->

## Phase 1

- [ ] 1.1 Create gate
  - **Do**: Parse artifacts and stop invalid plans before dispatch.
    \`\`\`text
    - [ ] 8.8 Fenced task must not parse
      - **Unknown**: ignored inside fence
    \`\`\`
  - Files: src/gate.txt
  - Traces: AC-1.1, FR-1, NFR-1
  - **model**: advanced
  - **model_used**: gpt-fixture
  - Cwd: .
  - **Done when**: Valid plan passes.
  - Verify: test -f src/gate.txt
  - Timeout: 120
  - Commit: feat: gate

- [ ] V1 [VERIFY] Check gate
  - Do: Check the local gate.
  - Files: none
  - Traces: AC-1.2
  - Cwd: .
  - Done when: Invalid plans fail.
  - Verify: test ! -f src/dispatch.txt
  - Timeout: 120
  - Commit: none
`;
    fs.writeFileSync(file, text.replace(/\n/g, "\r\n"));
  ' "$dir/spec/tasks.md" "$(sha_file "$dir/spec/requirements.md")" "$(sha_file "$dir/spec/design.md")"
}

write_flow_fixture() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir/spec" "$dir/repo/src"
  printf 'before\n' > "$dir/repo/src/tracked name.txt"
  cat > "$dir/spec/requirements.md" <<'EOF_REQ'
---
spec: "flow"
phase: requirements
status: "complete"
---

# Requirements: flow

## User Stories

#### US-1: Isolated acceptance
**Acceptance Criteria:**
- [ ] AC-1.1: First code task is promoted only after authoritative Verify.
- [ ] AC-1.2: Second code task is promoted only after authoritative Verify.
- [ ] AC-1.3: Checkpoint records evidence without a code commit.
- [ ] AC-1.4: False completion signals do not accept.
- [ ] AC-1.5: Dirty target state blocks promotion without losing bytes.

## Functional Requirements

| ID | Description | Priority | Verification |
|----|-------------|----------|--------------|
| FR-1 | Isolated task worktrees promote declared files only. | High | Flow fixture |
| FR-2 | Target acceptance is authoritative. | High | Flow fixture |

## Non-Functional Requirements

- NFR-1: Acceptance records are durable before tracking advances.
- NFR-2: External target changes are preserved.
EOF_REQ

  local req_sha
  req_sha="$(sha_file "$dir/spec/requirements.md")"
  cat > "$dir/spec/design.md" <<EOF_DESIGN
---
spec: "flow"
phase: design
status: "complete"
requirements_sha: "$req_sha"
---

# Design: flow

## Coverage

| Source | Design target |
|---|---|
| AC-1.1 | Acceptance Engine |
| AC-1.2 | Acceptance Engine |
| AC-1.3 | Acceptance Engine |
| AC-1.4 | Acceptance Engine |
| AC-1.5 | Acceptance Engine |
| FR-1 | Attempt Workspace Manager |
| FR-2 | Acceptance Engine |
| NFR-1 | State Ledger |
| NFR-2 | Acceptance Engine |
EOF_DESIGN

  local design_sha
  design_sha="$(sha_file "$dir/spec/design.md")"
  cat > "$dir/spec/tasks.md" <<EOF_TASKS
---
spec: "flow"
phase: tasks
status: "complete"
requirements_sha: "$req_sha"
design_sha: "$design_sha"
---

# Tasks: flow

## Phase 1

- [ ] 1.1 Write alpha
  - **Do**: Write alpha output.
  - **Files**: src/alpha.txt
  - **Traces**: AC-1.1, AC-1.4, AC-1.5, FR-1, FR-2, NFR-1, NFR-2
  - **model**: advanced
  - **Cwd**: .
  - **Done when**: Alpha file exists with expected bytes.
  - **Verify**: test "\$(cat src/alpha.txt)" = alpha
  - **Timeout**: 30
  - **Commit**: feat: alpha

- [ ] 1.2 Write beta
  - **Do**: Write beta output.
  - **Files**: src/tracked name.txt
  - **Traces**: AC-1.2, FR-1, FR-2, NFR-1
  - **model**: advanced
  - **Cwd**: .
  - **Done when**: Existing beta file is modified with expected bytes.
  - **Verify**: test "\$(cat 'src/tracked name.txt')" = beta
  - **Timeout**: 30
  - **Commit**: feat: beta

- [ ] V1 [VERIFY] Check final flow
  - **Do**: Verify accepted task outputs.
  - **Files**: none
  - **Traces**: AC-1.3, FR-2, NFR-1
  - **Cwd**: .
  - **Done when**: Alpha and beta outputs are present.
  - **Verify**: test "\$(cat src/alpha.txt)" = alpha && test "\$(cat 'src/tracked name.txt')" = beta
  - **Timeout**: 30
  - **Commit**: none
EOF_TASKS
  init_fixture_repo "$dir/repo"
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

approve_artifact() {
  local dir="$1"
  local artifact="$2"
  local evidence="$3"
  local sha input out err
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
      approvalEvidence: process.argv[5]
    }));
  ' "$input" "$dir/spec" "$artifact" "$sha" "$evidence"
  kernel_json "$input" "$out" "$err" || fail "approve $artifact failed: $(cat "$err")"
  assert_json_ok "$out"
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
  local actor="${3:-implement}"
  local input="$dir/next-$name.json"
  node -e '
    const fs = require("fs");
    fs.writeFileSync(process.argv[1], JSON.stringify({
      op: "next",
      specDir: process.argv[2],
      repoRoot: process.argv[3],
      actor: process.argv[4]
    }));
  ' "$input" "$dir/spec" "$dir/repo" "$actor"
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

run_recover() {
  local dir="$1"
  local name="$2"
  local attempt_id="$3"
  local evidence="$4"
  local input="$dir/recover-$name.json"
  node -e '
    const fs = require("fs");
    fs.writeFileSync(process.argv[1], JSON.stringify({
      op: "recover",
      specDir: process.argv[2],
      attemptId: process.argv[3],
      evidence: process.argv[4]
    }));
  ' "$input" "$dir/spec" "$attempt_id" "$evidence"
  kernel_json "$input" "$dir/recover-$name.out" "$dir/recover-$name.err"
}

run_pause() {
  local dir="$1"
  local name="$2"
  local reason="$3"
  local input="$dir/pause-$name.json"
  node -e '
    const fs = require("fs");
    fs.writeFileSync(process.argv[1], JSON.stringify({
      op: "pause",
      specDir: process.argv[2],
      reason: process.argv[3]
    }));
  ' "$input" "$dir/spec" "$reason"
  kernel_json "$input" "$dir/pause-$name.out" "$dir/pause-$name.err"
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

run_accept() {
  local dir="$1"
  local name="$2"
  local attempt_id="$3"
  local input="$dir/accept-$name.json"
  node -e '
    const fs = require("fs");
    fs.writeFileSync(process.argv[1], JSON.stringify({
      op: "accept",
      specDir: process.argv[2],
      repoRoot: process.argv[3],
      attemptId: process.argv[4]
    }));
  ' "$input" "$dir/spec" "$dir/repo" "$attempt_id"
  kernel_json "$input" "$dir/accept-$name.out" "$dir/accept-$name.err"
}

run_accept_crash() {
  local dir="$1"
  local name="$2"
  local attempt_id="$3"
  local crash_at="$4"
  local input="$dir/accept-$name.json"
  node -e '
    const fs = require("fs");
    fs.writeFileSync(process.argv[1], JSON.stringify({
      op: "accept",
      specDir: process.argv[2],
      repoRoot: process.argv[3],
      attemptId: process.argv[4],
      crashAt: process.argv[5]
    }));
  ' "$input" "$dir/spec" "$dir/repo" "$attempt_id" "$crash_at"
  kernel_json "$input" "$dir/accept-$name.out" "$dir/accept-$name.err"
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
  local mutation_file before_sha
  case "$name" in
    missing-field)
      mutation_file="$dir/spec/tasks.md"
      before_sha="$(sha_file "$mutation_file")"
      perl -0pi -e 's/\n  - \*\*Verify\*\*: test -f src\/gate.txt//' "$dir/spec/tasks.md"
      ;;
    invalid-task-id)
      mutation_file="$dir/spec/tasks.md"
      before_sha="$(sha_file "$mutation_file")"
      perl -0pi -e 's/- \[ \] 1\.1 Create gate/- [ ] one Create gate/' "$dir/spec/tasks.md"
      ;;
    unknown-trace)
      mutation_file="$dir/spec/tasks.md"
      before_sha="$(sha_file "$mutation_file")"
      perl -0pi -e 's/AC-1\.1, FR-1, NFR-1/AC-9.9, FR-1, NFR-1/' "$dir/spec/tasks.md"
      ;;
    coverage-incomplete)
      mutation_file="$dir/spec/design.md"
      before_sha="$(sha_file "$mutation_file")"
      perl -0pi -e 's/\| NFR-1 \| Portable Protocol \|//' "$dir/spec/design.md"
      ;;
    stale-hash)
      mutation_file="$dir/spec/tasks.md"
      before_sha="$(sha_file "$mutation_file")"
      perl -0pi -e 's/design_sha: "[a-f0-9]{64}"/design_sha: "0000000000000000000000000000000000000000000000000000000000000000"/' "$dir/spec/tasks.md"
      ;;
    blocked-artifact)
      mutation_file="$dir/spec/design.md"
      before_sha="$(sha_file "$mutation_file")"
      perl -0pi -e 's/status: "complete"/status: "blocked"/' "$dir/spec/design.md"
      ;;
    *)
      fail "unknown mutation fixture: $name"
      ;;
  esac
  assert_file_changed "$mutation_file" "$before_sha" "$name mutation"
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

expect_contract_preflight_error() {
  local name="$1"
  local mutator="$2"
  local needle="$3"
  local dir="$TMP_ROOT/$name"
  write_fixture "$dir"
  node -e "$mutator" "$dir/spec/tasks.md" "$dir/repo"
  approve_all "$dir"
  if run_preflight "$dir"; then
    fail "$name passed unexpectedly"
  fi
  assert_json_error_contains "$dir/preflight.out" "$needle"
  [[ ! -e "$dir/repo/src/dispatch.txt" ]] || fail "$name wrote dispatch sentinel"
}

contracts_poc() {
  rm -rf "$TMP_ROOT"
  mkdir -p "$TMP_ROOT"

  # Canonical generation contract: each downstream artifact captures the digest returned by explicit
  # upstream approval; generated tasks remain blocked until their own explicit approval and preflight.
  local generated="$TMP_ROOT/contracts-generated-path"
  write_fixture "$generated"
  approve_artifact "$generated" "requirements" "requirements reviewed for task generation"
  local approved_requirements_sha approved_design_sha
  approved_requirements_sha="$(json_get "$generated/approve-requirements.out" "sha256")"
  grep -Fq "requirements_sha: \"$approved_requirements_sha\"" "$generated/spec/design.md" \
    || fail "generated design did not capture approved requirements SHA-256"
  approve_artifact "$generated" "design" "design reviewed for task generation"
  approved_design_sha="$(json_get "$generated/approve-design.out" "sha256")"
  grep -Fq "requirements_sha: \"$approved_requirements_sha\"" "$generated/spec/tasks.md" \
    || fail "generated tasks did not capture approved requirements SHA-256"
  grep -Fq "design_sha: \"$approved_design_sha\"" "$generated/spec/tasks.md" \
    || fail "generated tasks did not capture approved design SHA-256"
  if run_preflight "$generated"; then
    fail "generated tasks passed preflight without explicit tasks approval"
  fi
  assert_json_error_contains "$generated/preflight.out" "missing explicit approval evidence for tasks"
  approve_artifact "$generated" "tasks" "generated task plan reviewed for execution"
  run_preflight "$generated" || fail "canonical generated plan failed preflight: $(cat "$generated/preflight.err")"
  assert_json_ok "$generated/preflight.out"

  printf '\nDesign mutation after approval.\n' >> "$generated/spec/design.md"
  if run_preflight "$generated"; then
    fail "mutated design passed with stale approval"
  fi
  assert_json_error_contains "$generated/preflight.out" "design hash is stale"

  local parser="$TMP_ROOT/contracts-parser"
  write_contract_fixture "$parser"
  approve_all "$parser"
  run_preflight "$parser" || fail "contract parser preflight failed: $(cat "$parser/preflight.err")"
  assert_json_ok "$parser/preflight.out"
  node -e '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (p.plan.totalTasks !== 2 || p.plan.taskOrder.join(",") !== "1.1,V1") process.exit(1);
  ' "$parser/preflight.out" || fail "contract parser task identity mismatch"

  perl -0pi -e 's/\*\*model_used\*\*: gpt-fixture/**model_used**: gpt-fixture-v2/' "$parser/spec/tasks.md"
  run_preflight "$parser" || fail "model_used-only change required fresh approval: $(cat "$parser/preflight.err")"
  assert_json_ok "$parser/preflight.out"
  perl -0pi -e 's/- \[ \] 1\.1 Create gate/- [x] 1.1 Create gate/' "$parser/spec/tasks.md"
  perl -0pi -e 's/(- \[x\] 1\.1 Create gate.*?\r?\n\r?\n)(- \[ \] V1 \[VERIFY\] Check gate.*?Commit: none\r?\n)/$2\r\n$1/s' "$parser/spec/tasks.md"
  run_next "$parser" "reordered" || fail "digest-stable reorder failed dispatch: $(cat "$parser/next-reordered.err")"
  assert_json_ok "$parser/next-reordered.out"
  [[ "$(json_get "$parser/next-reordered.out" "dispatch.taskId")" == "1.1" ]] || fail "reorder changed executable identity"

  local semantic="$TMP_ROOT/contracts-semantic-stale"
  write_contract_fixture "$semantic"
  approve_all "$semantic"
  perl -0pi -e 's/Valid plan passes\./Changed executable condition./' "$semantic/spec/tasks.md"
  if run_preflight "$semantic"; then
    fail "semantic task change passed with stale approval"
  fi
  assert_json_error_contains "$semantic/preflight.out" "tasks hash is stale"

  expect_contract_preflight_error "contracts-file-escape" '
    const fs = require("fs");
    const file = process.argv[1];
    fs.writeFileSync(file, fs.readFileSync(file, "utf8").replace("**Files**: src/gate.txt", "**Files**: ../escape.txt"));
  ' "Files path escapes repo"

  expect_contract_preflight_error "contracts-duplicate-files" '
    const fs = require("fs");
    const file = process.argv[1];
    fs.writeFileSync(file, fs.readFileSync(file, "utf8").replace("**Files**: src/gate.txt", "**Files**: src/gate.txt, src/gate.txt"));
  ' "duplicate paths"

  expect_contract_preflight_error "contracts-file-symlink" '
    const fs = require("fs");
    const path = require("path");
    const file = process.argv[1];
    const repo = process.argv[2];
    fs.symlinkSync(path.join(repo, "src"), path.join(repo, "linked-src"));
    fs.writeFileSync(file, fs.readFileSync(file, "utf8").replace("**Files**: src/gate.txt", "**Files**: linked-src/gate.txt"));
  ' "Files path traverses symlink"

  expect_contract_preflight_error "contracts-cwd-symlink" '
    const fs = require("fs");
    const path = require("path");
    const file = process.argv[1];
    const repo = process.argv[2];
    fs.symlinkSync(path.join(repo, "src"), path.join(repo, "linked-cwd"));
    fs.writeFileSync(file, fs.readFileSync(file, "utf8").replace("**Cwd**: .", "**Cwd**: linked-cwd"));
  ' "Cwd path traverses symlink"

  local legacy="$TMP_ROOT/contracts-legacy-index-only"
  write_fixture "$legacy"
  approve_all "$legacy"
  local before
  before="$(sha_file "$legacy/spec/.spec-drive-state.json")"
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    delete state.currentTaskId;
    delete state.taskOrder;
    delete state.taskStates;
    state.taskIndex = 0;
    state.totalTasks = 2;
    fs.writeFileSync(file, JSON.stringify(state, null, 2) + "\n");
  ' "$legacy/spec/.spec-drive-state.json"
  before="$(sha_file "$legacy/spec/.spec-drive-state.json")"
  if run_next "$legacy" "legacy"; then
    fail "index-only state was silently accepted"
  fi
  assert_json_error_contains "$legacy/next-legacy.out" "legacy index-only state"
  [[ "$(sha_file "$legacy/spec/.spec-drive-state.json")" == "$before" ]] || fail "index-only rejection mutated state bytes"

  local modern="$TMP_ROOT/contracts-modern-with-legacy-counter"
  write_fixture "$modern"
  approve_all "$modern"
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    delete state.legacyMigratedAt;
    state.currentTaskId = "1.1";
    state.taskOrder = ["1.1", "V1"];
    state.taskStates = {
      "1.1": { taskId: "1.1", status: "pending", required: true, attempts: [], dispatchFailures: 0, executionAttempts: 0 },
      "V1": { taskId: "V1", status: "pending", required: true, attempts: [], dispatchFailures: 0, executionAttempts: 0 }
    };
    state.currentStage = "ready";
    state.taskIndex = 0;
    fs.writeFileSync(file, JSON.stringify(state, null, 2) + "\n");
  ' "$modern/spec/.spec-drive-state.json"
  run_preflight "$modern" || fail "modern ID-based state with taskIndex failed preflight: $(cat "$modern/preflight.err")"
  assert_json_ok "$modern/preflight.out"
  run_next "$modern" "legacy-counter" || fail "modern ID-based state with taskIndex failed next: $(cat "$modern/next-legacy-counter.err")"
  assert_json_ok "$modern/next-legacy-counter.out"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (state.currentTaskId !== "1.1" || !Object.prototype.hasOwnProperty.call(state, "taskIndex")) process.exit(1);
    if (Object.prototype.hasOwnProperty.call(state, "legacyMigratedAt")) process.exit(1);
  ' "$modern/spec/.spec-drive-state.json" || fail "modern state did not retain compatible legacy counter"
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
  perl -0pi -e 's/Valid plan passes\./Changed executable condition./' "$changed/spec/tasks.md"
  if run_preflight "$changed"; then
    fail "changed executable task bytes passed preflight after approval"
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
  assert_json_error_contains "$dir/next-after-unknown.out" "requires recovery"

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
  assert_json_error_contains "$legacy/next-legacy.out" "legacy index-only state is not supported"
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

  node -e 'const fs=require("fs"); fs.writeFileSync(process.argv[1], JSON.stringify({op:"recover", specDir:process.argv[2], attemptId:"missing", evidence:"fixture recovery evidence"}));' "$dir/recover.json" "$dir/spec"
  if kernel_json "$dir/recover.json" "$dir/recover.out" "$dir/recover.err"; then
    fail "recover unexpectedly succeeded"
  fi
  assert_json_error_contains "$dir/recover.out" "unknown attemptId"
}

accept_code_task() {
  local dir="$1"
  local name="$2"
  local expected_task="$3"
  local rel_file="$4"
  local value="$5"
  run_next "$dir" "$name-next" || fail "$name next failed: $(cat "$dir/next-$name-next.err")"
  assert_json_ok "$dir/next-$name-next.out"
  local attempt task worktree
  attempt="$(json_get "$dir/next-$name-next.out" "dispatch.attemptId")"
  task="$(json_get "$dir/next-$name-next.out" "dispatch.taskId")"
  worktree="$(json_get "$dir/next-$name-next.out" "dispatch.worktreePath")"
  [[ "$task" == "$expected_task" ]] || fail "$name dispatched $task instead of $expected_task"
  mkdir -p "$(dirname "$worktree/$rel_file")"
  printf '%s\n' "$value" > "$worktree/$rel_file"
  run_report "$dir" "$name-report" "$attempt" "$expected_task" "task_complete" "none" "started" "true" \
    || fail "$name report failed: $(cat "$dir/report-$name-report.err")"
  assert_json_ok "$dir/report-$name-report.out"
  run_accept "$dir" "$name-accept" "$attempt" || fail "$name accept failed: $(cat "$dir/accept-$name-accept.err")"
  assert_json_ok "$dir/accept-$name-accept.out"
}

adapters_poc() {
  local dir="$TMP_ROOT/adapters"
  write_flow_fixture "$dir"
  approve_all "$dir"
  run_preflight "$dir" || fail "adapters preflight failed: $(cat "$dir/preflight.err")"
  assert_json_ok "$dir/preflight.out"

  run_next "$dir" "agent" || fail "agent adapter next failed: $(cat "$dir/next-agent.err")"
  assert_json_ok "$dir/next-agent.out"
  local agent_attempt agent_worktree before_invalid run_id
  agent_attempt="$(json_get "$dir/next-agent.out" "dispatch.attemptId")"
  agent_worktree="$(json_get "$dir/next-agent.out" "dispatch.worktreePath")"
  run_id="$(json_get "$dir/spec/.spec-drive-state.json" "runId")"
  before_invalid="$(sha_file "$dir/spec/.spec-drive-state.json")"
  node -e '
    const fs = require("fs");
    fs.writeFileSync(process.argv[1], JSON.stringify({
      op: "report",
      specDir: process.argv[2],
      repoRoot: process.argv[3],
      attemptId: process.argv[4],
      adapterEvidence: "started",
      report: {
        attemptId: "forged-private-attempt",
        taskId: "1.2",
        outcome: "task_complete",
        startedWork: true,
        summary: "invalid envelope must not fork history"
      }
    }));
  ' "$dir/report-agent-invalid.json" "$dir/spec" "$dir/repo" "$agent_attempt"
  if kernel_json "$dir/report-agent-invalid.json" "$dir/report-agent-invalid.out" "$dir/report-agent-invalid.err"; then
    fail "invalid adapter envelope was accepted"
  fi
  assert_json_error_contains "$dir/report-agent-invalid.out" "report identity does not match attempt"
  [[ "$(sha_file "$dir/spec/.spec-drive-state.json")" == "$before_invalid" ]] || fail "invalid adapter envelope mutated kernel ledger"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (Object.keys(state.attempts).length !== 1) process.exit(1);
    if (state.currentTaskId !== "1.1" || state.activeAttemptId !== process.argv[2]) process.exit(1);
    if (state.taskStates["1.1"].executionAttempts !== 1 || state.budgets.globalBudgetUsed !== 1) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" "$agent_attempt" || fail "invalid adapter envelope created private history or changed budgets"

  mkdir -p "$agent_worktree/src"
  printf 'alpha\n' > "$agent_worktree/src/alpha.txt"
  run_report "$dir" "agent" "$agent_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "agent adapter report failed: $(cat "$dir/report-agent.err")"
  run_accept "$dir" "agent" "$agent_attempt" || fail "agent adapter accept failed: $(cat "$dir/accept-agent.err")"
  assert_json_ok "$dir/accept-agent.out"

  run_next "$dir" "subprocess" || fail "subprocess adapter next failed: $(cat "$dir/next-subprocess.err")"
  assert_json_ok "$dir/next-subprocess.out"
  local subprocess_attempt subprocess_worktree
  subprocess_attempt="$(json_get "$dir/next-subprocess.out" "dispatch.attemptId")"
  subprocess_worktree="$(json_get "$dir/next-subprocess.out" "dispatch.worktreePath")"
  [[ "$(json_get "$dir/next-subprocess.out" "dispatch.mechanism")" == "subprocess" ]] || fail "subprocess adapter did not receive subprocess contract"
  mkdir -p "$subprocess_worktree/src"
  printf 'beta\n' > "$subprocess_worktree/src/tracked name.txt"
  run_report "$dir" "subprocess" "$subprocess_attempt" "1.2" "task_complete" "none" "started" "true" \
    || fail "subprocess adapter report failed: $(cat "$dir/report-subprocess.err")"
  run_accept "$dir" "subprocess" "$subprocess_attempt" || fail "subprocess adapter accept failed: $(cat "$dir/accept-subprocess.err")"
  assert_json_ok "$dir/accept-subprocess.out"

  run_next "$dir" "inherit" || fail "inherit adapter next failed: $(cat "$dir/next-inherit.err")"
  assert_json_ok "$dir/next-inherit.out"
  local inherit_attempt
  inherit_attempt="$(json_get "$dir/next-inherit.out" "dispatch.attemptId")"
  [[ "$(json_get "$dir/next-inherit.out" "dispatch.taskId")" == "V1" ]] || fail "inherit adapter did not resume shared task identity"
  [[ "$(json_get "$dir/next-inherit.out" "dispatch.mechanism")" == "inherit" ]] || fail "inherit adapter did not receive inherit contract"
  run_report "$dir" "inherit" "$inherit_attempt" "V1" "task_complete" "none" "started" "true" \
    || fail "inherit adapter report failed: $(cat "$dir/report-inherit.err")"
  run_accept "$dir" "inherit" "$inherit_attempt" || fail "inherit adapter accept failed: $(cat "$dir/accept-inherit.err")"
  assert_json_ok "$dir/accept-inherit.out"

  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const attempts = [process.argv[3], process.argv[4], process.argv[5]].map((id) => state.attempts[id]);
    if (state.runId !== process.argv[2]) process.exit(1);
    if (state.currentTaskId !== null || state.currentStage !== "completed") process.exit(1);
    if (state.budgets.globalBudgetUsed !== 3) process.exit(1);
    if (state.taskStates["1.1"].executionAttempts !== 1 || state.taskStates["1.2"].executionAttempts !== 1 || state.taskStates.V1.executionAttempts !== 1) process.exit(1);
    if (attempts.some((a) => !a || a.state !== "accepted")) process.exit(1);
    if (attempts.some((a) => a.actor !== "implement")) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" "$run_id" "$agent_attempt" "$subprocess_attempt" "$inherit_attempt" \
    || fail "adapters did not share one accepted ledger identity and budget"
  [[ "$(cat "$dir/repo/src/alpha.txt")" == "alpha" ]] || fail "adapter flow lost alpha bytes"
  [[ "$(cat "$dir/repo/src/tracked name.txt")" == "beta" ]] || fail "adapter flow lost beta bytes"
}

flow_poc() {
  local dir="$TMP_ROOT/flow"
  write_flow_fixture "$dir"
  approve_all "$dir"
  run_preflight "$dir" || fail "flow preflight failed: $(cat "$dir/preflight.err")"
  assert_json_ok "$dir/preflight.out"

  accept_code_task "$dir" "alpha" "1.1" "src/alpha.txt" "alpha"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const alpha = state.taskStates["1.1"].acceptance;
    if (state.currentTaskId !== "1.2" || state.currentStage !== "ready") process.exit(1);
    if (!alpha || !alpha.commitOid || alpha.commitOid === "null" || !alpha.verifiedTree) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" || fail "alpha acceptance not persisted"
  grep -q '^- \[x\] 1\.1 Write alpha' "$dir/spec/tasks.md" || fail "alpha task checkbox was not projected"
  grep -q '1.1: accepted' "$dir/spec/.progress.md" || fail "alpha progress was not projected"

  accept_code_task "$dir" "beta" "1.2" "src/tracked name.txt" "beta"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const beta = state.taskStates["1.2"].acceptance;
    if (state.currentTaskId !== "V1" || state.currentStage !== "ready") process.exit(1);
    if (!beta || !beta.commitOid || !beta.verifiedTree) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" || fail "beta acceptance not persisted"
  grep -q '^- \[x\] 1\.2 Write beta' "$dir/spec/tasks.md" || fail "beta task checkbox was not projected"

  local head_before_checkpoint
  head_before_checkpoint="$(fixture_git "$dir/repo" rev-parse HEAD)"
  run_next "$dir" "checkpoint-next" || fail "checkpoint next failed: $(cat "$dir/next-checkpoint-next.err")"
  local checkpoint_attempt checkpoint_task
  checkpoint_attempt="$(json_get "$dir/next-checkpoint-next.out" "dispatch.attemptId")"
  checkpoint_task="$(json_get "$dir/next-checkpoint-next.out" "dispatch.taskId")"
  [[ "$checkpoint_task" == "V1" ]] || fail "checkpoint dispatched $checkpoint_task instead of V1"
  run_report "$dir" "checkpoint-report" "$checkpoint_attempt" "V1" "task_complete" "none" "started" "true" \
    || fail "checkpoint report failed: $(cat "$dir/report-checkpoint-report.err")"
  run_accept "$dir" "checkpoint-accept" "$checkpoint_attempt" \
    || fail "checkpoint accept failed: $(cat "$dir/accept-checkpoint-accept.err")"
  assert_json_ok "$dir/accept-checkpoint-accept.out"
  [[ "$(fixture_git "$dir/repo" rev-parse HEAD)" == "$head_before_checkpoint" ]] || fail "checkpoint created a commit"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const checkpoint = state.taskStates.V1.acceptance;
    if (state.currentTaskId !== null || state.currentStage !== "completed") process.exit(1);
    if (!checkpoint || checkpoint.commitOid !== null || checkpoint.exitCode !== 0) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" || fail "checkpoint acceptance mismatch"

  local trailer_count
  trailer_count="$(fixture_git "$dir/repo" log --format=%B | grep -c "Spec-Drive-Attempt")"
  [[ "$trailer_count" == "2" ]] || fail "expected exactly two code commits with attempt trailers, got $trailer_count"
  [[ "$(fixture_git "$dir/repo" rev-list --count HEAD)" == "3" ]] || fail "expected baseline plus two code commits"
  [[ "$(cat "$dir/repo/src/alpha.txt")" == "alpha" ]] || fail "alpha target bytes mismatch"
  [[ "$(cat "$dir/repo/src/tracked name.txt")" == "beta" ]] || fail "beta target bytes mismatch"

  local signing="$TMP_ROOT/flow-signing-policy"
  write_flow_fixture "$signing"
  approve_all "$signing"
  git -C "$signing/repo" config commit.gpgsign true
  git -C "$signing/repo" config gpg.format openpgp
  cat > "$signing/fake-gpg.sh" <<'EOF_GPG'
#!/usr/bin/env bash
echo fake signing program invoked >&2
exit 42
EOF_GPG
  chmod +x "$signing/fake-gpg.sh"
  git -C "$signing/repo" config gpg.program "$signing/fake-gpg.sh"
  git -C "$signing/repo" config user.signingkey spec-drive-fixture@example.invalid
  run_next "$signing" "sign-next" || fail "signing next failed: $(cat "$signing/next-sign-next.err")"
  local sign_attempt sign_worktree
  sign_attempt="$(json_get "$signing/next-sign-next.out" "dispatch.attemptId")"
  sign_worktree="$(json_get "$signing/next-sign-next.out" "dispatch.worktreePath")"
  mkdir -p "$sign_worktree/src"
  printf 'alpha\n' > "$sign_worktree/src/alpha.txt"
  run_report "$signing" "sign-report" "$sign_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "signing report failed: $(cat "$signing/report-sign-report.err")"
  if run_accept "$signing" "sign-accept" "$sign_attempt"; then
    fail "accept bypassed local commit signing policy"
  fi
  assert_json_error_contains "$signing/accept-sign-accept.out" "fake signing program invoked"

  local metadata="$TMP_ROOT/flow-unrelated-metadata"
  write_flow_fixture "$metadata"
  approve_all "$metadata"
  run_next "$metadata" "metadata-next" || fail "metadata next failed: $(cat "$metadata/next-metadata-next.err")"
  local metadata_attempt metadata_worktree
  metadata_attempt="$(json_get "$metadata/next-metadata-next.out" "dispatch.attemptId")"
  metadata_worktree="$(json_get "$metadata/next-metadata-next.out" "dispatch.worktreePath")"
  mkdir -p "$metadata_worktree/src" "$metadata/repo/.spec-drive"
  printf 'alpha\n' > "$metadata_worktree/src/alpha.txt"
  printf 'user bytes\n' > "$metadata/repo/.spec-drive/user.txt"
  run_report "$metadata" "metadata-report" "$metadata_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "metadata report failed: $(cat "$metadata/report-metadata-report.err")"
  if run_accept "$metadata" "metadata-accept" "$metadata_attempt"; then
    fail "unrelated .spec-drive metadata was ignored"
  fi
  assert_json_error_contains "$metadata/accept-metadata-accept.out" ".spec-drive/user.txt"
  [[ "$(cat "$metadata/repo/.spec-drive/user.txt")" == "user bytes" ]] || fail "unrelated metadata bytes were lost"

  local lease_metadata="$TMP_ROOT/flow-unrelated-lease-metadata"
  write_flow_fixture "$lease_metadata"
  approve_all "$lease_metadata"
  run_next "$lease_metadata" "lease-metadata-next" || fail "lease metadata next failed: $(cat "$lease_metadata/next-lease-metadata-next.err")"
  local lease_metadata_attempt lease_metadata_worktree lease_metadata_run
  lease_metadata_attempt="$(json_get "$lease_metadata/next-lease-metadata-next.out" "dispatch.attemptId")"
  lease_metadata_worktree="$(json_get "$lease_metadata/next-lease-metadata-next.out" "dispatch.worktreePath")"
  lease_metadata_run="$(json_get "$lease_metadata/spec/.spec-drive-state.json" "runId")"
  mkdir -p "$lease_metadata_worktree/src" "$lease_metadata/repo/.spec-drive/kernel/leases/$lease_metadata_run"
  printf 'alpha\n' > "$lease_metadata_worktree/src/alpha.txt"
  printf 'user bytes\n' > "$lease_metadata/repo/.spec-drive/kernel/leases/$lease_metadata_run/user.txt"
  run_report "$lease_metadata" "lease-metadata-report" "$lease_metadata_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "lease metadata report failed: $(cat "$lease_metadata/report-lease-metadata-report.err")"
  if run_accept "$lease_metadata" "lease-metadata-accept" "$lease_metadata_attempt"; then
    fail "unrelated lease-directory metadata was ignored"
  fi
  assert_json_error_contains "$lease_metadata/accept-lease-metadata-accept.out" ".spec-drive/kernel/leases/$lease_metadata_run/user.txt"
  [[ "$(cat "$lease_metadata/repo/.spec-drive/kernel/leases/$lease_metadata_run/user.txt")" == "user bytes" ]] || fail "unrelated lease metadata bytes were lost"

  local locked="$TMP_ROOT/flow-promotion-locked"
  write_flow_fixture "$locked"
  approve_all "$locked"
  run_next "$locked" "locked-next" || fail "locked next failed: $(cat "$locked/next-locked-next.err")"
  local locked_attempt locked_worktree locked_run
  locked_attempt="$(json_get "$locked/next-locked-next.out" "dispatch.attemptId")"
  locked_worktree="$(json_get "$locked/next-locked-next.out" "dispatch.worktreePath")"
  locked_run="$(json_get "$locked/spec/.spec-drive-state.json" "runId")"
  mkdir -p "$locked_worktree/src" "$locked/repo/.spec-drive/kernel/locks/promotion.lock"
  printf '{"runId":"foreign-run","specDir":"foreign-spec"}\n' > "$locked/repo/.spec-drive/kernel/locks/promotion.lock/owner.json"
  [[ "$locked_run" != "foreign-run" ]] || fail "lock fixture did not use distinct run identity"
  [[ ! -e "$locked/repo/.spec-drive/kernel/locks/$locked_run/promotion.lock" ]] || fail "promotion lock remained run-scoped"
  printf 'alpha\n' > "$locked_worktree/src/alpha.txt"
  run_report "$locked" "locked-report" "$locked_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "locked report failed: $(cat "$locked/report-locked-report.err")"
  if run_accept "$locked" "locked-accept" "$locked_attempt"; then
    fail "held cooperative promotion lock did not block"
  fi
  assert_json_error_contains "$locked/accept-locked-accept.out" "promotion lock is held"
  [[ ! -e "$locked/repo/src/alpha.txt" ]] || fail "held lock allowed target mutation"

  local projection="$TMP_ROOT/flow-projection-fail"
  write_flow_fixture "$projection"
  approve_all "$projection"
  run_next "$projection" "projection-next" || fail "projection next failed: $(cat "$projection/next-projection-next.err")"
  local projection_attempt projection_worktree
  projection_attempt="$(json_get "$projection/next-projection-next.out" "dispatch.attemptId")"
  projection_worktree="$(json_get "$projection/next-projection-next.out" "dispatch.worktreePath")"
  mkdir -p "$projection_worktree/src" "$projection/spec/.progress.md"
  printf 'alpha\n' > "$projection_worktree/src/alpha.txt"
  run_report "$projection" "projection-report" "$projection_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "projection report failed: $(cat "$projection/report-projection-report.err")"
  if run_accept "$projection" "projection-accept" "$projection_attempt"; then
    fail "projection failure did not block closure"
  fi
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const task = state.taskStates["1.1"];
    if (task.status !== "accepted" || !task.acceptance || state.currentTaskId !== "1.1") process.exit(1);
    if (state.attempts[process.argv[2]].promotion.stage !== "accepted_recorded") process.exit(1);
  ' "$projection/spec/.spec-drive-state.json" "$projection_attempt" || fail "projection failure did not preserve accepted record before tracking"
  if run_next "$projection" "after-projection-fail"; then
    fail "next advanced after interrupted projection"
  fi
  assert_json_error_contains "$projection/next-after-projection-fail.out" "requires recovery"

  local false="$TMP_ROOT/flow-false-complete"
  write_flow_fixture "$false"
  approve_all "$false"
  run_next "$false" "false-next" || fail "false next failed: $(cat "$false/next-false-next.err")"
  local false_attempt
  false_attempt="$(json_get "$false/next-false-next.out" "dispatch.attemptId")"
  run_report "$false" "false-report" "$false_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "false report failed: $(cat "$false/report-false-report.err")"
  if run_accept "$false" "false-accept" "$false_attempt"; then
    fail "false completion bypassed authoritative Verify"
  fi
  assert_json_error_contains "$false/accept-false-accept.out" "Verify failed"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (state.taskStates["1.1"].status === "accepted") process.exit(1);
  ' "$false/spec/.spec-drive-state.json" || fail "false completion was accepted"

  local verify_fail="$TMP_ROOT/flow-verify-fail"
  write_flow_fixture "$verify_fail"
  approve_all "$verify_fail"
  run_next "$verify_fail" "bad-next" || fail "bad next failed: $(cat "$verify_fail/next-bad-next.err")"
  local bad_attempt bad_worktree
  bad_attempt="$(json_get "$verify_fail/next-bad-next.out" "dispatch.attemptId")"
  bad_worktree="$(json_get "$verify_fail/next-bad-next.out" "dispatch.worktreePath")"
  mkdir -p "$bad_worktree/src"
  printf 'wrong\n' > "$bad_worktree/src/alpha.txt"
  run_report "$verify_fail" "bad-report" "$bad_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "bad report failed: $(cat "$verify_fail/report-bad-report.err")"
  if run_accept "$verify_fail" "bad-accept" "$bad_attempt"; then
    fail "bad implementation passed authoritative Verify"
  fi
  assert_json_error_contains "$verify_fail/accept-bad-accept.out" "Verify failed"
  [[ ! -e "$verify_fail/repo/src/alpha.txt" ]] || fail "failed Verify promoted target code"

  local outside_files="$TMP_ROOT/flow-outside-files"
  write_flow_fixture "$outside_files"
  approve_all "$outside_files"
  run_next "$outside_files" "outside-next" || fail "outside next failed: $(cat "$outside_files/next-outside-next.err")"
  local outside_attempt outside_worktree
  outside_attempt="$(json_get "$outside_files/next-outside-next.out" "dispatch.attemptId")"
  outside_worktree="$(json_get "$outside_files/next-outside-next.out" "dispatch.worktreePath")"
  mkdir -p "$outside_worktree/src"
  printf 'alpha\n' > "$outside_worktree/src/alpha.txt"
  printf 'outside\n' > "$outside_worktree/src/outside.txt"
  run_report "$outside_files" "outside-report" "$outside_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "outside report failed: $(cat "$outside_files/report-outside-report.err")"
  if run_accept "$outside_files" "outside-accept" "$outside_attempt"; then
    fail "outside Files mutation was accepted"
  fi
  assert_json_error_contains "$outside_files/accept-outside-accept.out" "outside declared Files"
  [[ ! -e "$outside_files/repo/src/alpha.txt" ]] || fail "outside Files rejection promoted target alpha"
  [[ ! -e "$outside_files/repo/src/outside.txt" ]] || fail "outside Files rejection promoted target outside file"

  local dirty="$TMP_ROOT/flow-dirty-target"
  write_flow_fixture "$dirty"
  approve_all "$dirty"
  run_next "$dirty" "dirty-next" || fail "dirty next failed: $(cat "$dirty/next-dirty-next.err")"
  local dirty_attempt dirty_worktree
  dirty_attempt="$(json_get "$dirty/next-dirty-next.out" "dispatch.attemptId")"
  dirty_worktree="$(json_get "$dirty/next-dirty-next.out" "dispatch.worktreePath")"
  mkdir -p "$dirty_worktree/src" "$dirty/repo/src"
  printf 'alpha\n' > "$dirty_worktree/src/alpha.txt"
  run_report "$dirty" "dirty-report" "$dirty_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "dirty report failed: $(cat "$dirty/report-dirty-report.err")"
  printf 'external bytes\n' > "$dirty/repo/src/external.txt"
  if run_accept "$dirty" "dirty-accept" "$dirty_attempt"; then
    fail "dirty target was accepted"
  fi
  assert_json_error_contains "$dirty/accept-dirty-accept.out" "external changes"
  [[ "$(cat "$dirty/repo/src/external.txt")" == "external bytes" ]] || fail "dirty target bytes were lost"
  [[ ! -e "$dirty/repo/src/alpha.txt" ]] || fail "dirty target received promoted alpha despite rejection"

  local target_mutation="$TMP_ROOT/flow-target-verify-mutation"
  write_flow_fixture "$target_mutation"
  before_sha="$(sha_file "$target_mutation/spec/tasks.md")"
  perl -0pi -e 's#test "\$\(cat src/alpha.txt\)" = alpha#node -e '"'"'fs=require("fs"),fs.existsSync("../spec")&&fs.writeFileSync("src/alpha.txt","mutated\\n")'"'"'#' "$target_mutation/spec/tasks.md"
  assert_file_changed "$target_mutation/spec/tasks.md" "$before_sha" "target Verify mutation"
  approve_all "$target_mutation"
  run_next "$target_mutation" "target-mut-next" || fail "target mutation next failed: $(cat "$target_mutation/next-target-mut-next.err")"
  local target_mut_attempt target_mut_worktree
  target_mut_attempt="$(json_get "$target_mutation/next-target-mut-next.out" "dispatch.attemptId")"
  target_mut_worktree="$(json_get "$target_mutation/next-target-mut-next.out" "dispatch.worktreePath")"
  mkdir -p "$target_mut_worktree/src"
  printf 'alpha\n' > "$target_mut_worktree/src/alpha.txt"
  run_report "$target_mutation" "target-mut-report" "$target_mut_attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "target mutation report failed: $(cat "$target_mutation/report-target-mut-report.err")"
  if run_accept "$target_mutation" "target-mut-accept" "$target_mut_attempt"; then
    fail "target Verify mutation was accepted"
  fi
  assert_json_error_contains "$target_mutation/accept-target-mut-accept.out" "target Verify mutated candidate tree"
  [[ "$(cat "$target_mutation/repo/src/alpha.txt")" == "mutated" ]] || fail "target Verify mutation was rolled back or lost"

  local checkpoint_mutation="$TMP_ROOT/flow-checkpoint-verify-mutation"
  write_flow_fixture "$checkpoint_mutation"
  before_sha="$(sha_file "$checkpoint_mutation/spec/tasks.md")"
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const before = fs.readFileSync(file, "utf8");
    const after = before.replace(
      `test "$(cat src/alpha.txt)" = alpha && test "$(cat '"'"'src/tracked name.txt'"'"')" = beta`,
      `node -e '"'"'require("fs").writeFileSync("src/tracked name.txt","checkpoint-mutated\\n")'"'"'`
    );
    fs.writeFileSync(file, after);
  ' "$checkpoint_mutation/spec/tasks.md"
  assert_file_changed "$checkpoint_mutation/spec/tasks.md" "$before_sha" "checkpoint Verify mutation"
  approve_all "$checkpoint_mutation"
  accept_code_task "$checkpoint_mutation" "checkpoint-mut-alpha" "1.1" "src/alpha.txt" "alpha"
  accept_code_task "$checkpoint_mutation" "checkpoint-mut-beta" "1.2" "src/tracked name.txt" "beta"
  run_next "$checkpoint_mutation" "checkpoint-mut-next" || fail "checkpoint mutation next failed: $(cat "$checkpoint_mutation/next-checkpoint-mut-next.err")"
  local checkpoint_mut_attempt
  checkpoint_mut_attempt="$(json_get "$checkpoint_mutation/next-checkpoint-mut-next.out" "dispatch.attemptId")"
  run_report "$checkpoint_mutation" "checkpoint-mut-report" "$checkpoint_mut_attempt" "V1" "task_complete" "none" "started" "true" \
    || fail "checkpoint mutation report failed: $(cat "$checkpoint_mutation/report-checkpoint-mut-report.err")"
  if run_accept "$checkpoint_mutation" "checkpoint-mut-accept" "$checkpoint_mut_attempt"; then
    fail "checkpoint Verify mutation was accepted"
  fi
  assert_json_error_contains "$checkpoint_mutation/accept-checkpoint-mut-accept.out" "target Verify mutated candidate tree"
  [[ "$(cat "$checkpoint_mutation/repo/src/tracked name.txt")" == "checkpoint-mutated" ]] || fail "checkpoint mutation bytes were not preserved"

  node -e 'const fs=require("fs"); fs.writeFileSync(process.argv[1], JSON.stringify({op:"recover", specDir:process.argv[2], attemptId:"missing", evidence:"fixture recovery evidence"}));' "$dir/recover-flow.json" "$dir/spec"
  if kernel_json "$dir/recover-flow.json" "$dir/recover-flow.out" "$dir/recover-flow.err"; then
    fail "flow recover unexpectedly succeeded"
  fi
  assert_json_error_contains "$dir/recover-flow.out" "unknown attemptId"
}

prepare_alpha_attempt() {
  local dir="$1"
  write_flow_fixture "$dir"
  approve_all "$dir"
  run_preflight "$dir" || fail "$dir preflight failed: $(cat "$dir/preflight.err")"
  run_next "$dir" "alpha-next" || fail "$dir next failed: $(cat "$dir/next-alpha-next.err")"
  local attempt worktree
  attempt="$(json_get "$dir/next-alpha-next.out" "dispatch.attemptId")"
  worktree="$(json_get "$dir/next-alpha-next.out" "dispatch.worktreePath")"
  mkdir -p "$worktree/src"
  printf 'alpha\n' > "$worktree/src/alpha.txt"
  run_report "$dir" "alpha-report" "$attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "$dir report failed: $(cat "$dir/report-alpha-report.err")"
  printf '%s\n' "$attempt"
}

assert_alpha_accepted_once() {
  local dir="$1"
  local attempt="$2"
  local output="${3:-$dir/accept-resume.out}"
  assert_json_ok "$output"
  [[ "$(cat "$dir/repo/src/alpha.txt")" == "alpha" ]] || fail "$dir alpha bytes mismatch after recovery"
  local trailer_count
  trailer_count="$(fixture_git "$dir/repo" log --format=%B | grep -c "Spec-Drive-Attempt: $attempt")"
  [[ "$trailer_count" == "1" ]] || fail "$dir expected one trailer commit for $attempt, got $trailer_count"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const attempt = state.attempts[process.argv[2]];
    const task = state.taskStates["1.1"];
    if (!attempt || attempt.state !== "accepted" || attempt.promotion.stage !== "tracking_updated") process.exit(1);
    if (!task.acceptance || task.acceptance.commitOid !== attempt.promotion.commitOid || state.currentTaskId !== "1.2") process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" "$attempt" || fail "$dir recovered ledger mismatch"
  grep -q '^- \[x\] 1\.1 Write alpha' "$dir/spec/tasks.md" || fail "$dir recovered tasks projection missing"
  grep -q '1.1: accepted' "$dir/spec/.progress.md" || fail "$dir recovered progress projection missing"
}

crash_poc() {
  local points=(before-intent after-intent before-patch after-patch before-verify after-verify before-commit after-commit-before-state after-commit before-tracking after-tracking)
  local point dir attempt
  for point in "${points[@]}"; do
    dir="$TMP_ROOT/crash-$point"
    attempt="$(prepare_alpha_attempt "$dir")"
    if run_accept_crash "$dir" "crash" "$attempt" "$point"; then
      fail "$point did not inject a crash"
    fi
    assert_json_error_contains "$dir/accept-crash.out" "injected crash: $point"
    run_resume "$dir" "resume" || fail "$point recovery failed: $(cat "$dir/resume-resume.err")"
    assert_alpha_accepted_once "$dir" "$attempt" "$dir/resume-resume.out"
  done

  dir="$TMP_ROOT/crash-projection-repair"
  attempt="$(prepare_alpha_attempt "$dir")"
  mkdir "$dir/spec/.progress.md"
  if run_accept "$dir" "projection-fail" "$attempt"; then
    fail "projection failure accepted cleanly"
  fi
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const attempt = state.attempts[process.argv[2]];
    if (attempt.state !== "accepted" || attempt.promotion.stage !== "accepted_recorded") process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" "$attempt" || fail "projection failure did not persist accepted before tracking"
  rmdir "$dir/spec/.progress.md"
  run_resume "$dir" "resume" || fail "projection repair failed: $(cat "$dir/resume-resume.err")"
  assert_alpha_accepted_once "$dir" "$attempt" "$dir/resume-resume.out"

  dir="$TMP_ROOT/crash-commit-failure"
  attempt="$(prepare_alpha_attempt "$dir")"
  git -C "$dir/repo" config commit.gpgsign true
  git -C "$dir/repo" config gpg.format openpgp
  cat > "$dir/fake-gpg.sh" <<'EOF_GPG'
#!/usr/bin/env bash
echo fake signing program invoked >&2
exit 42
EOF_GPG
  chmod +x "$dir/fake-gpg.sh"
  git -C "$dir/repo" config gpg.program "$dir/fake-gpg.sh"
  git -C "$dir/repo" config user.signingkey spec-drive-fixture@example.invalid
  if run_accept "$dir" "commit-fail" "$attempt"; then
    fail "commit failure was accepted"
  fi
  assert_json_error_contains "$dir/accept-commit-fail.out" "fake signing program invoked"
  [[ "$(fixture_git "$dir/repo" log --format=%B | grep -c "Spec-Drive-Attempt: $attempt" || true)" == "0" ]] || fail "failed commit created trailer"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const attempt = state.attempts[process.argv[2]];
    if (attempt.state === "accepted" || attempt.promotion.stage !== "target_verified") process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" "$attempt" || fail "commit failure did not preserve resumable target_verified state"
  git -C "$dir/repo" config commit.gpgsign false
  git -C "$dir/repo" config --unset gpg.program || true
  run_resume "$dir" "resume" || fail "temporary commit failure did not resume: $(cat "$dir/resume-resume.err")"
  assert_alpha_accepted_once "$dir" "$attempt" "$dir/resume-resume.out"

  dir="$TMP_ROOT/crash-hook-tree-change"
  attempt="$(prepare_alpha_attempt "$dir")"
  mkdir -p "$dir/repo/.git/hooks"
  cat > "$dir/repo/.git/hooks/pre-commit" <<'EOF_HOOK'
#!/usr/bin/env bash
printf 'hook-mutated\n' > src/alpha.txt
git add src/alpha.txt
EOF_HOOK
  chmod +x "$dir/repo/.git/hooks/pre-commit"
  if run_accept "$dir" "hook" "$attempt"; then
    fail "hook tree mutation was accepted"
  fi
  assert_json_error_contains "$dir/accept-hook.out" "tree does not match verified target tree"
  [[ "$(cat "$dir/repo/src/alpha.txt")" == "hook-mutated" ]] || fail "hook mutation bytes were lost"
  if run_resume "$dir" "hook-resume"; then
    fail "incompatible hook commit was reconciled"
  fi
  assert_json_error_contains "$dir/resume-hook-resume.out" "existing accepted commit tree does not match"
  [[ "$(fixture_git "$dir/repo" log --format=%B | grep -c "Spec-Drive-Attempt: $attempt")" == "1" ]] || fail "hook failure created duplicate commits"

  dir="$TMP_ROOT/crash-corrupt-patch-hash"
  attempt="$(prepare_alpha_attempt "$dir")"
  if run_accept_crash "$dir" "intent" "$attempt" "after-intent"; then
    fail "after-intent did not inject a crash"
  fi
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    state.attempts[process.argv[2]].promotion.patchSha256 = "0".repeat(64);
    fs.writeFileSync(file, JSON.stringify(state, null, 2) + "\n");
  ' "$dir/spec/.spec-drive-state.json" "$attempt"
  if run_resume "$dir" "corrupt"; then
    fail "corrupt patch hash was resumed"
  fi
  assert_json_error_contains "$dir/resume-corrupt.out" "patch hash"
  [[ ! -e "$dir/repo/src/alpha.txt" ]] || fail "corrupt patch recovery touched target"

  dir="$TMP_ROOT/crash-symlink-recovery"
  attempt="$(prepare_alpha_attempt "$dir")"
  if run_accept_crash "$dir" "intent" "$attempt" "after-intent"; then
    fail "after-intent symlink did not inject a crash"
  fi
  rm -f "$dir/repo/src/alpha.txt"
  ln -s "../external-alpha.txt" "$dir/repo/src/alpha.txt"
  if run_resume "$dir" "symlink"; then
    fail "symlink recovery was accepted"
  fi
  assert_json_error_contains "$dir/resume-symlink.out" "external changes"
  [[ "$(readlink "$dir/repo/src/alpha.txt")" == "../external-alpha.txt" ]] || fail "symlink recovery overwrote target symlink"

  dir="$TMP_ROOT/crash-partial-external"
  attempt="$(prepare_alpha_attempt "$dir")"
  if run_accept_crash "$dir" "patch" "$attempt" "after-patch"; then
    fail "after-patch partial did not inject a crash"
  fi
  printf 'external bytes\n' > "$dir/repo/src/alpha.txt"
  if run_resume "$dir" "partial"; then
    fail "partial external target was accepted"
  fi
  assert_json_error_contains "$dir/resume-partial.out" "before/after manifests"
  [[ "$(cat "$dir/repo/src/alpha.txt")" == "external bytes" ]] || fail "partial external bytes were lost"
  [[ "$(fixture_git "$dir/repo" log --format=%B | grep -c "Spec-Drive-Attempt: $attempt" || true)" == "0" ]] || fail "partial external recovery created a commit"

  dir="$TMP_ROOT/crash-foreign-branch-trailer"
  attempt="$(prepare_alpha_attempt "$dir")"
  if run_accept_crash "$dir" "verify" "$attempt" "after-verify"; then
    fail "after-verify foreign did not inject a crash"
  fi
  fixture_git "$dir/repo" switch -q -c foreign-trailer
  fixture_git "$dir/repo" add src/alpha.txt
  fixture_git "$dir/repo" commit -q -m "foreign accepted" -m "Spec-Drive-Attempt: $attempt"
  fixture_git "$dir/repo" switch -q -
  [[ ! -e "$dir/repo/src/alpha.txt" ]] || fail "foreign branch checkout did not restore target"
  run_resume "$dir" "foreign" || fail "foreign branch trailer blocked valid resume: $(cat "$dir/resume-foreign.err")"
  assert_alpha_accepted_once "$dir" "$attempt" "$dir/resume-foreign.out"

  dir="$TMP_ROOT/crash-ancestor-trailer"
  attempt="$(prepare_alpha_attempt "$dir")"
  if run_accept_crash "$dir" "commit" "$attempt" "after-commit-before-state"; then
    fail "after-commit-before-state ancestor did not inject a crash"
  fi
  fixture_git "$dir/repo" commit --allow-empty -q -m "external after accepted trailer"
  if run_resume "$dir" "ancestor"; then
    fail "ancestor trailer was reconciled as current acceptance"
  fi
  assert_json_error_contains "$dir/resume-ancestor.out" "not current target HEAD"
  [[ "$(fixture_git "$dir/repo" log --format=%B | grep -c "Spec-Drive-Attempt: $attempt")" == "1" ]] || fail "ancestor recovery created duplicate commits"

  dir="$TMP_ROOT/crash-dirty-after-commit"
  attempt="$(prepare_alpha_attempt "$dir")"
  if run_accept_crash "$dir" "commit" "$attempt" "after-commit-before-state"; then
    fail "after-commit-before-state dirty did not inject a crash"
  fi
  printf 'dirty after commit\n' > "$dir/repo/src/alpha.txt"
  if run_resume "$dir" "dirty-after-commit"; then
    fail "dirty target after accepted commit was reconciled"
  fi
  assert_json_error_contains "$dir/resume-dirty-after-commit.out" "external changes"
  [[ "$(cat "$dir/repo/src/alpha.txt")" == "dirty after commit" ]] || fail "dirty after commit bytes were lost"
  [[ "$(fixture_git "$dir/repo" log --format=%B | grep -c "Spec-Drive-Attempt: $attempt")" == "1" ]] || fail "dirty after commit recovery created duplicate commits"

  dir="$TMP_ROOT/crash-missing-target-verify"
  attempt="$(prepare_alpha_attempt "$dir")"
  if run_accept_crash "$dir" "verify" "$attempt" "after-verify"; then
    fail "after-verify missing target Verify did not inject a crash"
  fi
  fixture_git "$dir/repo" add src/alpha.txt
  fixture_git "$dir/repo" commit -q -m "accepted without durable verify" -m "Spec-Drive-Attempt: $attempt"
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    state.attempts[process.argv[2]].promotion.targetVerify = null;
    fs.writeFileSync(file, JSON.stringify(state, null, 2) + "\n");
  ' "$dir/spec/.spec-drive-state.json" "$attempt"
  if run_resume "$dir" "missing-target-verify"; then
    fail "missing target Verify record was reconciled"
  fi
  assert_json_error_contains "$dir/resume-missing-target-verify.out" "missing target Verify record"
  [[ "$(fixture_git "$dir/repo" log --format=%B | grep -c "Spec-Drive-Attempt: $attempt")" == "1" ]] || fail "missing Verify recovery created duplicate commits"

  dir="$TMP_ROOT/crash-forged-target-verify"
  attempt="$(prepare_alpha_attempt "$dir")"
  if run_accept_crash "$dir" "verify" "$attempt" "after-verify"; then
    fail "after-verify forged target Verify did not inject a crash"
  fi
  fixture_git "$dir/repo" add src/alpha.txt
  fixture_git "$dir/repo" commit -q -m "accepted with forged verify" -m "Spec-Drive-Attempt: $attempt"
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    state.attempts[process.argv[2]].promotion.targetVerify.command = "true";
    fs.writeFileSync(file, JSON.stringify(state, null, 2) + "\n");
  ' "$dir/spec/.spec-drive-state.json" "$attempt"
  if run_resume "$dir" "forged-target-verify"; then
    fail "forged target Verify record was reconciled"
  fi
  assert_json_error_contains "$dir/resume-forged-target-verify.out" "Verify record does not match"
  [[ "$(fixture_git "$dir/repo" log --format=%B | grep -c "Spec-Drive-Attempt: $attempt")" == "1" ]] || fail "forged Verify recovery created duplicate commits"

  dir="$TMP_ROOT/crash-wrong-parent-trailer"
  attempt="$(prepare_alpha_attempt "$dir")"
  if run_accept_crash "$dir" "verify" "$attempt" "after-verify"; then
    fail "after-verify wrong-parent did not inject a crash"
  fi
  fixture_git "$dir/repo" reset -q HEAD -- src/alpha.txt
  fixture_git "$dir/repo" commit --allow-empty -q -m "external parent"
  fixture_git "$dir/repo" add src/alpha.txt
  fixture_git "$dir/repo" commit -q -m "wrong parent" -m "Spec-Drive-Attempt: $attempt"
  if run_resume "$dir" "wrong-parent"; then
    fail "wrong-parent trailer was reconciled"
  fi
  assert_json_error_contains "$dir/resume-wrong-parent.out" "parent does not match"

  dir="$TMP_ROOT/crash-multiple-trailers"
  attempt="$(prepare_alpha_attempt "$dir")"
  if run_accept_crash "$dir" "verify" "$attempt" "after-verify"; then
    fail "after-verify multiple did not inject a crash"
  fi
  fixture_git "$dir/repo" add src/alpha.txt
  fixture_git "$dir/repo" commit -q -m "accepted once" -m "Spec-Drive-Attempt: $attempt"
  fixture_git "$dir/repo" commit --allow-empty -q -m "accepted twice" -m "Spec-Drive-Attempt: $attempt"
  if run_resume "$dir" "multiple"; then
    fail "multiple exact trailers were reconciled"
  fi
  assert_json_error_contains "$dir/resume-multiple.out" "multiple accepted commits"

  dir="$TMP_ROOT/crash-similar-prefix-trailer"
  attempt="$(prepare_alpha_attempt "$dir")"
  if run_accept_crash "$dir" "verify" "$attempt" "after-verify"; then
    fail "after-verify similar-prefix did not inject a crash"
  fi
  fixture_git "$dir/repo" add src/alpha.txt
  fixture_git "$dir/repo" commit -q -m "similar prefix" -m "Spec-Drive-Attempt: $attempt-extra"
  if run_resume "$dir" "similar"; then
    fail "similar-prefix trailer was treated as exact"
  fi
  assert_json_error_contains "$dir/resume-similar.out" "target HEAD changed"

  dir="$TMP_ROOT/crash-checkpoint-projection-repair"
  write_flow_fixture "$dir"
  approve_all "$dir"
  accept_code_task "$dir" "checkpoint-alpha" "1.1" "src/alpha.txt" "alpha"
  accept_code_task "$dir" "checkpoint-beta" "1.2" "src/tracked name.txt" "beta"
  run_next "$dir" "checkpoint-next" || fail "checkpoint repair next failed: $(cat "$dir/next-checkpoint-next.err")"
  attempt="$(json_get "$dir/next-checkpoint-next.out" "dispatch.attemptId")"
  run_report "$dir" "checkpoint-report" "$attempt" "V1" "task_complete" "none" "started" "true" \
    || fail "checkpoint repair report failed: $(cat "$dir/report-checkpoint-report.err")"
  rm -f "$dir/spec/.progress.md"
  mkdir "$dir/spec/.progress.md"
  if run_accept "$dir" "checkpoint-projection-fail" "$attempt"; then
    fail "checkpoint projection failure accepted cleanly"
  fi
  assert_json_error_contains "$dir/accept-checkpoint-projection-fail.out" "EISDIR"
  rmdir "$dir/spec/.progress.md"
  run_resume "$dir" "checkpoint-projection" || fail "checkpoint projection resume failed: $(cat "$dir/resume-checkpoint-projection.err")"
  assert_json_ok "$dir/resume-checkpoint-projection.out"
  grep -q '^- \[x\] V1 \[VERIFY\] Check final flow' "$dir/spec/tasks.md" || fail "checkpoint projection recovery missing checkbox"
  grep -q 'V1: accepted' "$dir/spec/.progress.md" || fail "checkpoint projection recovery missing progress"
}

ownership_poc() {
  local dir attempt worktree retry_attempt retry_worktree

  dir="$TMP_ROOT/ownership-logic-preserve"
  write_flow_fixture "$dir"
  approve_all "$dir"
  run_next "$dir" "first" || fail "ownership logic first next failed: $(cat "$dir/next-first.err")"
  attempt="$(json_get "$dir/next-first.out" "dispatch.attemptId")"
  worktree="$(json_get "$dir/next-first.out" "dispatch.worktreePath")"
  mkdir -p "$worktree/src"
  printf 'partial-own\n' > "$worktree/src/alpha.txt"
  run_report "$dir" "logic" "$attempt" "1.1" "task_blocked" "logic_error" "started" "true" \
    || fail "ownership logic report failed: $(cat "$dir/report-logic.err")"
  run_next "$dir" "retry" || fail "ownership logic retry failed: $(cat "$dir/next-retry.err")"
  retry_attempt="$(json_get "$dir/next-retry.out" "dispatch.attemptId")"
  retry_worktree="$(json_get "$dir/next-retry.out" "dispatch.worktreePath")"
  [[ "$retry_attempt" != "$attempt" ]] || fail "logic retry reused attemptId"
  [[ "$retry_worktree" == "$worktree" ]] || fail "logic retry did not preserve worktree"
  [[ "$(cat "$worktree/src/alpha.txt")" == "partial-own" ]] || fail "logic retry lost owned worktree bytes"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const task = state.taskStates["1.1"];
    if (task.executionAttempts !== 2 || state.budgets.globalBudgetUsed !== 2) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" || fail "logic retry reset budgets"

  dir="$TMP_ROOT/ownership-worktree-drift"
  write_flow_fixture "$dir"
  approve_all "$dir"
  run_next "$dir" "first" || fail "worktree drift first next failed: $(cat "$dir/next-first.err")"
  attempt="$(json_get "$dir/next-first.out" "dispatch.attemptId")"
  worktree="$(json_get "$dir/next-first.out" "dispatch.worktreePath")"
  mkdir -p "$worktree/src"
  printf 'partial-own\n' > "$worktree/src/alpha.txt"
  run_report "$dir" "logic" "$attempt" "1.1" "task_blocked" "logic_error" "started" "true" \
    || fail "worktree drift report failed: $(cat "$dir/report-logic.err")"
  printf 'external drift\n' > "$worktree/src/external-drift.txt"
  if run_next "$dir" "retry"; then
    fail "worktree drift allowed retry"
  fi
  assert_json_error_contains "$dir/next-retry.out" "ownership manifest changed"
  [[ "$(cat "$worktree/src/alpha.txt")" == "partial-own" ]] || fail "worktree drift lost owned bytes"
  [[ "$(cat "$worktree/src/external-drift.txt")" == "external drift" ]] || fail "worktree drift lost external bytes"

  dir="$TMP_ROOT/ownership-target-drift"
  write_flow_fixture "$dir"
  approve_all "$dir"
  run_next "$dir" "first" || fail "target drift first next failed: $(cat "$dir/next-first.err")"
  attempt="$(json_get "$dir/next-first.out" "dispatch.attemptId")"
  worktree="$(json_get "$dir/next-first.out" "dispatch.worktreePath")"
  mkdir -p "$worktree/src"
  printf 'partial-own\n' > "$worktree/src/alpha.txt"
  run_report "$dir" "logic" "$attempt" "1.1" "task_blocked" "logic_error" "started" "true" \
    || fail "target drift report failed: $(cat "$dir/report-logic.err")"
  printf 'external target\n' > "$dir/repo/src/external-target.txt"
  if run_next "$dir" "retry"; then
    fail "target untracked drift allowed retry"
  fi
  assert_json_error_contains "$dir/next-retry.out" "external changes"
  [[ "$(cat "$dir/repo/src/external-target.txt")" == "external target" ]] || fail "target drift bytes were lost"

  dir="$TMP_ROOT/ownership-env-recover"
  write_flow_fixture "$dir"
  approve_all "$dir"
  run_next "$dir" "first" || fail "env recover first next failed: $(cat "$dir/next-first.err")"
  attempt="$(json_get "$dir/next-first.out" "dispatch.attemptId")"
  worktree="$(json_get "$dir/next-first.out" "dispatch.worktreePath")"
  mkdir -p "$worktree/src"
  printf 'env-owned\n' > "$worktree/src/alpha.txt"
  run_report "$dir" "env" "$attempt" "1.1" "task_blocked" "env_error" "started" "true" \
    || fail "env report failed: $(cat "$dir/report-env.err")"
  if run_next "$dir" "before-recover"; then
    fail "env_error allowed retry without recovery"
  fi
  assert_json_error_contains "$dir/next-before-recover.out" "requires recovery"
  if run_recover "$dir" "short" "$attempt" "fixed"; then
    fail "short recovery evidence was accepted"
  fi
  assert_json_error_contains "$dir/recover-short.out" "explicit recovery evidence"
  run_recover "$dir" "env" "$attempt" "executor ended and missing runtime was restored" \
    || fail "env recover failed: $(cat "$dir/recover-env.err")"
  assert_json_ok "$dir/recover-env.out"
  run_next "$dir" "after-recover" || fail "env retry after recover failed: $(cat "$dir/next-after-recover.err")"
  retry_attempt="$(json_get "$dir/next-after-recover.out" "dispatch.attemptId")"
  retry_worktree="$(json_get "$dir/next-after-recover.out" "dispatch.worktreePath")"
  [[ "$retry_attempt" != "$attempt" ]] || fail "env retry reused attemptId"
  [[ "$retry_worktree" == "$worktree" ]] || fail "env retry did not preserve worktree"
  [[ "$(cat "$worktree/src/alpha.txt")" == "env-owned" ]] || fail "env retry lost owned bytes"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const task = state.taskStates["1.1"];
    if (task.executionAttempts !== 2 || state.budgets.globalBudgetUsed !== 2) process.exit(1);
    if (!state.attempts[process.argv[2]].recovery) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" "$attempt" || fail "env recovery reset or lost counters"

  dir="$TMP_ROOT/ownership-indeterminate-late"
  write_flow_fixture "$dir"
  approve_all "$dir"
  run_next "$dir" "first" || fail "indeterminate first next failed: $(cat "$dir/next-first.err")"
  attempt="$(json_get "$dir/next-first.out" "dispatch.attemptId")"
  worktree="$(json_get "$dir/next-first.out" "dispatch.worktreePath")"
  mkdir -p "$worktree/src"
  printf 'uncertain-owned\n' > "$worktree/src/alpha.txt"
  run_report "$dir" "unknown" "$attempt" "1.1" "task_blocked" "logic_error" "unknown" "false" \
    || fail "indeterminate report failed: $(cat "$dir/report-unknown.err")"
  if run_next "$dir" "before-recover"; then
    fail "indeterminate allowed automatic redispatch"
  fi
  assert_json_error_contains "$dir/next-before-recover.out" "requires recovery"
  run_recover "$dir" "unknown" "$attempt" "executor process tree confirmed ended" \
    || fail "indeterminate recover failed: $(cat "$dir/recover-unknown.err")"
  run_next "$dir" "after-recover" || fail "indeterminate retry after recover failed: $(cat "$dir/next-after-recover.err")"
  retry_attempt="$(json_get "$dir/next-after-recover.out" "dispatch.attemptId")"
  run_report "$dir" "late" "$attempt" "1.1" "task_complete" "none" "started" "true" \
    || fail "late abandoned report returned error: $(cat "$dir/report-late.err")"
  node -e '
    const fs = require("fs");
    const late = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const state = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    if (late.report !== "late_ignored") process.exit(1);
    if (state.activeAttemptId !== process.argv[3] || state.currentStage !== "dispatching") process.exit(1);
  ' "$dir/report-late.out" "$dir/spec/.spec-drive-state.json" "$retry_attempt" || fail "late abandoned report modified current state"

  dir="$TMP_ROOT/ownership-blocked-classes"
  write_flow_fixture "$dir"
  approve_all "$dir"
  run_next "$dir" "verify" || fail "blocked class next failed: $(cat "$dir/next-verify.err")"
  attempt="$(json_get "$dir/next-verify.out" "dispatch.attemptId")"
  run_report "$dir" "verify" "$attempt" "1.1" "task_blocked" "verify_error" "started" "true" \
    || fail "verify_error report failed: $(cat "$dir/report-verify.err")"
  if run_next "$dir" "after-verify"; then
    fail "verify_error allowed same-plan retry"
  fi
  assert_json_error_contains "$dir/next-after-verify.out" "requires recovery"

  dir="$TMP_ROOT/ownership-pause"
  write_flow_fixture "$dir"
  approve_all "$dir"
  run_next "$dir" "first" || fail "pause first next failed: $(cat "$dir/next-first.err")"
  attempt="$(json_get "$dir/next-first.out" "dispatch.attemptId")"
  run_pause "$dir" "active" "operator cancelled without deleting work" || fail "pause failed: $(cat "$dir/pause-active.err")"
  assert_json_ok "$dir/pause-active.out"
  node -e '
    const fs = require("fs");
    const state = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (!state.paused || state.paused.activeAttemptId !== process.argv[2]) process.exit(1);
    if (state.taskStates["1.1"].executionAttempts !== 1 || state.budgets.globalBudgetUsed !== 1) process.exit(1);
  ' "$dir/spec/.spec-drive-state.json" "$attempt" || fail "pause reset counters or lost active attempt"
  run_resume "$dir" "paused" || fail "paused ledger did not resume: $(cat "$dir/resume-paused.err")"
  assert_json_ok "$dir/resume-paused.out"
  node -e '
    const fs = require("fs");
    const resumed = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const state = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    if (resumed.ledger.currentTaskId !== "1.1" || resumed.ledger.activeAttemptId !== process.argv[3]) process.exit(1);
    if (state.taskStates["1.1"].executionAttempts !== 1 || state.budgets.globalBudgetUsed !== 1) process.exit(1);
  ' "$dir/resume-paused.out" "$dir/spec/.spec-drive-state.json" "$attempt" || fail "pause/resume changed identity or budgets"
}

all() {
  gate_poc
  contracts_poc
  ledger_poc
  adapters_poc
  flow_poc
  crash_poc
  ownership_poc
}

if [[ $# -eq 0 ]]; then
  set -- all
fi

for mode in "$@"; do
  case "$mode" in
    gate-poc) gate_poc ;;
    ledger-poc) ledger_poc ;;
    flow-poc) flow_poc ;;
    crash) crash_poc ;;
    ownership) ownership_poc ;;
    contracts) contracts_poc ;;
    adapters) adapters_poc ;;
    all) all ;;
    *) fail "unknown mode: $mode" ;;
  esac
done
