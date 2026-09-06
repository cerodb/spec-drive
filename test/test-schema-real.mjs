#!/usr/bin/env node
// Validate persisted kernel states with the published JSON Schema, not a hand-written subset.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const kernel = path.join(root, "hooks/scripts/execution-kernel.mjs");
const schema = JSON.parse(readFileSync(path.join(root, "schemas/spec-drive.schema.json"), "utf8"));
const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
const validate = ajv.compile(schema);

function sha(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

function writeFixture(dir) {
  const spec = path.join(dir, "spec");
  const repo = path.join(dir, "repo");
  mkdirSync(path.join(repo, "src"), { recursive: true });
  mkdirSync(spec, { recursive: true });
  writeFileSync(path.join(spec, "requirements.md"), `---\nspec: fixture\nphase: requirements\nstatus: complete\n---\n\n# Requirements\n\n## User Stories\n\n#### US-1: A valid release fixture\n**Acceptance Criteria:**\n- [ ] AC-1.1: Code is accepted after Verify.\n- [ ] AC-1.2: Recovery preserves ledger state.\n\n## Functional Requirements\n\n| ID | Description | Priority | Verification |\n| --- | --- | --- | --- |\n| FR-1 | The kernel stores durable state. | High | fixture |\n\n## Non-Functional Requirements\n\n- NFR-1: State remains portable.\n`);
  const requirementsSha = sha(path.join(spec, "requirements.md"));
  writeFileSync(path.join(spec, "design.md"), `---\nspec: fixture\nphase: design\nstatus: complete\nrequirements_sha: \"${requirementsSha}\"\n---\n\n# Design\n\n| Source | Design target |\n| --- | --- |\n| AC-1.1 | Kernel |\n| AC-1.2 | Kernel |\n| FR-1 | Kernel |\n| NFR-1 | Kernel |\n`);
  const designSha = sha(path.join(spec, "design.md"));
  writeFileSync(path.join(spec, "tasks.md"), `---\nspec: fixture\nphase: tasks\nstatus: complete\nrequirements_sha: \"${requirementsSha}\"\ndesign_sha: \"${designSha}\"\n---\n\n# Tasks\n\n- [ ] 1.1 Write alpha\n  - **Do**: Write alpha.\n  - **Files**: src/alpha.txt\n  - **Traces**: AC-1.1, AC-1.2, FR-1, NFR-1\n  - **Cwd**: .\n  - **Done when**: alpha exists.\n  - **Verify**: test \"$(cat src/alpha.txt)\" = alpha\n  - **Timeout**: 30\n  - **Commit**: feat: alpha\n`);
  execFileSync("git", ["init", "-q", repo]);
  execFileSync("git", ["-C", repo, "config", "user.name", "Schema fixture"]);
  execFileSync("git", ["-C", repo, "config", "user.email", "schema@example.invalid"]);
  execFileSync("git", ["-C", repo, "config", "commit.gpgsign", "false"]);
  execFileSync("git", ["-C", repo, "config", "tag.gpgSign", "false"]);
  execFileSync("git", ["-C", repo, "add", "."]);
  execFileSync("git", ["-C", repo, "commit", "--allow-empty", "-q", "-m", "baseline"]);
  return { spec, repo };
}

function call(payload) {
  const result = spawnSync(process.execPath, [kernel], { input: JSON.stringify(payload), encoding: "utf8" });
  assert.equal(result.error, undefined, result.error?.message);
  const response = JSON.parse(result.stdout);
  assert.equal(response.ok, true, result.stderr || JSON.stringify(response));
  return response;
}

function state(spec) {
  return JSON.parse(readFileSync(path.join(spec, ".spec-drive-state.json"), "utf8"));
}

function valid(label, data) {
  assert.equal(validate(data), true, `${label}: ${ajv.errorsText(validate.errors, { separator: "\n" })}`);
}

function invalid(label, data) {
  assert.equal(validate(data), false, `${label}: expected schema rejection`);
}

function approveAll(spec) {
  for (const artifact of ["requirements", "design", "tasks"]) {
    const file = path.join(spec, `${artifact}.md`);
    call({ op: "approve", specDir: spec, artifact, expectedSha256: sha(file), approvalEvidence: "fixture approval evidence" });
    valid(`approve ${artifact}`, state(spec));
  }
}

const tmp = mkdtempSync(path.join(tmpdir(), "spec-drive-schema-real-"));
try {
  const accepted = writeFixture(path.join(tmp, "accepted"));
  approveAll(accepted.spec);
  const dispatch = call({ op: "next", specDir: accepted.spec, repoRoot: accepted.repo, actor: "implement" }).dispatch;
  valid("next dispatch", state(accepted.spec));
  mkdirSync(path.join(dispatch.worktreePath, "src"), { recursive: true });
  writeFileSync(path.join(dispatch.worktreePath, "src", "alpha.txt"), "alpha\n");
  call({ op: "report", specDir: accepted.spec, repoRoot: accepted.repo, attemptId: dispatch.attemptId, adapterEvidence: "started", report: { attemptId: dispatch.attemptId, taskId: "1.1", outcome: "task_complete", startedWork: true, summary: "alpha written" } });
  valid("report complete", state(accepted.spec));
  call({ op: "accept", specDir: accepted.spec, repoRoot: accepted.repo, attemptId: dispatch.attemptId });
  const acceptedState = state(accepted.spec);
  valid("accept", acceptedState);
  assert.equal(acceptedState.taskStates["1.1"].status, "accepted");

  const recovery = writeFixture(path.join(tmp, "recovery"));
  approveAll(recovery.spec);
  const failed = call({ op: "next", specDir: recovery.spec, repoRoot: recovery.repo, actor: "implement" }).dispatch;
  call({ op: "report", specDir: recovery.spec, repoRoot: recovery.repo, attemptId: failed.attemptId, adapterEvidence: "started", report: { attemptId: failed.attemptId, taskId: "1.1", outcome: "task_blocked", startedWork: true, summary: "runtime unavailable", failureClass: "env_error" } });
  valid("reported failure", state(recovery.spec));
  call({ op: "recover", specDir: recovery.spec, attemptId: failed.attemptId, evidence: "the runtime was restored and the executor exited" });
  valid("recovery", state(recovery.spec));
  call({ op: "pause", specDir: recovery.spec, reason: "fixture pause before resume" });
  valid("paused", state(recovery.spec));
  call({ op: "resume", specDir: recovery.spec, repoRoot: recovery.repo });
  valid("resume", state(recovery.spec));

  const missingActor = structuredClone(acceptedState);
  delete missingActor.attempts[dispatch.attemptId].actor;
  invalid("required attempt actor", missingActor);
  const unknownAttemptField = structuredClone(acceptedState);
  unknownAttemptField.attempts[dispatch.attemptId].unexpected = true;
  invalid("closed attempt object", unknownAttemptField);
  const badTimestamp = structuredClone(acceptedState);
  badTimestamp.attempts[dispatch.attemptId].promotion.targetVerify.stdout = 7;
  invalid("nested verify record type", badTimestamp);

  console.log("Schema real-state validation passed.");
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
