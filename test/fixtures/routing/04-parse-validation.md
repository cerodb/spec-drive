# Fixture: parse-validation
expected_tier: standard

- [ ] 2.2 Tighten parsing for a small config field
  - **Do**:
    1. Update the config loader to reject empty `projectRoot` values.
    2. Add a validation test for the empty-string case.
  - **Files**: `hooks/scripts/resolve-config.sh`, `test/test-hooks.sh`
  - **Traces**: FR-4
  - **Cwd**: `<repoRoot>`
  - **Done when**: empty `projectRoot` values fail validation and the new test passes.
  - **Verify**: `bash test/test-hooks.sh`
  - **Timeout**: `60s`
  - **Commit**: `fix(config): reject empty projectRoot`
