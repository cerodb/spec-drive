#!/usr/bin/env node
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
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
  respond(response, code === "artifact_error" ? 2 : 1);
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

function readState(specDir) {
  const file = statePath(specDir);
  if (!existsSync(file)) {
    return { schemaVersion: 1, approvals: {} };
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

function writeState(specDir, state) {
  writeFileSync(statePath(specDir), `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
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

function buildPlanSummary(tasks, requiredTraceIds) {
  return {
    totalTasks: tasks.length,
    requiredTasks: tasks.length,
    acceptedTasks: 0,
    pendingTasks: tasks.length,
    taskOrder: tasks.map((task) => task.taskId),
    requiredTraceIds: [...requiredTraceIds].sort(),
  };
}

function preflight(request) {
  const specDir = resolveSpecDir(requireString(request, "specDir"));
  const repoRoot = path.resolve(requireString(request, "repoRoot"));
  if (!existsSync(repoRoot)) {
    throw artifactError(`repoRoot does not exist: ${request.repoRoot}`, { artifact: "repoRoot" });
  }
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
  requireApproval(state, "tasks", tasksArtifact.hash);
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
    plan: buildPlanSummary(tasks, requiredCoverage),
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
  const state = readState(specDir);
  state.schemaVersion = 1;
  state.approvals ||= {};
  state.approvals[artifact] = {
    sha256: current.hash,
    approvalEvidence,
    approvedAt: new Date().toISOString(),
  };
  writeState(specDir, state);
  return { ok: true, approved: artifact, sha256: current.hash };
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
      approvals: Object.fromEntries(Object.entries(state.approvals || {}).map(([name, approval]) => [
        name,
        { sha256: approval.sha256, hasEvidence: Boolean(approval.approvalEvidence) },
      ])),
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
    case "status":
      respond(status(request));
      break;
    default:
      throw requestError(`unsupported operation: ${request.op || "<missing>"}`);
  }
} catch (error) {
  errorResponse(error);
}
