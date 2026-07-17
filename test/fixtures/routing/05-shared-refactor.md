# Fixture: shared-refactor
expected_tier: advanced

- [ ] 3.1 Refactor shared task parsing to remove duplicated fallback logic
  - **Do**:
    1. Extract the repeated task-block parsing logic into a shared helper used by the command runner and the hook script.
    2. Preserve backward compatibility for legacy task blocks with missing optional fields.
    3. Cover the main edge cases with one focused regression test.
  - **Files**: `commands/implement.md`, `hooks/scripts/context-loader.sh`, `hooks/scripts/resolve-model.sh`, `test/test-smoke.sh`
  - **Traces**: FR-5, FR-6
  - **Cwd**: `<repoRoot>`
  - **Done when**: both call sites use the shared helper and legacy blocks still parse correctly.
  - **Verify**: `bash test/test-smoke.sh`
  - **Timeout**: `90s`
  - **Commit**: `refactor(tasks): share parser fallback logic`
