#!/usr/bin/env node
// Read-only project routing. A kernel error must never trigger a legacy fallback.
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
export function resolveRuntime(specDir) {
  if (typeof specDir !== 'string' || !specDir.trim()) throw new Error('specDir is required');
  const file = path.join(specDir, '.spec-drive-state.json');
  if (!existsSync(file)) throw new Error(`No state at ${file}; locate the existing spec before continuing`);
  const state = JSON.parse(readFileSync(file, 'utf8'));
  if (!state || typeof state !== 'object' || Array.isArray(state)) throw new Error('State must be a JSON object');
  if (state.schemaVersion !== undefined && ![1, 2].includes(state.schemaVersion)) {
    throw new Error(`Unsupported schemaVersion: ${state.schemaVersion}`);
  }
  // 2.0 already wrote schemaVersion=2, including during planning. Stable IDs by
  // themselves are not proof: externally coordinated legacy specs also use them.
  const kernel = state.schemaVersion === 2 || typeof state.runId === 'string'
    || Object.keys(state).every(key => ['schemaVersion', 'approvals'].includes(key));
  if (!kernel && (typeof state.name !== 'string' || typeof state.phase !== 'string')) {
    throw new Error('Unrecognized state; inspect its history before choosing a conductor');
  }
  return {
    ok: true,
    runtime: kernel ? 'kernel-v2' : 'legacy',
    reason: kernel ? 'Kernel state; normal validation and recovery still apply' : 'Existing pre-kernel project; preserve its format and progress',
    specDir: path.resolve(specDir),
    commandPath: kernel ? null : path.join(root, 'docs/legacy-mode-en.md'),
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const request = JSON.parse(readFileSync(0, 'utf8'));
    process.stdout.write(`${JSON.stringify(resolveRuntime(request.specDir))}\n`);
  } catch (error) {
    process.stdout.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
    process.exitCode = 1;
  }
}
