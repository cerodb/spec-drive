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

all() {
  gate_poc
}

if [[ $# -eq 0 ]]; then
  set -- all
fi

for mode in "$@"; do
  case "$mode" in
    gate-poc) gate_poc ;;
    all) all ;;
    *) fail "unknown mode: $mode" ;;
  esac
done
