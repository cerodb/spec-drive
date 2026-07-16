# Fixture: command-test
expected_tier: standard

- [ ] 2.1 Add a command smoke test for a new status flag
  - **Do**:
    1. Extend the command smoke test to cover a new `--summary` status flag.
    2. Assert the output stays on one line and exits successfully.
  - **Files**: `test/test-commands.sh`, `commands/status.md`
  - **Traces**: FR-3
  - **Cwd**: `<repoRoot>`
  - **Done when**: the test covers the new flag and passes locally.
  - **Verify**: `bash test/test-commands.sh`
  - **Timeout**: `60s`
  - **Commit**: `test(commands): cover status summary flag`
