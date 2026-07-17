# Fixture: doc-heading
expected_tier: light

- [ ] 1.1 Rename a README heading for consistency
  - **Do**:
    1. Rename the "Quick start" heading in the README to "Getting Started".
    2. Keep the existing content and links unchanged.
  - **Files**: `README.md`
  - **Traces**: FR-1
  - **Cwd**: `<repoRoot>`
  - **Done when**: the heading is renamed and the section anchor still works.
  - **Verify**: `grep -q '^## Getting Started$' README.md`
  - **Timeout**: `30s`
  - **Commit**: `docs(readme): rename quick start heading`
