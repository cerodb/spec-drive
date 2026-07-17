# Fixture: inline-comment
expected_tier: light

- [ ] 1.2 Add a clarifying shell comment
  - **Do**:
    1. Add one short comment above the environment bootstrap line in the test script.
    2. Do not change command order or behavior.
  - **Files**: `test/test-hooks.sh`
  - **Traces**: FR-2
  - **Cwd**: `<repoRoot>`
  - **Done when**: the script includes the new comment and still behaves exactly the same.
  - **Verify**: `bash -n test/test-hooks.sh`
  - **Timeout**: `30s`
  - **Commit**: `docs(test): clarify bootstrap comment`
