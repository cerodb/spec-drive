# Fixture: auth-rotation
expected_tier: frontier

- [ ] 4.1 Rotate authentication for a live external provider without breaking active sessions
  - **Do**:
    1. Replace the current token exchange flow with a new OAuth provider contract.
    2. Preserve active sessions during the cutover and document the rollback strategy.
    3. Add verification that the live provider rejects stale credentials after rotation.
  - **Files**: `commands/implement.md`, `hooks/scripts/resolve-config.sh`, `hooks/scripts/context-loader.sh`, `schemas/spec-drive.schema.json`, `test/test-hooks.sh`, `test/test-smoke.sh`
  - **Traces**: FR-8, NFR-3
  - **Cwd**: `<repoRoot>`
  - **Done when**: the new provider flow works, active sessions survive rotation, and stale credentials are rejected.
  - **Verify**: `bash test/test-hooks.sh && bash test/test-smoke.sh`
  - **Timeout**: `180s`
  - **Commit**: `feat(auth): rotate live oauth provider contract`
