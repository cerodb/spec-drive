# Fixture: migration-guard
expected_tier: advanced

- [ ] 3.2 Add a rollback-safe state migration guard
  - **Do**:
    1. Add a migration step that backfills a missing state field when loading older project state files.
    2. Guard the migration so partially written state never gets persisted.
    3. Add coverage for the upgrade path and the rollback path.
  - **Files**: `schemas/spec-drive.schema.json`, `hooks/scripts/context-loader.sh`, `test/test-schema.sh`, `test/test-smoke.sh`
  - **Traces**: FR-7, NFR-2
  - **Cwd**: `<repoRoot>`
  - **Done when**: older state files upgrade cleanly and failed migrations leave persisted state unchanged.
  - **Verify**: `bash test/test-schema.sh && bash test/test-smoke.sh`
  - **Timeout**: `120s`
  - **Commit**: `fix(state): add guarded migration for legacy files`
