import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, symlinkSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fixture, call, ok, state, git, dispatch, report, result } from './helpers/kernel-fixture.mjs';

function test(name, options, fn) {
  const f = fixture(options);
  try { fn(f); console.log(`PASS: ${name}`); } finally { f.cleanup(); }
}

test('versioned spec completes two tasks and preserves lifecycle through path aliases', { inline: true, tasks: 2 }, (f) => {
  const alias = path.join(f.root, 'alias'); symlinkSync(f.repo, alias);
  const logical = { ...f, repo: alias, spec: path.join(alias, 'spec') };
  for (let i = 1; i <= 2; i++) {
    const d = dispatch(logical);
    assert.equal(state(f).phase, 'execution');
    result(d, 'ok\n', i === 1 ? 'result.txt' : 'result2.txt'); report(f, d);
    ok(call(logical, 'accept', { attemptId: d.attemptId }));
    const committed = git(f.repo, 'diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD');
    assert.equal(committed, i === 1 ? 'result.txt' : 'result2.txt');
  }
  assert.equal(state(f).phase, 'completed');
  assert.equal(call(f, 'status').status.currentTaskId, null);
  assert.equal(call(logical, 'resume').ledger.currentTaskId, null);
  assert.match(readFileSync(path.join(f.spec, 'tasks.md'), 'utf8'), /\[x\] 1.2/);
});

test('external spec edits remain visible', { inline: true, tasks: 2 }, (f) => {
  const d = dispatch(f); result(d); report(f, d); ok(call(f, 'accept', { attemptId: d.attemptId }));
  writeFileSync(path.join(f.spec, '.progress.md'), 'external notes\n');
  const r = call(f, 'next', { actor: 'implement' }); assert.equal(r.ok, false);
  assert.match(JSON.stringify(r), /external changes/);
  assert.equal(readFileSync(path.join(f.spec, '.progress.md'), 'utf8'), 'external notes\n');
});

test('failed worktree Verify retries with preserved bytes and budget', { verify: 'test "$(cat result.txt)" = good' }, (f) => {
  const first = dispatch(f); result(first, 'bad\n'); report(f, first);
  assert.equal(call(f, 'accept', { attemptId: first.attemptId }).ok, false);
  let s = state(f); assert.equal(s.attempts[first.attemptId].verificationFailure.failureClass, 'logic_error');
  assert.equal(s.currentStage, 'ready'); assert.equal(s.taskStates['1.1'].executionAttempts, 1);
  assert.equal(call(f, 'accept', { attemptId: first.attemptId }).ok, false);
  const second = dispatch(f); assert.equal(second.worktreePath, first.worktreePath);
  assert.equal(readFileSync(path.join(second.worktreePath, 'result.txt'), 'utf8'), 'bad\n');
  assert.notEqual(second.attemptId, first.attemptId);
  result(second, 'good\n'); report(f, second); ok(call(f, 'accept', { attemptId: second.attemptId }));
  s = state(f); assert.equal(s.taskStates['1.1'].executionAttempts, 2); assert.equal(s.budgets.globalBudgetUsed, 2);
});

test('failed target Verify reverses only owned patch and retries', { verify: (f) => `test "$PWD" != '${f.repo}' || test "$(cat result.txt)" = good` }, (f) => {
  const first = dispatch(f);
  result(first, 'bad\n'); report(f, first);
  assert.equal(call(f, 'accept', { attemptId: first.attemptId }).ok, false);
  const failure = state(f).attempts[first.attemptId].verificationFailure;
  assert.equal(failure.location, 'target'); assert.equal(failure.promotionRolledBack, true);
  assert.equal(existsSync(path.join(f.repo, 'result.txt')), false);
  assert.equal(readFileSync(path.join(first.worktreePath, 'result.txt'), 'utf8'), 'bad\n');
  const retry = dispatch(f); result(retry, 'good\n'); report(f, retry);
  ok(call(f, 'accept', { attemptId: retry.attemptId }));
});

test('Verify outputs use external temporary directory', { verify: 'touch "$SPEC_DRIVE_VERIFY_TMPDIR/output" && test "$TMPDIR" = "$SPEC_DRIVE_VERIFY_TMPDIR"' }, (f) => {
  const d = dispatch(f); result(d); report(f, d); ok(call(f, 'accept', { attemptId: d.attemptId }));
  assert.equal(git(f.repo, 'status', '--porcelain', '--untracked-files=no'), '');
});

test('Verify mutations stay blocked and preserve evidence', { verify: 'touch unexpected.txt' }, (f) => {
  const d = dispatch(f); result(d); report(f, d);
  assert.equal(call(f, 'accept', { attemptId: d.attemptId }).ok, false);
  assert.equal(state(f).attempts[d.attemptId].verificationFailure.failureClass, 'verify_error');
  assert.equal(call(f, 'next', { actor: 'implement' }).ok, false);
  assert.equal(existsSync(path.join(d.worktreePath, 'unexpected.txt')), true);
});

test('timeout requires explicit recovery and preserves execution budget', { verify: 'sleep 2', timeout: 1 }, (f) => {
  const d = dispatch(f); result(d); report(f, d);
  assert.equal(call(f, 'accept', { attemptId: d.attemptId }).ok, false);
  assert.equal(state(f).attempts[d.attemptId].verificationFailure.failureClass, 'env_error');
  assert.equal(call(f, 'next', { actor: 'implement' }).ok, false);
  ok(call(f, 'recover', { attemptId: d.attemptId, evidence: 'Timed out process has terminated; environment checked' }));
  const retry = dispatch(f); assert.equal(retry.worktreePath, d.worktreePath);
  assert.equal(state(f).taskStates['1.1'].executionAttempts, 2);
});
