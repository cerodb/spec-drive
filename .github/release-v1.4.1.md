# Spec-Drive v1.4.1

Maintenance release. **No runtime change over v1.4.0.**

This release exists so that a given version number identifies exactly one snapshot.
v1.4.0 shipped with a test harness that failed on macOS; the fix landed after the tag,
which left the source repo and the distributed copy both calling themselves `1.4.0`
while holding different files. v1.4.1 closes that gap.

## What changed

- Test suites no longer compare raw `mktemp -d` output against resolver output.
  On macOS the temp root is reached through a symlink (`/var` -> `/private/var`),
  which `portable_realpath` resolves, so the assertions failed there while passing
  on Linux. The product behaviour was correct throughout.
- A hooks assertion no longer passes a non-existent start dir, so it exercises the
  intended tier instead of the `$PWD` fallback.
- A failure diagnostic is guarded, so a red suite with no `FAIL:` lines no longer
  aborts the run and hides the suites after it.
- New suite `test/test-macos-pathing.sh`, wired into `npm test`.

## What did not change

No command, agent, hook, skill, schema, profile, or template was modified.
Installing v1.4.1 over v1.4.0 changes nothing at runtime.

## Validation

- `npm test` green on ubuntu-latest and macos-latest
- disclosure scan (`test/test-public-clean.sh`) green
