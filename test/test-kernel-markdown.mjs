#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const root = mkdtempSync(path.join(tmpdir(), "spec-drive-kernel-markdown-"));
const kernel = path.resolve(import.meta.dirname, "../hooks/scripts/execution-kernel.mjs");
const repo = path.join(root, "repo");
const spec = path.join(repo, "spec");

function digest(text) {
  return createHash("sha256").update(text).digest("hex");
}

function call(op, extra = {}) {
  const result = spawnSync(process.execPath, [kernel], {
    input: JSON.stringify({ op, specDir: spec, repoRoot: repo, ...extra }),
    encoding: "utf8",
  });
  assert.equal(result.status, 0, `${op} failed: ${result.stderr}\n${result.stdout}`);
  return JSON.parse(result.stdout);
}

try {
  execFileSync("mkdir", ["-p", path.join(repo, "src"), spec]);
  writeFileSync(path.join(repo, "baseline.txt"), "baseline\n");
  execFileSync("git", ["-C", repo, "init", "-q"]);
  execFileSync("git", ["-C", repo, "config", "user.name", "Kernel Markdown Fixture"]);
  execFileSync("git", ["-C", repo, "config", "user.email", "kernel-markdown@example.invalid"]);

  const requirements = [
    "---", "spec: markdown", "phase: requirements", "status: complete", "---", "",
    "# Requirements", "- AC-1.1: Verify commands execute.", "- NFR-1: Preserve parser syntax.", "",
  ].join("\r\n");
  const design = [
    "---", "spec: markdown", "phase: design", "status: complete", `requirements_sha: ${digest(requirements)}`, "---", "",
    "# Design", "AC-1.1 NFR-1", "",
  ].join("\r\n");
  const tasks = [
    "---", "spec: markdown", "phase: tasks", "status: complete", `requirements_sha: ${digest(requirements)}`, `design_sha: ${digest(design)}`, "---", "",
    "<!--", "- [ ] V9 fake task", "  - **Verify**: printf should-not-run", "-->",
    "```text", "- [ ] V8 fenced task", "  - **Verify**: printf should-not-run", "```", "",
    "- [ ] V1 [VERIFY] Run markdown Verify", "  - **Do**: Execute the fixture check.", "  - **Files**: none", "  - **Traces**: AC-1.1, NFR-1", "  - **Cwd**: .", "  - **Done when**: The wrapped command passes.",
    "  - **Verify**: `test \"$(printf `printf check-ok`)\" = check-ok`", "  - **Timeout**: 10", "  - **Commit**: none", "",
    "- [ ] V2 [VERIFY] Run second markdown Verify", "  - **Do**: Execute the second fixture check.", "  - **Files**: none", "  - **Traces**: AC-1.1, NFR-1", "  - **Cwd**: .", "  - **Done when**: The second wrapped command passes.",
    "  - **Verify**: `test \"$(printf `printf check-ok`)\" = check-ok`", "  - **Timeout**: 10", "  - **Commit**: none", "",
  ].join("\r\n");
  writeFileSync(path.join(spec, "requirements.md"), requirements);
  writeFileSync(path.join(spec, "design.md"), design);
  writeFileSync(path.join(spec, "tasks.md"), tasks);
  writeFileSync(path.join(spec, ".spec-drive-state.json"), JSON.stringify({
    name: "markdown", basePath: spec, phase: "tasks", mode: "normal", awaitingApproval: false, schemaVersion: 2,
  }));
  execFileSync("git", ["-C", repo, "add", "."]);
  execFileSync("git", ["-C", repo, "-c", "commit.gpgsign=false", "-c", "tag.gpgSign=false", "commit", "-qm", "fixture baseline"]);

  for (const [artifact, text] of Object.entries({ requirements, design, tasks })) {
    const approved = call("approve", {
      artifact,
      expectedSha256: digest(text),
      approvalEvidence: `fixture approval for ${artifact}`,
    });
    assert.equal(approved.ok, true);
  }

  const preflight = call("preflight");
  assert.deepEqual(preflight.plan.taskOrder, ["V1", "V2"]);
  assert.equal(readFileSync(path.join(spec, "tasks.md"), "utf8"), tasks);

  function completeCheckpoint(expectedTaskId) {
    const dispatch = call("next", { actor: "implement" }).dispatch;
    assert.equal(dispatch.taskId, expectedTaskId);
    assert.equal(dispatch.verify.command, "test \"$(printf `printf check-ok`)\" = check-ok");
    assert.equal(call("report", {
      attemptId: dispatch.attemptId,
      adapterEvidence: "started",
      report: {
        attemptId: dispatch.attemptId,
        taskId: dispatch.taskId,
        outcome: "task_complete",
        startedWork: true,
        summary: "fixture completed",
      },
    }).ok, true);
    assert.equal(call("accept", { attemptId: dispatch.attemptId }).ok, true);
  }
  completeCheckpoint("V1");
  assert.equal(call("resume").ledger.currentTaskId, "V2");
  completeCheckpoint("V2");
  assert.equal(call("resume").ledger.currentTaskId, null);
  console.log("kernel markdown Verify test passed");
} finally {
  rmSync(root, { recursive: true, force: true });
}
