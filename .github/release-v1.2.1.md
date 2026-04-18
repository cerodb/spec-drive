## Spec-Drive v1.2.1

Small post-QA polish release after `v1.2.0`.

### What's new

- researcher now walks sibling specs under `repoRoot/specs/`
- `research.md` now requires a `## Related Specs` section
- task-planner now gates Phase 5 PR lifecycle on explicit remote-target evidence
- small local-only projects stay compact instead of inheriting unreachable PR tasks
- structural tests now protect both fixes

### Install

```text
/plugin marketplace add cerodb/cerodb-plugins
/plugin install spec-drive@cerodb
```

### Notes

- source tag: `v1.2.1`
- follow-on QA project: `P344`
- keep `P344` open pending tester confirmation
