import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';

const kernel = fileURLToPath(new URL('../../hooks/scripts/execution-kernel.mjs', import.meta.url));
const schema = JSON.parse(readFileSync(fileURLToPath(new URL('../../schemas/spec-drive.schema.json', import.meta.url)), 'utf8'));
const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
const validateState = ajv.compile(schema);

function assertPersistedStateSchema(f) {
  const file = path.join(f.spec, '.spec-drive-state.json');
  if (!existsSync(file)) return;
  assert.equal(validateState(JSON.parse(readFileSync(file, 'utf8'))), true,
    `persisted kernel state violates schema: ${ajv.errorsText(validateState.errors, { separator: '\n' })}`);
}
export const digest = (s) => createHash('sha256').update(s).digest('hex');
export function git(repo, ...args) {
  const r = spawnSync('git', ['-C', repo, ...args], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.trim();
}
export function call(f, op, extra = {}) {
  const r = spawnSync(process.execPath, [kernel], {
    input: JSON.stringify({ op, specDir: f.spec, repoRoot: f.repo, ...extra }),
    encoding: 'utf8', timeout: 30000,
    env: { ...process.env, XDG_CONFIG_HOME: path.join(f.root, 'config') },
  });
  assert.ifError(r.error);
  let response;
  try { response = JSON.parse(r.stdout); } catch { throw new Error(r.stderr + r.stdout); }
  assertPersistedStateSchema(f);
  return response;
}
export function ok(result) { assert.equal(result.ok, true, JSON.stringify(result)); return result; }
export function state(f) { return JSON.parse(readFileSync(path.join(f.spec, '.spec-drive-state.json'), 'utf8')); }
export function fixture({ inline = false, verify = 'test -f result.txt', tasks = 1, timeout = 5 } = {}) {
  const root = realpathSync(mkdtempSync(path.join(tmpdir(), 'spec-drive-release-')));
  const repo = path.join(root, 'repo');
  const spec = inline ? path.join(repo, 'spec') : path.join(root, 'spec');
  mkdirSync(repo, { recursive: true }); mkdirSync(spec, { recursive: true });
  const f = { root, repo, spec, cleanup: () => rmSync(root, { recursive: true, force: true }) };
  if (typeof verify === 'function') verify = verify(f);
  writeFileSync(path.join(repo, 'baseline.txt'), 'baseline\n');
  const req = '---\nspec: release\nphase: requirements\nstatus: complete\n---\n# Requirements\n- AC-1.1: Produce a result.\n- NFR-1: Preserve work.\n';
  const design = `---\nspec: release\nphase: design\nstatus: complete\nrequirements_sha: ${digest(req)}\n---\n# Design\nAC-1.1, NFR-1\n`;
  let plan = `---\nspec: release\nphase: tasks\nstatus: complete\nrequirements_sha: ${digest(req)}\ndesign_sha: ${digest(design)}\n---\n# Tasks\n`;
  for (let i = 1; i <= tasks; i++) plan += `- [ ] 1.${i} Write result\n  - **Do**: Write a result.\n  - **Files**: ${i === 1 ? 'result.txt' : `result${i}.txt`}\n  - **Traces**: AC-1.1, NFR-1\n  - **Cwd**: .\n  - **Done when**: Verify passes.\n  - **Verify**: ${verify}\n  - **Timeout**: ${timeout}\n  - **Commit**: feat: result ${i}\n`;
  writeFileSync(path.join(spec, '.spec-drive-state.json'), JSON.stringify({ name: 'release', basePath: spec, phase: 'tasks', schemaVersion: 2 }));
  for (const [artifact, data] of [['requirements', req], ['design', design], ['tasks', plan]]) {
    writeFileSync(path.join(spec, artifact + '.md'), data);
    ok(call(f, 'approve', { artifact, expectedSha256: digest(data), approvalEvidence: 'Explicit fixture approval' }));
  }
  git(repo, 'init', '-q'); git(repo, 'config', 'user.name', 'Release Fixture');
  git(repo, 'config', 'user.email', 'fixture@example.invalid'); git(repo, 'config', 'commit.gpgsign', 'false');
  git(repo, 'add', '.'); git(repo, 'commit', '-qm', 'baseline');
  return f;
}
export function dispatch(f) { return ok(call(f, 'next', { actor: 'implement' })).dispatch; }
export function report(f, d) {
  return ok(call(f, 'report', { attemptId: d.attemptId, adapterEvidence: 'started', report: {
    attemptId: d.attemptId, taskId: d.taskId, outcome: 'task_complete', startedWork: true, summary: 'Fixture finished',
  } }));
}
export function result(d, text = 'ok\n', file = 'result.txt') { writeFileSync(path.join(d.worktreePath, file), text); }
