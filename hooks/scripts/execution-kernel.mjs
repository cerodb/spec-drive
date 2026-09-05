#!/usr/bin/env node
import { createHash } from "node:crypto";
import {
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";

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
  const files = parseList(task.fields.Files);
  if (task.taskType === "verify") {
    if (task.fields.Files.trim() !== "none" || task.fields.Commit.trim() !== "none") {
      throw artifactError("checkpoint tasks must declare Files=none and Commit=none", { taskId: task.taskId });
    }
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
    if (state.currentStage === "reported_complete") {
      throw requestError("task is awaiting authoritative acceptance; accept is not implemented until task 1.3", {
        taskId: state.currentTaskId,
        attemptId: state.activeAttemptId || state.taskStates?.[state.currentTaskId]?.latestAttemptId || null,
        nextAction: "run final verification and wait for accept support",
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
    const sequence = taskState.attempts.length + 1;
    const attemptId = `${task.taskId.replace(/\W+/g, "-")}-a${sequence}-${Date.now().toString(36)}`;
    const worktreePath = path.join(repoRoot, ".spec-drive", "worktrees", state.runId, task.taskId);
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
        branch: `spec-drive/${state.runId}/${task.taskId}`,
        targetHeadAtCreate: "unknown",
        files: task.files,
      },
    };
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
