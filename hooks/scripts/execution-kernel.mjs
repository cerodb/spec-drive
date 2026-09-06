#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdtempSync } from "node:fs";
import {
  closeSync,
  existsSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  openSync,
  readdirSync,
  readlinkSync,
  realpathSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const STATE_FILE = ".spec-drive-state.json";
const ARTIFACTS = {
  requirements: "requirements.md",
  design: "design.md",
  tasks: "tasks.md",
};
const REQUIRED_FIELDS = [
  "Do",
  "Files",
  "Traces",
  "Cwd",
  "Done when",
  "Verify",
  "Timeout",
  "Commit",
];
const OPTIONAL_FIELDS = new Set(["model", "model_used"]);
const ALLOWED_FIELDS = new Set([...REQUIRED_FIELDS, ...OPTIONAL_FIELDS]);
const MODEL_TIERS = new Set(["light", "standard", "advanced", "frontier"]);
const ID_RE = /^(?:\d+\.\d+(?:\.\d+)?|V[1-9]\d*)$/;
const TRACE_RE = /\b(?:AC-\d+\.\d+|FR-\d+|NFR-\d+)\b/g;
const DEFAULT_BUDGETS = {
  maxDispatchFailures: 3,
  maxExecutionAttempts: 5,
  maxGlobalOperations: 100,
};
const MUTABLE_TRACKING_FIELDS = new Set(["model_used"]);
const STATE_METADATA_FIELDS = ["name", "basePath", "phase"];
const STATE_PHASES = new Set(["idea", "research", "requirements", "design", "tasks", "execution", "completed"]);

class KernelFailure extends Error {
  constructor(code, detail, extra = {}) {
    super(detail);
    this.code = code;
    this.detail = detail;
    this.extra = extra;
  }
}

function artifactError(detail, extra) {
  return new KernelFailure("artifact_error", detail, extra);
}

function requestError(detail, extra) {
  return new KernelFailure("request_error", detail, extra);
}

function executionError(detail, extra) {
  return new KernelFailure("execution_error", detail, extra);
}

function externalChangeError(detail, extra) {
  return new KernelFailure("external_change_error", detail, extra);
}

function acceptanceError(detail, extra) {
  return new KernelFailure("acceptance_error", detail, extra);
}

function diagnostic(message) {
  console.error(`[execution-kernel] ${message}`);
}

function respond(payload, exitCode = 0) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
  process.exitCode = exitCode;
}

function errorResponse(err) {
  const code = err instanceof KernelFailure ? err.code : "kernel_error";
  const detail = err instanceof KernelFailure ? err.detail : err.message;
  const exitCodes = {
    artifact_error: 2,
    migration_error: 3,
    dispatch_error: 4,
    execution_error: 5,
    external_change_error: 6,
    acceptance_error: 7,
  };
  const response = {
    ok: false,
    error: {
      code,
      detail,
      recovery: code === "artifact_error"
        ? "Fix artifacts or refresh explicit approvals before dispatch."
        : "Correct the request and retry.",
      ...(err instanceof KernelFailure ? err.extra : {}),
    },
  };
  diagnostic(`${code}: ${detail}`);
  respond(response, exitCodes[code] || 1);
}

function parseJsonStdin() {
  const input = readFileSync(0, "utf8");
  if (!input.trim()) {
    throw requestError("stdin must contain a KernelRequest JSON object");
  }
  try {
    const parsed = JSON.parse(input);
    if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") {
      throw new Error("not an object");
    }
    return parsed;
  } catch (error) {
    throw requestError(`invalid JSON request: ${error.message}`);
  }
}

function requireString(request, name) {
  if (typeof request[name] !== "string" || request[name].trim() === "") {
    throw requestError(`missing required string field: ${name}`);
  }
  return request[name];
}

function resolveSpecDir(specDir) {
  const resolved = path.resolve(specDir);
  if (!existsSync(resolved)) {
    throw artifactError(`specDir does not exist: ${specDir}`, { artifact: "specDir" });
  }
  return resolved;
}

function readBytes(filePath, artifact) {
  try {
    return readFileSync(filePath);
  } catch {
    throw artifactError(`missing artifact: ${artifact}`, { artifact });
  }
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function readArtifact(specDir, artifact) {
  const file = ARTIFACTS[artifact];
  if (!file) {
    throw requestError(`unsupported artifact: ${artifact}`);
  }
  const bytes = readBytes(path.join(specDir, file), artifact);
  return { text: bytes.toString("utf8"), hash: sha256(bytes) };
}

function parseFrontmatter(text) {
  if (!text.startsWith("---")) {
    return {};
  }
  const end = text.indexOf("\n---", 3);
  if (end === -1) {
    return {};
  }
  const body = text.slice(3, end).split(/\r?\n/);
  const result = {};
  for (const line of body) {
    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/);
    if (!match) continue;
    result[match[1]] = match[2].trim().replace(/^["']|["']$/g, "");
  }
  return result;
}

function assertArtifactUsable(name, frontmatter) {
  const status = String(frontmatter.status || "").toLowerCase();
  if (status === "blocked" || status === "incomplete") {
    throw artifactError(`${name} artifact is ${status}`, { artifact: name, condition: status });
  }
  for (const [key, value] of Object.entries(frontmatter)) {
    if (/gap/i.test(key) && value && !/^(none|no|false|\[\])$/i.test(value)) {
      throw artifactError(`${name} artifact has open required gaps`, { artifact: name, condition: key });
    }
  }
}

function statePath(specDir) {
  return path.join(specDir, STATE_FILE);
}

function lockPath(specDir) {
  return path.join(specDir, `${STATE_FILE}.lock`);
}

function withStateLock(specDir, fn) {
  const lock = lockPath(specDir);
  try {
    mkdirSync(lock, { mode: 0o700 });
  } catch (error) {
    if (error.code === "EEXIST") {
      throw requestError("kernel state is locked by another coordinator", { lock });
    }
    throw error;
  }
  try {
    return fn();
  } finally {
    rmSync(lock, { recursive: true, force: true });
  }
}

function repoPromotionLockPath(repoRoot) {
  return path.join(repoRoot, ".spec-drive", "kernel", "locks", "promotion.lock");
}

function withRepoPromotionLock(repoRoot, state, fn) {
  const lock = repoPromotionLockPath(repoRoot);
  mkdirSync(path.dirname(lock), { recursive: true });
  try {
    mkdirSync(lock, { mode: 0o700 });
  } catch (error) {
    if (error.code === "EEXIST") {
      throw externalChangeError("target repo cooperative promotion lock is held", { lock });
    }
    throw externalChangeError(`cannot establish target repo cooperative promotion lock: ${error.message}`, { lock });
  }
  try {
    return fn();
  } finally {
    rmSync(lock, { recursive: true, force: true });
  }
}

function leasePath(repoRoot, state, taskId) {
  return path.join(repoRoot, ".spec-drive", "kernel", "leases", state.runId, `${taskId}.json`);
}

function writeTaskLease(repoRoot, state, task, attempt) {
  const file = leasePath(repoRoot, state, task.taskId);
  mkdirSync(path.dirname(file), { recursive: true });
  if (existsSync(file)) {
    const existing = JSON.parse(readFileSync(file, "utf8"));
    if (existing.attemptId !== attempt.attemptId || existing.taskId !== task.taskId || existing.runId !== state.runId) {
      const previous = state.attempts?.[existing.attemptId];
      const ledgerAllowsReplacement = state.activeAttemptId !== existing.attemptId && state.currentStage === "ready";
      if (!previous || (!["abandoned", "reported_blocked"].includes(previous.state) && !ledgerAllowsReplacement)) {
        throw externalChangeError("task already has a cooperative execution lease", { lease: file });
      }
      rmSync(file, { force: true });
    } else {
      return;
    }
  }
  writeFileSync(file, `${JSON.stringify({
    runId: state.runId,
    taskId: task.taskId,
    attemptId: attempt.attemptId,
    targetHeadAtCreate: attempt.worktree.targetHeadAtCreate,
    createdAt: new Date().toISOString(),
  }, null, 2)}\n`);
}

function requireTaskLease(repoRoot, state, task, attempt) {
  const file = leasePath(repoRoot, state, task.taskId);
  if (!existsSync(file)) {
    throw externalChangeError("missing cooperative execution lease", { lease: file });
  }
  const lease = JSON.parse(readFileSync(file, "utf8"));
  if (lease.runId !== state.runId || lease.taskId !== task.taskId || lease.attemptId !== attempt.attemptId) {
    throw externalChangeError("cooperative execution lease does not match attempt", { lease: file });
  }
}

function readState(specDir) {
  const file = statePath(specDir);
  if (!existsSync(file)) {
    return { schemaVersion: 1, approvals: {}, __fresh: true };
  }
  try {
    const state = JSON.parse(readFileSync(file, "utf8"));
    if (!state || typeof state !== "object" || Array.isArray(state)) {
      throw new Error("state is not an object");
    }
    state.approvals ||= {};
    return state;
  } catch (error) {
    throw artifactError(`invalid kernel state: ${error.message}`, { artifact: STATE_FILE });
  }
}

function stateOwnKeys(state) {
  return Object.keys(state).filter((key) => key !== "__fresh");
}

function hasCompleteStateMetadata(state) {
  return STATE_METADATA_FIELDS.every((field) => typeof state[field] === "string" && state[field].trim() !== "");
}

function assertStateMetadata(state, specDir) {
  if (!hasCompleteStateMetadata(state)) {
    throw artifactError("kernel state is missing required metadata; legacy migration is not supported yet", {
      artifact: STATE_FILE,
      required: STATE_METADATA_FIELDS,
    });
  }
  if (state.basePath !== path.resolve(specDir)) {
    throw artifactError("kernel state basePath does not match specDir", { artifact: STATE_FILE });
  }
  if (!STATE_PHASES.has(state.phase)) {
    throw artifactError(`kernel state has unsupported phase: ${state.phase}`, { artifact: STATE_FILE });
  }
}

function defaultStateName(specDir, artifactText = "") {
  const specName = parseFrontmatter(artifactText).spec;
  return typeof specName === "string" && specName.trim() !== "" ? specName.trim() : path.basename(specDir);
}

function initializeFreshStateMetadata(state, specDir, phase, artifactText = "") {
  if (hasCompleteStateMetadata(state)) {
    assertStateMetadata(state, specDir);
    return;
  }
  const keys = stateOwnKeys(state);
  const freshApprovalOnlyState = state.__fresh
    || keys.every((key) => key === "schemaVersion" || key === "approvals");
  if (!freshApprovalOnlyState) {
    assertStateMetadata(state, specDir);
  }
  state.name = defaultStateName(specDir, artifactText);
  state.basePath = path.resolve(specDir);
  state.phase = phase;
}

function requireSafeInteger(value, name, { positive = false } = {}) {
  if (!Number.isSafeInteger(value) || (positive ? value <= 0 : value < 0)) {
    throw artifactError(`${name} must be a ${positive ? "positive" : "nonnegative"} safe integer`, {
      artifact: STATE_FILE,
      field: name,
    });
  }
}

function validateBudgetLedger(state) {
  state.budgets ||= {};
  for (const [key, value] of Object.entries(DEFAULT_BUDGETS)) {
    if (state.budgets[key] === undefined) {
      state.budgets[key] = value;
    } else {
      requireSafeInteger(state.budgets[key], `budgets.${key}`, { positive: true });
    }
  }
  if (state.budgets.globalBudgetUsed === undefined) {
    state.budgets.globalBudgetUsed = 0;
  } else {
    requireSafeInteger(state.budgets.globalBudgetUsed, "budgets.globalBudgetUsed");
  }
  for (const [taskId, taskState] of Object.entries(state.taskStates || {})) {
    requireSafeInteger(taskState.dispatchFailures ?? 0, `taskStates.${taskId}.dispatchFailures`);
    requireSafeInteger(taskState.executionAttempts ?? 0, `taskStates.${taskId}.executionAttempts`);
  }
}

function writeState(specDir, state) {
  const file = statePath(specDir);
  const dir = path.dirname(file);
  const tmp = path.join(dir, `.${path.basename(file)}.${process.pid}.${Date.now()}.tmp`);
  const fd = openSync(tmp, "w", 0o600);
  try {
    writeFileSync(fd, `${JSON.stringify(state, null, 2)}\n`);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  renameSync(tmp, file);
  try {
    const dirFd = openSync(dir, "r");
    try {
      fsyncSync(dirFd);
    } finally {
      closeSync(dirFd);
    }
  } catch {
    // Directory fsync is not supported on every filesystem used by test runners.
  }
}

function parseTraceDefinitions(requirementsText) {
  return new Set(requirementsText.match(TRACE_RE) || []);
}

function parseDesignCoverage(designText) {
  const coverage = new Set();
  const lines = designText.split(/\r?\n/);
  let inFence = false;
  for (const line of lines) {
    if (/^\s*```/.test(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence || /^\s*<!--/.test(line)) continue;
    for (const id of line.match(TRACE_RE) || []) {
      coverage.add(id);
    }
  }
  return coverage;
}

function normalizeFieldName(rawName) {
  const lower = rawName.trim().toLowerCase();
  if (lower === "done when") return "Done when";
  if (lower === "model") return "model";
  if (lower === "model_used") return "model_used";
  return rawName.trim().replace(/\b\w/g, (char) => char.toUpperCase());
}

function appendField(task, field, value) {
  task.fields[field] = task.fields[field] ? `${task.fields[field]}\n${value}` : value;
}

function parseTasks(tasksText) {
  const tasks = [];
  const seen = new Map();
  const lines = tasksText.split(/\r?\n/);
  let inFence = false;
  let inComment = false;
  let current = null;
  let currentField = null;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const lineNumber = index + 1;
    if (/^\s*```/.test(line)) {
      inFence = !inFence;
      if (current && currentField) appendField(current, currentField, line);
      continue;
    }
    if (!inFence && line.includes("<!--")) inComment = true;
    if (!inFence && inComment) {
      if (line.includes("-->")) inComment = false;
      continue;
    }
    if (inFence) {
      if (current && currentField) appendField(current, currentField, line);
      continue;
    }

    const taskLine = line.match(/^\s*-\s*\[[ xX]\]\s+(\S+)(.*)$/);
    if (taskLine) {
      const taskId = taskLine[1];
      if (!ID_RE.test(taskId)) {
        throw artifactError(`invalid task id '${taskId}' at line ${lineNumber}`, { taskId, line: lineNumber });
      }
      if (seen.has(taskId)) {
        throw artifactError(`duplicate task id '${taskId}' at line ${lineNumber}`, { taskId, line: lineNumber });
      }
      const tail = taskLine[2] || "";
      current = {
        taskId,
        checked: /^\s*-\s*\[[xX]\]/.test(line),
        title: tail.trim(),
        line: lineNumber,
        taskType: tail.includes("[VERIFY]") || taskId.startsWith("V") ? "verify" : "regular",
        parallel: tail.includes("[P]"),
        fields: {},
      };
      seen.set(taskId, current);
      tasks.push(current);
      currentField = null;
      continue;
    }

    if (!current) continue;
    const fieldMatch = line.match(/^\s+-\s+(?:\*\*)?([A-Za-z][A-Za-z _]*?)(?:\*\*)?\s*:\s*(.*)$/);
    if (fieldMatch) {
      const field = normalizeFieldName(fieldMatch[1]);
      if (!ALLOWED_FIELDS.has(field)) {
        throw artifactError(`unknown field '${fieldMatch[1].trim()}' at line ${lineNumber}`, {
          taskId: current.taskId,
          line: lineNumber,
        });
      }
      if (Object.hasOwn(current.fields, field)) {
        throw artifactError(`duplicate field '${field}' at line ${lineNumber}`, {
          taskId: current.taskId,
          line: lineNumber,
        });
      }
      current.fields[field] = fieldMatch[2].trim();
      currentField = field;
      continue;
    }
    if (/^\s{4,}\S/.test(line) && currentField) {
      appendField(current, currentField, line.replace(/^\s{4}/, ""));
    }
  }

  if (tasks.length === 0) {
    throw artifactError("tasks.md contains no executable tasks", { artifact: "tasks" });
  }
  return tasks;
}

function taskSemanticRecord(task) {
  const fields = {};
  for (const [field, value] of Object.entries(task.fields)) {
    if (MUTABLE_TRACKING_FIELDS.has(field)) continue;
    fields[field] = value.trim();
  }
  return {
    taskId: task.taskId,
    taskType: task.taskType,
    parallel: task.parallel,
    fields,
  };
}

function taskSemanticDigest(task) {
  return sha256(Buffer.from(JSON.stringify(taskSemanticRecord(task))));
}

function buildTaskApprovalMetadata(tasks) {
  return {
    taskOrder: tasks.map((task) => task.taskId),
    taskChecks: Object.fromEntries(tasks.map((task) => [task.taskId, task.checked])),
    taskDigests: Object.fromEntries(
      [...tasks]
        .sort((a, b) => a.taskId.localeCompare(b.taskId))
        .map((task) => [task.taskId, taskSemanticDigest(task)]),
    ),
  };
}

function sameStringMap(left = {}, right = {}) {
  const leftKeys = Object.keys(left).sort();
  const rightKeys = Object.keys(right).sort();
  if (leftKeys.join("\0") !== rightKeys.join("\0")) return false;
  return leftKeys.every((key) => left[key] === right[key]);
}

function sameTaskOrder(left = [], right = []) {
  return left.length === right.length && left.every((taskId, index) => taskId === right[index]);
}

function sameTaskChecks(left = {}, right = {}) {
  return sameStringMap(
    Object.fromEntries(Object.entries(left).map(([key, value]) => [key, String(Boolean(value))])),
    Object.fromEntries(Object.entries(right).map(([key, value]) => [key, String(Boolean(value))])),
  );
}

function parseList(value) {
  return value
    .split(/[\n,]/)
    .map((item) => item.replace(/^\s*-\s*/, "").trim())
    .filter(Boolean);
}

function validateRelativePath(repoRoot, relPath, taskId, fieldName) {
  if (relPath === ".") return;
  if (path.isAbsolute(relPath) || relPath.includes("\0")) {
    throw artifactError(`${fieldName} path must be repo-relative: ${relPath}`, { taskId, path: relPath });
  }
  const resolved = path.resolve(repoRoot, relPath);
  const root = path.resolve(repoRoot);
  if (resolved !== root && !resolved.startsWith(`${root}${path.sep}`)) {
    throw artifactError(`${fieldName} path escapes repo: ${relPath}`, { taskId, path: relPath });
  }
}

function runGit(repoRoot, args, options = {}) {
  const result = spawnSync("git", ["-C", repoRoot, ...args], {
    encoding: options.encoding || "utf8",
    env: { ...process.env, ...(options.env || {}) },
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.error) {
    throw executionError(`git failed to start: ${result.error.message}`, { repoRoot, args });
  }
  if (result.status !== 0) {
    const detail = String(result.stderr || result.stdout || "").trim() || `git exited ${result.status}`;
    throw new KernelFailure(options.errorCode || "acceptance_error", detail, { repoRoot, args });
  }
  if (options.raw) return result.stdout || (options.encoding === "buffer" ? Buffer.alloc(0) : "");
  return String(result.stdout || "").replace(/\r?\n$/, "");
}

function gitOptional(repoRoot, args) {
  const result = spawnSync("git", ["-C", repoRoot, ...args], {
    encoding: "utf8",
    env: { ...process.env },
    maxBuffer: 10 * 1024 * 1024,
  });
  return {
    ok: result.status === 0,
    stdout: (result.stdout || "").replace(/\r?\n$/, ""),
    stderr: (result.stderr || "").trim(),
  };
}

function requireGitRepo(repoRoot) {
  const inside = gitOptional(repoRoot, ["rev-parse", "--is-inside-work-tree"]);
  if (!inside.ok || inside.stdout !== "true") {
    throw artifactError("repoRoot must be a Git worktree for execution", { artifact: "repoRoot", repoRoot });
  }
}

function parsePorcelainZ(output) {
  const entries = String(output || "").split("\0");
  const paths = [];
  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index];
    if (!entry) continue;
    const status = entry.slice(0, 2);
    const relPath = entry.slice(3);
    if (!relPath) continue;
    paths.push(relPath);
    if (status.includes("R") || status.includes("C")) {
      const source = entries[index + 1];
      if (source) paths.push(source);
      index += 1;
    }
  }
  return [...new Set(paths)];
}

function knownOwnedMetadataPaths(state = {}, taskId = null) {
  const paths = new Set([".spec-drive/kernel/locks/promotion.lock"]);
  if (!state.runId) return paths;
  const knownTaskIds = new Set();
  if (taskId) knownTaskIds.add(taskId);
  for (const knownTaskId of Object.keys(state.taskStates || {})) {
    const taskState = state.taskStates[knownTaskId];
    if (taskState?.latestAttemptId || taskState?.acceptance || (taskState?.attempts || []).length) {
      knownTaskIds.add(knownTaskId);
    }
  }
  for (const attempt of Object.values(state.attempts || {})) {
    if (attempt?.taskId) knownTaskIds.add(attempt.taskId);
  }
  for (const knownTaskId of knownTaskIds) {
    paths.add(`.spec-drive/worktrees/${state.runId}/${knownTaskId}`);
    paths.add(`.spec-drive/kernel/leases/${state.runId}/${knownTaskId}.json`);
  }
  return paths;
}

function isOwnedKernelMetadataPath(relPath, state = {}, taskId = null) {
  for (const owned of knownOwnedMetadataPaths(state, taskId)) {
    if (relPath === owned || (owned.includes("/worktrees/") && relPath.startsWith(`${owned}/`))) {
      return true;
    }
  }
  return false;
}

function assertFilesDoNotOverlapOwnedMetadata(task, state) {
  for (const file of task.files || []) {
    if (isOwnedKernelMetadataPath(file, state, task.taskId)) {
      throw artifactError("Files may not overlap kernel-owned metadata", { taskId: task.taskId, path: file });
    }
  }
}

function repoStatusPaths(repoRoot, { ignoreOwnedMetadata = false, state = {}, taskId = null } = {}) {
  const output = runGit(repoRoot, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], {
    errorCode: "external_change_error",
    raw: true,
  });
  return parsePorcelainZ(output).filter(
    (relPath) => !(ignoreOwnedMetadata && isOwnedKernelMetadataPath(relPath, state, taskId)),
  );
}

function requireTargetClean(repoRoot, state = {}, taskId = null) {
  const dirty = repoStatusPaths(repoRoot, { ignoreOwnedMetadata: true, state, taskId });
  if (dirty.length) {
    throw externalChangeError("target repo has external changes", { dirtyPaths: dirty });
  }
}

function assertCwdContained(root, cwd, label) {
  const resolvedRoot = realpathSync(root);
  const resolvedCwd = realpathSync(cwd);
  if (resolvedCwd !== resolvedRoot && !resolvedCwd.startsWith(`${resolvedRoot}${path.sep}`)) {
    throw acceptanceError(`${label} cwd escapes worktree`, { cwd: resolvedCwd, root: resolvedRoot });
  }
  if (!existsSync(resolvedCwd)) {
    throw acceptanceError(`${label} cwd does not exist`, { cwd: resolvedCwd });
  }
}

function ensureWorktree(repoRoot, state, task) {
  requireGitRepo(repoRoot);
  assertFilesDoNotOverlapOwnedMetadata(task, state);
  requireTargetClean(repoRoot, state, task.taskId);
  const worktreePath = path.join(repoRoot, ".spec-drive", "worktrees", state.runId, task.taskId);
  const branch = `spec-drive/${state.runId}/${task.taskId}`;
  const targetHead = runGit(repoRoot, ["rev-parse", "HEAD"], { errorCode: "external_change_error" });
  mkdirSync(path.dirname(worktreePath), { recursive: true });
  if (!existsSync(worktreePath)) {
    const branchExists = gitOptional(repoRoot, ["rev-parse", "--verify", "--quiet", branch]);
    const args = branchExists.ok
      ? ["worktree", "add", worktreePath, branch]
      : ["worktree", "add", "-b", branch, worktreePath, targetHead];
    runGit(repoRoot, args, { errorCode: "external_change_error" });
  }
  return { worktreePath, branch, targetHead };
}

function taskById(tasks, taskId) {
  return tasks.find((task) => task.taskId === taskId) || null;
}

function assertAttemptFilesOnly(worktreePath, task) {
  const allowed = new Set(task.taskType === "verify" ? [] : task.files);
  const changed = repoStatusPaths(worktreePath);
  const outside = changed.filter((relPath) => !allowed.has(relPath));
  if (outside.length) {
    throw acceptanceError("attempt changed files outside declared Files", {
      taskId: task.taskId,
      changedPaths: changed,
      outsidePaths: outside,
    });
  }
  if (task.taskType === "verify" && changed.length) {
    throw acceptanceError("checkpoint attempt must not change code", { taskId: task.taskId, changedPaths: changed });
  }
  return changed;
}

function contentManifest(root, files) {
  const manifest = {};
  for (const relPath of files) {
    const filePath = path.join(root, relPath);
    if (!existsSync(filePath)) {
      manifest[relPath] = null;
      continue;
    }
    const bytes = readFileSync(filePath);
    manifest[relPath] = { sha256: sha256(bytes), bytes: bytes.length };
  }
  return manifest;
}

function listTrackedFiles(root) {
  const output = runGit(root, ["ls-files", "-z"], { errorCode: "acceptance_error", raw: true });
  return String(output || "").split("\0").filter(Boolean);
}

function completeCandidateManifest(root, state = {}, taskId = null) {
  const tracked = new Set(listTrackedFiles(root));
  const stack = [root];
  while (stack.length) {
    const current = stack.pop();
    for (const name of readdirSync(current)) {
      if (current === root && name === ".git") continue;
      const abs = path.join(current, name);
      const rel = path.relative(root, abs).split(path.sep).join("/");
      if (isOwnedKernelMetadataPath(rel, state, taskId)) continue;
      const st = lstatSync(abs);
      if (st.isSymbolicLink()) {
        tracked.add(rel);
      } else if (st.isDirectory()) {
        stack.push(abs);
      } else if (st.isFile()) {
        tracked.add(rel);
      }
    }
  }
  const manifest = {};
  for (const relPath of [...tracked].sort()) {
    if (isOwnedKernelMetadataPath(relPath, state, taskId)) continue;
    const filePath = path.join(root, relPath);
    if (!existsSync(filePath)) {
      manifest[relPath] = null;
      continue;
    }
    const st = lstatSync(filePath);
    if (st.isSymbolicLink()) {
      manifest[relPath] = { mode: "symlink", target: readlinkSync(filePath) };
    } else if (st.isFile()) {
      const bytes = readFileSync(filePath);
      manifest[relPath] = { mode: (statSync(filePath).mode & 0o777).toString(8), sha256: sha256(bytes), bytes: bytes.length };
    }
  }
  return manifest;
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function runVerify(command, cwd, timeoutSec) {
  const result = spawnSync(command, {
    cwd,
    shell: true,
    encoding: "utf8",
    timeout: timeoutSec * 1000,
    killSignal: "SIGTERM",
    maxBuffer: 10 * 1024 * 1024,
  });
  return {
    command,
    cwd,
    timeoutSec,
    exitCode: result.status === null ? 124 : result.status,
    timedOut: result.error?.code === "ETIMEDOUT",
    stdout: (result.stdout || "").slice(-4000),
    stderr: (result.stderr || "").slice(-4000),
  };
}

function headAndIndexState(root) {
  return {
    head: runGit(root, ["rev-parse", "HEAD"], { errorCode: "acceptance_error" }),
    index: runGit(root, ["write-tree"], { errorCode: "acceptance_error" }),
  };
}

function runAuthoritativeVerify(root, task, cwdRel, label, state = {}) {
  const cwd = path.resolve(root, cwdRel);
  assertCwdContained(root, cwd, label);
  const before = completeCandidateManifest(root, state, task.taskId);
  const gitBefore = headAndIndexState(root);
  const record = runVerify(task.fields.Verify, cwd, task.timeoutSec);
  const after = completeCandidateManifest(root, state, task.taskId);
  const gitAfter = headAndIndexState(root);
  if (record.timedOut) {
    throw acceptanceError(`${label} Verify timed out`, { verify: record });
  }
  if (record.exitCode !== 0) {
    throw acceptanceError(`${label} Verify failed`, { verify: record });
  }
  if (!sameJson(before, after)) {
    throw acceptanceError(`${label} Verify mutated candidate tree`, { before, after, verify: record });
  }
  if (!sameJson(gitBefore, gitAfter)) {
    throw acceptanceError(`${label} Verify mutated HEAD or index`, { before: gitBefore, after: gitAfter, verify: record });
  }
  return record;
}

function treeFromDeclaredFiles(worktreePath, files) {
  mkdirSync(path.join(worktreePath, ".spec-drive", "kernel"), { recursive: true });
  const indexDir = mkdtempSync(path.join(worktreePath, ".spec-drive", "kernel", "tmp-index-"));
  const indexPath = path.join(indexDir, "index");
  const env = { GIT_INDEX_FILE: indexPath };
  runGit(worktreePath, ["read-tree", "HEAD"], { env });
  if (files.length) {
    runGit(worktreePath, ["add", "--", ...files], { env });
  }
  const tree = runGit(worktreePath, ["write-tree"], { env });
  rmSync(indexDir, { recursive: true, force: true });
  return tree;
}

function applyTreeDiff(targetRepoPath, baseCommit, tree) {
  const diff = spawnSync("git", ["-C", targetRepoPath, "diff", "--binary", baseCommit, tree], {
    encoding: "buffer",
    env: { ...process.env },
    maxBuffer: 20 * 1024 * 1024,
  });
  if (diff.error || diff.status !== 0) {
    throw acceptanceError("failed to compute promotion diff", {
      detail: diff.error?.message || diff.stderr?.toString("utf8") || "git diff failed",
    });
  }
  const apply = spawnSync("git", ["-C", targetRepoPath, "apply", "--binary", "--index"], {
    input: diff.stdout,
    encoding: "buffer",
    env: { ...process.env },
    maxBuffer: 20 * 1024 * 1024,
  });
  if (apply.error || apply.status !== 0) {
    throw acceptanceError("failed to apply promotion diff", {
      detail: apply.error?.message || apply.stderr?.toString("utf8") || "git apply failed",
    });
  }
}

function replaceTaskCheckbox(tasksText, taskId) {
  const escaped = taskId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`^(\\s*-\\s*\\[) \\](\\s+${escaped}\\b)`, "m");
  if (!re.test(tasksText)) {
    if (new RegExp(`^\\s*-\\s*\\[[xX]\\]\\s+${escaped}\\b`, "m").test(tasksText)) return tasksText;
    throw acceptanceError("could not project accepted task checkbox", { taskId });
  }
  return tasksText.replace(re, "$1x]$2");
}

function progressPath(specDir) {
  return path.join(specDir, ".progress.md");
}

function projectTracking(specDir, state, tasks, taskId, acceptance) {
  const tasksFile = path.join(specDir, ARTIFACTS.tasks);
  const updatedTasks = replaceTaskCheckbox(readFileSync(tasksFile, "utf8"), taskId);
  writeFileSync(tasksFile, updatedTasks);
  const progressFile = progressPath(specDir);
  const acceptedCount = tasks.filter((task) => task.taskId === taskId || getTaskState(state, task.taskId)?.status === "accepted").length;
  const line = `- ${taskId}: accepted ${acceptance.acceptedAt}${acceptance.commitOid ? ` ${acceptance.commitOid}` : " checkpoint"}\n`;
  const previous = existsSync(progressFile) ? readFileSync(progressFile, "utf8") : "# Progress\n\n";
  const header = previous.includes("Accepted tasks:") ? previous : `${previous.replace(/\s*$/, "\n\n")}Accepted tasks:\n`;
  writeFileSync(progressFile, `${header.replace(new RegExp(`^- ${taskId}:.*\\n`, "m"), "")}${line}`);
  state.trackingProjection = {
    tasksFile,
    progressFile,
    acceptedCount,
    totalTasks: tasks.length,
    updatedAt: new Date().toISOString(),
  };
}

function validateTask(task, repoRoot, knownTraces) {
  for (const field of REQUIRED_FIELDS) {
    if (!Object.hasOwn(task.fields, field) || task.fields[field].trim() === "") {
      throw artifactError(`missing required field '${field}'`, { taskId: task.taskId, line: task.line });
    }
  }
  if (task.fields.model && !MODEL_TIERS.has(task.fields.model.trim())) {
    throw artifactError(`invalid model tier '${task.fields.model.trim()}'`, { taskId: task.taskId });
  }
  const timeout = Number(task.fields.Timeout.trim());
  if (!Number.isInteger(timeout) || timeout <= 0) {
    throw artifactError("Timeout must be a positive integer", { taskId: task.taskId });
  }
  if (task.fields.Verify.includes(";")) {
    throw artifactError("Verify must be a single command without semicolon separators", { taskId: task.taskId });
  }
  validateRelativePath(repoRoot, task.fields.Cwd.trim(), task.taskId, "Cwd");
  const cwd = path.resolve(repoRoot, task.fields.Cwd.trim());
  if (!existsSync(cwd)) {
    throw artifactError(`Cwd does not exist: ${task.fields.Cwd.trim()}`, { taskId: task.taskId });
  }
  let files = parseList(task.fields.Files);
  if (task.taskType === "verify") {
    if (task.fields.Files.trim() !== "none" || task.fields.Commit.trim() !== "none") {
      throw artifactError("checkpoint tasks must declare Files=none and Commit=none", { taskId: task.taskId });
    }
    files = [];
  } else if (task.fields.Files.trim() === "none") {
    throw artifactError("Files=none is only valid for checkpoints", { taskId: task.taskId });
  } else {
    for (const file of files) validateRelativePath(repoRoot, file, task.taskId, "Files");
  }
  const traces = parseList(task.fields.Traces);
  if (traces.length === 0) {
    throw artifactError("Traces must include at least one reference", { taskId: task.taskId });
  }
  for (const trace of traces) {
    if (!knownTraces.has(trace)) {
      throw artifactError(`unknown trace reference '${trace}'`, { taskId: task.taskId, trace });
    }
  }
  return { ...task, timeoutSec: timeout, traces, files };
}

function requireApproval(state, artifact, actualHash) {
  const approval = state.approvals?.[artifact];
  if (!approval || typeof approval.approvalEvidence !== "string" || approval.approvalEvidence.trim() === "") {
    throw artifactError(`missing explicit approval evidence for ${artifact}`, { artifact });
  }
  if (approval.sha256 !== actualHash) {
    throw artifactError(`${artifact} hash is stale`, { artifact, expected: approval.sha256, actual: actualHash });
  }
  return approval;
}

function requireTasksApproval(state, actualHash, tasks) {
  const approval = state.approvals?.tasks;
  if (!approval || typeof approval.approvalEvidence !== "string" || approval.approvalEvidence.trim() === "") {
    throw artifactError("missing explicit approval evidence for tasks", { artifact: "tasks" });
  }
  if (approval.sha256 === actualHash) return approval;
  const currentMetadata = buildTaskApprovalMetadata(tasks);
  const semanticMatch = approval.taskDigests && sameStringMap(approval.taskDigests, currentMetadata.taskDigests);
  const orderChanged = approval.taskOrder && !sameTaskOrder(approval.taskOrder, currentMetadata.taskOrder);
  const checksChanged = approval.taskChecks && !sameTaskChecks(approval.taskChecks, currentMetadata.taskChecks);
  if (semanticMatch && (orderChanged || checksChanged)) {
    return approval;
  }
  throw artifactError("tasks hash is stale", { artifact: "tasks", expected: approval.sha256, actual: actualHash });
}

function getTaskState(state, taskId) {
  return state.taskStates?.[taskId] || null;
}

function buildPlanSummary(tasks, requiredTraceIds, state = {}) {
  const accepted = tasks.filter((task) => getTaskState(state, task.taskId)?.status === "accepted").length;
  return {
    totalTasks: tasks.length,
    requiredTasks: tasks.length,
    acceptedTasks: accepted,
    pendingTasks: tasks.length - accepted,
    taskOrder: tasks.map((task) => task.taskId),
    requiredTraceIds: [...requiredTraceIds].sort(),
  };
}

function ensureLedger(state, tasks, tasksHash) {
  assertStateMetadata(state, state.basePath);
  validateBudgetLedger(state);
  state.schemaVersion = Math.max(Number(state.schemaVersion || 1), 2);
  state.runId ||= `run-${createHash("sha256").update(`${tasksHash}:${state.basePath || ""}`).digest("hex").slice(0, 12)}`;
  state.planRevision ||= tasksHash;
  state.taskOrder ||= state.approvals?.tasks?.taskOrder || tasks.map((task) => task.taskId);
  state.currentTaskId ||= state.taskOrder.find((taskId) => getTaskState(state, taskId)?.status !== "accepted")
    || state.taskOrder[0]
    || tasks[0]?.taskId
    || null;
  state.currentStage ||= "ready";
  state.taskStates ||= {};
  state.attempts ||= {};
  for (const task of tasks) {
    state.taskStates[task.taskId] ||= {
      taskId: task.taskId,
      status: "pending",
      required: true,
      attempts: [],
      dispatchFailures: 0,
      executionAttempts: 0,
    };
    state.taskStates[task.taskId].required = true;
    state.taskStates[task.taskId].attempts ||= [];
    state.taskStates[task.taskId].dispatchFailures ??= 0;
    state.taskStates[task.taskId].executionAttempts ??= 0;
  }
  if (state.taskIndex !== undefined && !state.legacyMigratedAt) {
    throw artifactError("legacy taskIndex state migration is not supported yet", { artifact: STATE_FILE });
  }
  validateBudgetLedger(state);
  return state;
}

function loadValidatedPlan(specDir, repoRoot) {
  const requirements = readArtifact(specDir, "requirements");
  const design = readArtifact(specDir, "design");
  const tasksArtifact = readArtifact(specDir, "tasks");
  const requirementsFm = parseFrontmatter(requirements.text);
  const designFm = parseFrontmatter(design.text);
  const tasksFm = parseFrontmatter(tasksArtifact.text);
  assertArtifactUsable("requirements", requirementsFm);
  assertArtifactUsable("design", designFm);
  assertArtifactUsable("tasks", tasksFm);

  const state = readState(specDir);
  requireApproval(state, "requirements", requirements.hash);
  requireApproval(state, "design", design.hash);
  if (tasksFm.requirements_sha !== requirements.hash || tasksFm.requirements_sha !== state.approvals.requirements.sha256) {
    throw artifactError("tasks.md requirements_sha is stale", { artifact: "tasks", field: "requirements_sha" });
  }
  if (tasksFm.design_sha !== design.hash || tasksFm.design_sha !== state.approvals.design.sha256) {
    throw artifactError("tasks.md design_sha is stale", { artifact: "tasks", field: "design_sha" });
  }
  if (designFm.requirements_sha && designFm.requirements_sha !== requirements.hash) {
    throw artifactError("design.md requirements_sha is stale", { artifact: "design", field: "requirements_sha" });
  }

  const knownTraces = parseTraceDefinitions(requirements.text);
  const designCoverage = parseDesignCoverage(design.text);
  const tasks = parseTasks(tasksArtifact.text).map((task) => validateTask(task, repoRoot, knownTraces));
  requireTasksApproval(state, tasksArtifact.hash, tasks);
  const requiredCoverage = new Set([...knownTraces].filter((id) => /^AC-|^NFR-/.test(id)));
  const taskCoverage = new Set(tasks.flatMap((task) => task.traces));
  const missingInDesign = [...requiredCoverage].filter((id) => !designCoverage.has(id));
  const missingInTasks = [...requiredCoverage].filter((id) => !taskCoverage.has(id));
  if (missingInDesign.length || missingInTasks.length) {
    throw artifactError("coverage incomplete", {
      missingInDesign,
      missingInTasks,
    });
  }
  return { requirements, design, tasksArtifact, tasks, requiredCoverage, state };
}

function preflight(request) {
  const specDir = resolveSpecDir(requireString(request, "specDir"));
  const repoRoot = path.resolve(requireString(request, "repoRoot"));
  if (!existsSync(repoRoot)) {
    throw artifactError(`repoRoot does not exist: ${request.repoRoot}`, { artifact: "repoRoot" });
  }
  const { requirements, design, tasksArtifact, tasks, requiredCoverage, state } = loadValidatedPlan(specDir, repoRoot);

  const warnings = tasks.filter((task) => task.parallel).map((task) => `[P] task ${task.taskId} will run serially`);
  for (const warning of warnings) diagnostic(warning);
  return {
    ok: true,
    phase: "tasks",
    hashes: {
      requirements: requirements.hash,
      design: design.hash,
      tasks: tasksArtifact.hash,
    },
    plan: buildPlanSummary(tasks, requiredCoverage, state),
    warnings,
  };
}

function approve(request) {
  const specDir = resolveSpecDir(requireString(request, "specDir"));
  const artifact = requireString(request, "artifact");
  if (!Object.hasOwn(ARTIFACTS, artifact)) {
    throw requestError(`unsupported artifact for approval: ${artifact}`);
  }
  const expectedSha256 = requireString(request, "expectedSha256");
  if (!/^[a-f0-9]{64}$/i.test(expectedSha256)) {
    throw requestError("expectedSha256 must be a 64-character hex SHA-256 digest");
  }
  const approvalEvidence = requireString(request, "approvalEvidence");
  const current = readArtifact(specDir, artifact);
  if (current.hash !== expectedSha256.toLowerCase()) {
    throw artifactError(`${artifact} approval hash does not match current bytes`, {
      artifact,
      expected: expectedSha256.toLowerCase(),
      actual: current.hash,
    });
  }
  withStateLock(specDir, () => {
    const state = readState(specDir);
    initializeFreshStateMetadata(state, specDir, artifact === "tasks" ? "tasks" : artifact, current.text);
    state.schemaVersion = Math.max(Number(state.schemaVersion || 1), 2);
    state.approvals ||= {};
    let taskMetadata = {};
    if (artifact === "tasks") {
      try {
        taskMetadata = buildTaskApprovalMetadata(parseTasks(current.text));
      } catch {
        taskMetadata = {};
      }
    }
    state.approvals[artifact] = {
      sha256: current.hash,
      approvalEvidence,
      approvedAt: new Date().toISOString(),
      ...taskMetadata,
    };
    delete state.__fresh;
    writeState(specDir, state);
  });
  return { ok: true, approved: artifact, sha256: current.hash };
}

function nextTask(tasks, state) {
  const byId = new Map(tasks.map((task) => [task.taskId, task]));
  if (state.currentTaskId) {
    const current = byId.get(state.currentTaskId);
    if (current && getTaskState(state, current.taskId)?.status !== "accepted") return current;
  }
  for (const taskId of state.taskOrder || []) {
    const task = byId.get(taskId);
    if (task && getTaskState(state, task.taskId)?.status !== "accepted") return task;
  }
  return tasks.find((task) => getTaskState(state, task.taskId)?.status !== "accepted") || null;
}

function interruptedPromotionAttempt(state) {
  return Object.values(state.attempts || {}).find((attempt) => {
    const stage = attempt?.promotion?.stage;
    return stage && stage !== "tracking_updated";
  }) || null;
}

function next(request) {
  const specDir = resolveSpecDir(requireString(request, "specDir"));
  const repoRoot = path.resolve(requireString(request, "repoRoot"));
  const actor = requireString(request, "actor");
  if (!new Set(["implement", "stop-watcher"]).has(actor)) {
    throw requestError(`unsupported next actor: ${actor}`);
  }
  return withStateLock(specDir, () => {
    const { tasksArtifact, tasks, state } = loadValidatedPlan(specDir, repoRoot);
    initializeFreshStateMetadata(state, specDir, "execution");
    ensureLedger(state, tasks, tasksArtifact.hash);
    const interrupted = interruptedPromotionAttempt(state);
    if (interrupted) {
      throw requestError("unsupported in-progress promotion state requires recovery", {
        taskId: interrupted.taskId,
        attemptId: interrupted.attemptId,
        stage: interrupted.promotion.stage,
      });
    }
    if (state.currentStage === "reported_complete") {
      throw requestError("task is awaiting authoritative acceptance", {
        taskId: state.currentTaskId,
        attemptId: state.activeAttemptId || state.taskStates?.[state.currentTaskId]?.latestAttemptId || null,
        nextAction: "run accept",
      });
    }
    if (state.activeAttemptId) {
      const active = state.attempts[state.activeAttemptId];
      if (active && !["reported_complete", "reported_blocked", "accepted", "abandoned"].includes(active.state)) {
        throw requestError("active attempt prevents new dispatch", {
          taskId: active.taskId,
          attemptId: active.attemptId,
          state: active.state,
        });
      }
    }
    const task = nextTask(tasks, state);
    if (!task) {
      state.currentStage = "completed";
      state.currentTaskId = null;
      writeState(specDir, state);
      return { ok: true, phase: "execution", plan: buildPlanSummary(tasks, new Set(), state) };
    }
    const taskState = state.taskStates[task.taskId];
    if (state.budgets.globalBudgetUsed >= state.budgets.maxGlobalOperations) {
      throw new KernelFailure("execution_error", "global operation budget exhausted", { taskId: task.taskId });
    }
    if (taskState.dispatchFailures >= state.budgets.maxDispatchFailures) {
      throw new KernelFailure("dispatch_error", "dispatch failure budget exhausted", { taskId: task.taskId });
    }
    if (taskState.executionAttempts >= state.budgets.maxExecutionAttempts) {
      throw new KernelFailure("execution_error", "execution attempt budget exhausted", { taskId: task.taskId });
    }
    const lease = ensureWorktree(repoRoot, state, task);
    const sequence = taskState.attempts.length + 1;
    const attemptId = `${task.taskId.replace(/\W+/g, "-")}-a${sequence}-${Date.now().toString(36)}`;
    const worktreePath = lease.worktreePath;
    const attempt = {
      attemptId,
      taskId: task.taskId,
      sequence,
      dispatchBudgetUsed: taskState.dispatchFailures,
      executionBudgetUsed: taskState.executionAttempts + 1,
      globalBudgetUsed: state.budgets.globalBudgetUsed + 1,
      state: "dispatching",
      actor,
      adapterStart: "unknown",
      worktree: {
        path: worktreePath,
        branch: lease.branch,
        targetHeadAtCreate: lease.targetHead,
        files: task.files,
      },
    };
    writeTaskLease(repoRoot, state, task, attempt);
    state.attempts[attemptId] = attempt;
    taskState.status = "in_progress";
    taskState.latestAttemptId = attemptId;
    taskState.attempts.push(attemptId);
    taskState.executionAttempts += 1;
    state.budgets.globalBudgetUsed += 1;
    state.currentTaskId = task.taskId;
    state.currentStage = "dispatching";
    state.activeAttemptId = attemptId;
    state.lastFailureClass = null;
    writeState(specDir, state);
    return {
      ok: true,
      dispatch: {
        taskId: task.taskId,
        attemptId,
        taskType: task.taskType,
        mechanism: task.fields.model ? "subprocess" : "inherit",
        worktreePath,
        targetRepoPath: repoRoot,
        promptContractPath: path.join(specDir, "tasks.md"),
        verify: {
          command: task.fields.Verify,
          cwd: path.resolve(worktreePath, task.fields.Cwd.trim()),
          timeoutSec: task.timeoutSec,
        },
        commitMessage: task.fields.Commit.trim(),
        traces: task.traces,
      },
    };
  });
}

function sameReport(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function report(request) {
  const specDir = resolveSpecDir(requireString(request, "specDir"));
  const attemptId = requireString(request, "attemptId");
  const incoming = request.report;
  if (!incoming || typeof incoming !== "object" || Array.isArray(incoming)) {
    throw requestError("missing report object");
  }
  return withStateLock(specDir, () => {
    const state = readState(specDir);
    const attempt = state.attempts?.[attemptId];
    if (!attempt) {
      throw requestError("unknown attemptId", { attemptId });
    }
    if (attempt.report) {
      if (sameReport(attempt.report, incoming)) {
        return { ok: true, report: "duplicate_ignored", attemptId };
      }
      throw requestError("conflicting duplicate report", { attemptId });
    }
    if (incoming.attemptId !== attemptId || incoming.taskId !== attempt.taskId) {
      throw requestError("report identity does not match attempt", { attemptId, taskId: attempt.taskId });
    }
    const taskState = state.taskStates?.[attempt.taskId];
    if (!taskState) {
      throw requestError("attempt task is missing from ledger", { attemptId, taskId: attempt.taskId });
    }
    const adapterEvidence = request.adapterEvidence || "unknown";
    const noStartDemonstrated = adapterEvidence === "not_started";
    attempt.report = incoming;
    attempt.adapterStart = adapterEvidence;
    if (incoming.outcome === "task_complete") {
      if (adapterEvidence !== "started" || incoming.startedWork !== true) {
        attempt.state = "indeterminate";
        taskState.status = "blocked";
        state.currentStage = "indeterminate";
        state.activeAttemptId = attemptId;
        state.lastFailureClass = "conflicting_success_start_evidence";
        writeState(specDir, state);
        return {
          ok: true,
          attemptId,
          taskId: attempt.taskId,
          state: attempt.state,
          awaitingRecovery: true,
        };
      }
      attempt.state = "reported_complete";
      taskState.status = "promotion_pending";
      state.currentStage = "reported_complete";
      state.activeAttemptId = null;
    } else if (incoming.failureClass === "dispatch_error" && noStartDemonstrated) {
      attempt.state = "abandoned";
      attempt.executionBudgetUsed = Math.max(0, attempt.executionBudgetUsed - 1);
      taskState.executionAttempts = Math.max(0, taskState.executionAttempts - 1);
      taskState.dispatchFailures += 1;
      taskState.status = "pending";
      state.currentStage = "ready";
      state.activeAttemptId = null;
      state.lastFailureClass = "dispatch_error";
    } else if (incoming.outcome === "task_indeterminate" || adapterEvidence === "unknown") {
      attempt.state = "indeterminate";
      taskState.status = "blocked";
      state.currentStage = "indeterminate";
      state.activeAttemptId = attemptId;
      state.lastFailureClass = incoming.failureClass || "unknown_start";
    } else {
      attempt.state = "reported_blocked";
      taskState.status = "pending";
      state.currentStage = "ready";
      state.activeAttemptId = null;
      state.lastFailureClass = incoming.failureClass || "logic_error";
    }
    writeState(specDir, state);
    return {
      ok: true,
      attemptId,
      taskId: attempt.taskId,
      state: attempt.state,
      budgets: {
        dispatchFailures: taskState.dispatchFailures,
        executionAttempts: taskState.executionAttempts,
        globalBudgetUsed: state.budgets.globalBudgetUsed,
      },
    };
  });
}

function advanceAfterAccepted(state, tasks, taskId) {
  const currentIndex = (state.taskOrder || []).indexOf(taskId);
  const nextId = (state.taskOrder || [])
    .slice(Math.max(0, currentIndex + 1))
    .find((candidate) => getTaskState(state, candidate)?.status !== "accepted");
  const fallback = tasks.find((task) => getTaskState(state, task.taskId)?.status !== "accepted")?.taskId || null;
  state.currentTaskId = nextId || fallback;
  state.currentStage = state.currentTaskId ? "ready" : "completed";
  state.activeAttemptId = null;
}

function commitAcceptedTarget(repoRoot, attempt, task, targetTree, verifyRecord) {
  const message = task.fields.Commit.trim();
  const trailer = `Spec-Drive-Attempt: ${attempt.attemptId}`;
  runGit(repoRoot, ["commit", "-m", message, "-m", trailer], { errorCode: "acceptance_error" });
  const commitOid = runGit(repoRoot, ["rev-parse", "HEAD"], { errorCode: "acceptance_error" });
  const parent = runGit(repoRoot, ["rev-parse", `${commitOid}^`], { errorCode: "acceptance_error" });
  const actualTree = runGit(repoRoot, ["rev-parse", `${commitOid}^{tree}`], { errorCode: "acceptance_error" });
  const body = runGit(repoRoot, ["log", "-1", "--format=%B", commitOid], { errorCode: "acceptance_error" });
  if (parent !== attempt.worktree.targetHeadAtCreate) {
    throw acceptanceError("accepted commit parent does not match promotion intent", { commitOid, parent });
  }
  if (actualTree !== targetTree) {
    throw acceptanceError("accepted commit tree does not match verified target tree", { commitOid, actualTree, targetTree });
  }
  if (!body.includes(trailer)) {
    throw acceptanceError("accepted commit is missing attempt trailer", { commitOid, trailer });
  }
  return {
    taskId: task.taskId,
    attemptId: attempt.attemptId,
    command: verifyRecord.command,
    cwd: verifyRecord.cwd,
    timeoutSec: verifyRecord.timeoutSec,
    exitCode: verifyRecord.exitCode,
    verifiedTree: targetTree,
    commitOid,
    parent,
    tree: actualTree,
    trailer,
    acceptedAt: new Date().toISOString(),
  };
}

function accept(request) {
  const specDir = resolveSpecDir(requireString(request, "specDir"));
  const repoRoot = path.resolve(requireString(request, "repoRoot"));
  const attemptId = requireString(request, "attemptId");
  return withStateLock(specDir, () => {
    const { tasksArtifact, tasks, state } = loadValidatedPlan(specDir, repoRoot);
    ensureLedger(state, tasks, tasksArtifact.hash);
    const attempt = state.attempts?.[attemptId];
    if (!attempt) {
      throw requestError("unknown attemptId", { attemptId });
    }
    const task = taskById(tasks, attempt.taskId);
    if (!task) {
      throw requestError("attempt task is missing from current plan", { attemptId, taskId: attempt.taskId });
    }
    const taskState = state.taskStates?.[task.taskId];
    if (!taskState) {
      throw requestError("attempt task is missing from ledger", { attemptId, taskId: task.taskId });
    }
    if (attempt.state === "accepted" && taskState.acceptance && attempt.promotion?.stage === "tracking_updated") {
      return { ok: true, accepted: taskState.acceptance };
    }
    if (attempt.state !== "reported_complete") {
      throw acceptanceError("attempt is not ready for acceptance", { attemptId, state: attempt.state });
    }
    if (!attempt.report || attempt.report.outcome !== "task_complete") {
      throw acceptanceError("attempt report is not complete", { attemptId });
    }

    return withRepoPromotionLock(repoRoot, state, () => {
      requireTaskLease(repoRoot, state, task, attempt);
      if (attempt.promotion && attempt.promotion.stage && attempt.promotion.stage !== "tracking_updated") {
        throw acceptanceError("unsupported in-progress promotion state requires recovery", {
          attemptId,
          stage: attempt.promotion.stage,
        });
      }

      const worktreePath = attempt.worktree?.path;
      if (!worktreePath || !existsSync(worktreePath)) {
        throw acceptanceError("attempt worktree is missing", { attemptId, worktreePath });
      }
      assertAttemptFilesOnly(worktreePath, task);
      let worktreeVerify = null;
      let verifiedWorktreeTree = null;
      if (task.taskType !== "verify") {
        worktreeVerify = runAuthoritativeVerify(worktreePath, task, task.fields.Cwd.trim(), "worktree", state);
        assertAttemptFilesOnly(worktreePath, task);
        verifiedWorktreeTree = treeFromDeclaredFiles(worktreePath, task.files);
      }
      const targetHead = runGit(repoRoot, ["rev-parse", "HEAD"], { errorCode: "external_change_error" });
      const intent = {
        attemptId,
        taskId: task.taskId,
        verifyCommand: task.fields.Verify,
        verifyCwd: task.fields.Cwd.trim(),
        verifyTimeoutSec: task.timeoutSec,
        verifiedWorktreeTree,
        targetHeadExpected: attempt.worktree.targetHeadAtCreate,
        targetFilesExpectedClean: task.files,
        commitTrailer: `Spec-Drive-Attempt: ${attemptId}`,
        targetCommitMessage: task.fields.Commit.trim(),
        stage: "intent_recorded",
        worktreeVerify,
      };
      attempt.promotion = intent;
      state.currentStage = "intent_recorded";
      writeState(specDir, state);

      if (task.taskType === "verify") {
        requireTargetClean(repoRoot, state, task.taskId);
        if (targetHead !== attempt.worktree.targetHeadAtCreate) {
          throw externalChangeError("target HEAD changed before checkpoint acceptance", {
            expected: attempt.worktree.targetHeadAtCreate,
            actual: targetHead,
          });
        }
        const targetVerify = runAuthoritativeVerify(repoRoot, task, task.fields.Cwd.trim(), "target", state);
        const targetTree = runGit(repoRoot, ["rev-parse", "HEAD^{tree}"], { errorCode: "acceptance_error" });
        const acceptance = {
          taskId: task.taskId,
          attemptId,
          command: targetVerify.command,
          cwd: targetVerify.cwd,
          timeoutSec: targetVerify.timeoutSec,
          exitCode: targetVerify.exitCode,
          verifiedTree: targetTree,
          commitOid: null,
          parent: targetHead,
          tree: targetTree,
          trailer: null,
          acceptedAt: new Date().toISOString(),
        };
        attempt.state = "accepted";
        attempt.promotion.stage = "accepted_recorded";
        taskState.status = "accepted";
        taskState.acceptance = acceptance;
        writeState(specDir, state);
        projectTracking(specDir, state, tasks, task.taskId, acceptance);
        attempt.promotion.stage = "tracking_updated";
        advanceAfterAccepted(state, tasks, task.taskId);
        writeState(specDir, state);
        return { ok: true, accepted: acceptance };
      }

      requireTargetClean(repoRoot, state, task.taskId);
      if (targetHead !== attempt.worktree.targetHeadAtCreate) {
        throw externalChangeError("target HEAD changed before acceptance", {
          expected: attempt.worktree.targetHeadAtCreate,
          actual: targetHead,
        });
      }
      attempt.promotion.stage = "target_verified_clean";
      writeState(specDir, state);

      applyTreeDiff(repoRoot, attempt.worktree.targetHeadAtCreate, verifiedWorktreeTree);
      attempt.promotion.stage = "patch_applied";
      writeState(specDir, state);

      const changed = repoStatusPaths(repoRoot, { ignoreOwnedMetadata: true, state, taskId: task.taskId });
      const outside = changed.filter((relPath) => !task.files.includes(relPath));
      if (outside.length) {
        throw acceptanceError("promotion changed files outside declared Files", { changedPaths: changed, outsidePaths: outside });
      }
      const targetVerify = runAuthoritativeVerify(repoRoot, task, task.fields.Cwd.trim(), "target", state);
      const targetTree = treeFromDeclaredFiles(repoRoot, task.files);
      attempt.promotion.stage = "target_verified";
      attempt.promotion.targetVerify = targetVerify;
      attempt.promotion.targetTree = targetTree;
      writeState(specDir, state);

      const acceptance = commitAcceptedTarget(repoRoot, attempt, task, targetTree, targetVerify);
      attempt.state = "accepted";
      attempt.promotion.stage = "accepted_recorded";
      taskState.status = "accepted";
      taskState.acceptance = acceptance;
      writeState(specDir, state);
      projectTracking(specDir, state, tasks, task.taskId, acceptance);
      attempt.promotion.stage = "tracking_updated";
      advanceAfterAccepted(state, tasks, task.taskId);
      writeState(specDir, state);
      return { ok: true, accepted: acceptance };
    });
  });
}

function status(request) {
  const specDir = resolveSpecDir(requireString(request, "specDir"));
  const state = readState(specDir);
  return {
    ok: true,
    status: {
      schemaVersion: state.schemaVersion || 1,
      currentTaskId: state.currentTaskId || null,
      currentStage: state.currentStage || "preflight",
      activeAttemptId: state.activeAttemptId || null,
      lastFailureClass: state.lastFailureClass || null,
      taskOrder: state.taskOrder || [],
      budgets: state.budgets || { ...DEFAULT_BUDGETS, globalBudgetUsed: 0 },
      attempts: state.attempts || {},
      taskStates: state.taskStates || {},
      approvals: Object.fromEntries(Object.entries(state.approvals || {}).map(([name, approval]) => [
        name,
        { sha256: approval.sha256, hasEvidence: Boolean(approval.approvalEvidence) },
      ])),
    },
  };
}

function resume(request) {
  const specDir = resolveSpecDir(requireString(request, "specDir"));
  const repoRoot = path.resolve(requireString(request, "repoRoot"));
  const { tasksArtifact, tasks, requiredCoverage, state } = loadValidatedPlan(specDir, repoRoot);
  ensureLedger(state, tasks, tasksArtifact.hash);
  return {
    ok: true,
    phase: "execution",
    plan: buildPlanSummary(tasks, requiredCoverage, state),
    ledger: {
      runId: state.runId,
      taskOrder: state.taskOrder,
      currentTaskId: state.currentTaskId,
      currentStage: state.currentStage,
      activeAttemptId: state.activeAttemptId || null,
      budgets: state.budgets,
      taskStates: state.taskStates,
    },
  };
}

try {
  const request = parseJsonStdin();
  switch (request.op) {
    case "approve":
      respond(approve(request));
      break;
    case "preflight":
      respond(preflight(request));
      break;
    case "next":
      respond(next(request));
      break;
    case "report":
      respond(report(request));
      break;
    case "accept":
      respond(accept(request));
      break;
    case "resume":
      respond(resume(request));
      break;
    case "recover":
      throw requestError("recover is not implemented by the execution kernel POC");
    case "status":
      respond(status(request));
      break;
    default:
      throw requestError(`unsupported operation: ${request.op || "<missing>"}`);
  }
} catch (error) {
  errorResponse(error);
}
