#!/usr/bin/env node
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { resolveRuntime } from '../hooks/scripts/runtime-route.mjs';

const scripts = fileURLToPath(new URL('../hooks/scripts/', import.meta.url));
const root = realpathSync(mkdtempSync(path.join(tmpdir(), 'spec-drive-legacy-')));
const project = path.join(root, 'started');
const spec = path.join(project, 'spec');
mkdirSync(spec, { recursive: true });
const stateFile = path.join(spec, '.spec-drive-state.json');
const legacy = { name: 'started', basePath: spec, phase: 'execution', mode: 'normal',
  awaitingApproval: false, taskIndex: 1, totalTasks: 3, taskIteration: 2, globalIteration: 4,
  currentTaskId: '1.2', taskResults: { '1.1': { status: 'success' } }, custom: { preserve: true } };
writeFileSync(path.join(project, '.spec-drive-config.json'), JSON.stringify({ projectRoot: root }));
writeFileSync(path.join(spec, 'tasks.md'), '- [x] 1.1 Done\n- [-] 1.2 Partly implemented\n  - Verify: test -f partial.txt\n- [ ] V1 [VERIFY] Check result\n');
writeFileSync(path.join(project, 'partial.txt'), 'unfinished work\n');
writeFileSync(path.join(spec, '.progress.md'), 'Task 1.1 complete; 1.2 in progress.\n');
const tracked = [stateFile, path.join(spec, 'tasks.md'), path.join(spec, '.progress.md'), path.join(project, 'partial.txt')];
const run = (script, input) => spawnSync(script.endsWith('.sh') ? 'bash' : process.execPath,
  [path.join(scripts, script)], { input: JSON.stringify(input), encoding: 'utf8', env: process.env });
try {
  writeFileSync(stateFile, JSON.stringify(legacy, null, 2) + '\n');
  const before = tracked.map(f => readFileSync(f));
  const route = resolveRuntime(spec);
  assert.equal(route.runtime, 'legacy'); // stable IDs alone are still legacy
  assert.match(readFileSync(route.commandPath, 'utf8'), /Never reset to task 0/);
  for (const hook of ['context-loader.sh', 'stop-watcher.sh']) {
    const r = run(hook, { cwd: project });
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout + r.stderr, /Legacy mode/);
    assert.match(r.stdout + r.stderr, /legacy-mode-en.md/);
  }
  for (const op of ['resume', 'pause', 'approve']) {
    const r = run('execution-kernel.mjs', { op, specDir: spec, reason: 'fixture' });
    assert.notEqual(r.status, 0);
    assert.match(r.stdout, /legacy mode/);
  }
  tracked.forEach((f, i) => assert.deepEqual(readFileSync(f), before[i], f));
  console.log('PASS legacy started task: routing/hooks preserve cursor, history and partial work');

  writeFileSync(stateFile, JSON.stringify({ ...legacy, awaitingApproval: true }));
  assert.equal(run('stop-watcher.sh', { cwd: project }).stdout, '');
  writeFileSync(stateFile, JSON.stringify({ ...legacy, phase: 'completed' }));
  assert.equal(run('stop-watcher.sh', { cwd: project }).stdout, '');
  console.log('PASS legacy paused and completed specs do not auto-resume');

  const modern = { name: 'modern', basePath: spec, phase: 'execution', schemaVersion: 2,
    currentTaskId: '1.2', currentStage: 'indeterminate', activeAttemptId: 'a-1' };
  writeFileSync(stateFile, JSON.stringify(modern));
  assert.equal(resolveRuntime(spec).runtime, 'kernel-v2');
  const status = run('execution-kernel.mjs', { op: 'status', specDir: spec });
  assert.equal(JSON.parse(status.stdout).status.currentTaskId, '1.2');
  assert.equal(resolveRuntime(spec).runtime, 'kernel-v2');
  console.log('PASS existing 2.0 kernel state stays on kernel, including interrupted execution');

  for (const bytes of ['{broken', JSON.stringify({ ...legacy, schemaVersion: 99 })]) {
    writeFileSync(stateFile, bytes);
    const r = run('runtime-route.mjs', { specDir: spec });
    assert.notEqual(r.status, 0);
    assert.equal(JSON.parse(r.stdout).ok, false);
    assert.equal(readFileSync(stateFile, 'utf8'), bytes);
  }
  console.log('PASS corrupt and unknown-version state are preserved with actionable errors');
} finally {
  rmSync(root, { recursive: true, force: true });
}
