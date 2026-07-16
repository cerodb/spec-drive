# Fixture: breaking-contract
expected_tier: frontier

- [ ] 4.2 Redesign the published task contract for downstream clients
  - **Do**:
    1. Replace the current task block format with a new public contract consumed by multiple downstream tools.
    2. Reconcile conflicting compatibility requirements between existing clients and the new contract.
    3. Ship a staged transition plan for the breaking change and document failure handling.
  - **Files**: `templates/tasks.md`, `agents/task-planner.md`, `commands/implement.md`, `agents/executor.md`, `schemas/spec-drive.schema.json`, `README.md`
  - **Traces**: FR-9, NFR-4
  - **Cwd**: `<repoRoot>`
  - **Done when**: the public contract is documented, downstream compatibility is explicitly addressed, and the transition plan is executable.
  - **Verify**: `bash test/test-structure.sh && bash test/test-schema.sh`
  - **Timeout**: `180s`
  - **Commit**: `feat(contract): redesign published task block format`
