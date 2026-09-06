---
spec: "{{spec_name}}"
phase: tasks
status: "complete"
created: "{{timestamp}}"
requirements_sha: "{{approved_requirements_sha256}}"
design_sha: "{{approved_design_sha256}}"
repoRoot: "{{repo_root}}"
shell: "bash"
---

# Tasks: {{spec_name}}

## Phase 1: Make It Work (POC)

<!-- Minimal working implementation. Hardcoded values are fine. Skip tests. Goal: prove the approach works end-to-end. Each task needs: Do (steps), Files (unique repo-relative paths), Traces (known AC/FR/NFR ids), an optional model: <tier> field placed after Traces and before Cwd (tier is one of light|standard|advanced|frontier — omit to inherit the default model), Cwd (repo-relative working directory), Done when (criteria), Verify (one non-destructive command), Timeout (positive integer seconds, without a unit), and Commit (message). After the task completes, the executor may record which tier actually ran as model_used: <tier>. -->

- [ ] 1.1 ...

- [ ] V1 [VERIFY] Checkpoint: ...
  - **Do**: Validate the complete preceding unchecked batch.
  - **Files**: none
  - **Traces**: AC-1.1, NFR-1
  - **Cwd**: .
  - **Done when**: The preceding batch passes its automated contract.
  - **Verify**: `repo-local command`
  - **Timeout**: 120
  - **Commit**: none

## Phase 2: Refactoring

<!-- Clean up POC code. Extract patterns, add error handling, follow project conventions. No new features. -->

- [ ] 2.1 ...

## Phase 3: Testing

<!-- Write tests for the implementation. Unit tests first, then integration. All tests must pass before proceeding. -->

- [ ] 3.1 ...

## Phase 4: Quality Gates

<!-- Final checks: linting, type checking, documentation. All local quality gates must pass. Prepare for review. -->

- [ ] 4.1 ...

## Coverage Matrix

| AC / NFR | Task IDs |
|----------|----------|
| AC-1.1 | 1.1, V1 |
| NFR-1 | 1.1, V1 |
