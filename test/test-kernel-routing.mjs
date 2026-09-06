#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const kernel = path.join(root, "hooks/scripts/execution-kernel.mjs");

function sha(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

function call(request, env = {}) {
  const result = spawnSync(process.execPath, [kernel], {
    input: JSON.stringify(request),
    encoding: "utf8",
    env: { ...process.env, ...env },
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return JSON.parse(result.stdout);
}

function git(repo, ...args) {
  execFileSync("git", ["-C", repo, ...args], { stdio: "ignore" });
}

function fixture(name, model) {
  const dir = mkdtempSync(path.join(tmpdir(), `spec-drive-routing-${name}-`));
  const spec = path.join(dir, "spec");
  const repo = path.join(dir, "repo");
  mkdirSync(path.join(repo, "src"), { recursive: true });
  mkdirSync(spec, { recursive: true });
  writeFileSync(path.join(spec, "requirements.md"), `---\nspec: "${name}"\nphase: requirements\nstatus: complete\n---\n\n# Requirements\n\n## User Stories\n\n#### US-1: routing\n**Acceptance Criteria:**\n- [ ] AC-1.1: Routing is resolved before dispatch.\n\n## Functional Requirements\n\n| ID | Description | Priority | Verification |\n| --- | --- | --- | --- |\n| FR-1 | Use the configured adapter. | High | fixture |\n\n## Non-Functional Requirements\n\n- NFR-1: Ledger state is durable.\n`);
  const requirementsSha = sha(path.join(spec, "requirements.md"));
  writeFileSync(path.join(spec, "design.md"), `---\nspec: "${name}"\nphase: design\nstatus: complete\nrequirements_sha: "${requirementsSha}"\n---\n\n# Design\n\n## Coverage\n\n| Source | Design target |\n| --- | --- |\n| AC-1.1 | Routing |\n| FR-1 | Routing |\n| NFR-1 | Ledger |\n`);
  const designSha = sha(path.join(spec, "design.md"));
  const modelLine = model ? `  - **model**: ${model}\n` : "";
  writeFileSync(path.join(spec, "tasks.md"), `---\nspec: "${name}"\nphase: tasks\nstatus: complete\nrequirements_sha: "${requirementsSha}"\ndesign_sha: "${designSha}"\n---\n\n# Tasks\n\n- [ ] 1.1 Write routed output\n  - **Do**: Write the fixture output.\n  - **Files**: src/output.txt\n  - **Traces**: AC-1.1, FR-1, NFR-1\n${modelLine}  - **Cwd**: .\n  - **Done when**: The output exists.\n  - **Verify**: test "$(cat src/output.txt)" = routed\n  - **Timeout**: 30\n  - **Commit**: feat: routed output\n`);
  git(repo, "init", "-q");
  git(repo, "config", "user.name", "Fixture");
  git(repo, "config", "user.email", "fixture@example.invalid");
  git(repo, "config", "commit.gpgsign", "false");
  git(repo, "config", "tag.gpgSign", "false");
  writeFileSync(path.join(repo, "README.md"), "fixture\n");
  git(repo, "add", ".");
  git(repo, "commit", "-qm", "baseline");
  return { dir, spec, repo };
}

function approveAll(fixtureDir, env) {
  for (const artifact of ["requirements", "design", "tasks"]) {
    const file = path.join(fixtureDir.spec, `${artifact}.md`);
    const response = call({
      op: "approve",
      specDir: fixtureDir.spec,
      artifact,
      expectedSha256: sha(file),
      approvalEvidence: "routing fixture approval",
    }, env);
    assert.equal(response.ok, true);
  }
}

function assertRouting(name, model, env, expected) {
  const f = fixture(name, model);
  env = { ...env, XDG_CONFIG_HOME: path.join(f.dir, "config") };
  try {
    approveAll(f, env);
    const dispatched = call({ op: "next", specDir: f.spec, repoRoot: f.repo, actor: "implement" }, env);
    assert.equal(dispatched.ok, true);
    assert.deepEqual(
      {
        mechanism: dispatched.dispatch.mechanism,
        model: dispatched.dispatch.model,
        cmd: dispatched.dispatch.cmd,
      },
      expected,
    );
    const executing = JSON.parse(readFileSync(path.join(f.spec, ".spec-drive-state.json"), "utf8"));
    assert.equal(executing.phase, "execution", "next persists execution for the stop watcher");

    mkdirSync(path.join(dispatched.dispatch.worktreePath, "src"), { recursive: true });
    writeFileSync(path.join(dispatched.dispatch.worktreePath, "src/output.txt"), "routed\n");
    const reported = call({
      op: "report",
      specDir: f.spec,
      repoRoot: f.repo,
      attemptId: dispatched.dispatch.attemptId,
      adapterEvidence: "started",
      report: {
        attemptId: dispatched.dispatch.attemptId,
        taskId: "1.1",
        outcome: "task_complete",
        startedWork: true,
        summary: "fixture wrote output",
      },
    }, env);
    assert.equal(reported.ok, true);
    const accepted = call({ op: "accept", specDir: f.spec, repoRoot: f.repo, attemptId: dispatched.dispatch.attemptId }, env);
    assert.equal(accepted.ok, true);
    const completed = JSON.parse(readFileSync(path.join(f.spec, ".spec-drive-state.json"), "utf8"));
    assert.equal(completed.phase, "completed");
    assert.equal(completed.currentTaskId, null);
    assert.equal(completed.currentStage, "completed");
    const status = call({ op: "status", specDir: f.spec }, env);
    const resumed = call({ op: "resume", specDir: f.spec, repoRoot: f.repo }, env);
    assert.equal(status.status.currentTaskId, null);
    assert.equal(status.status.currentStage, "completed");
    assert.equal(resumed.ledger.currentTaskId, null);
    assert.equal(resumed.ledger.currentStage, "completed");
  } finally {
    rmSync(f.dir, { recursive: true, force: true });
  }
}

assertRouting("claude-agent", "advanced", { CLAUDE_PLUGIN_ROOT: root, CODEX_HOME: "" }, {
  mechanism: "agent",
  model: "opus",
  cmd: "",
});
assertRouting("codex-subprocess", "advanced", { CLAUDE_PLUGIN_ROOT: "", CODEX_HOME: "/fixture/codex" }, {
  mechanism: "subprocess",
  model: "",
  cmd: "codex exec -m gpt-5.5 -s workspace-write -- < {promptfile}",
});
assertRouting("inherit", null, { CLAUDE_PLUGIN_ROOT: "", CODEX_HOME: "/fixture/codex" }, {
  mechanism: "inherit",
  model: "",
  cmd: "",
});

console.log("kernel routing lifecycle fixtures passed");
