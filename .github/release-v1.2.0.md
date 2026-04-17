## Spec-Drive v1.2.0

This release improves orchestration quality and downstream output shape.

### What's new

- direct `/spec-drive:tasks`
- better coordinator conflict handling
- tighter `design.md` and `tasks.md` output
- stronger regression coverage

### Install

```text
/plugin marketplace add cerodb/cerodb-plugins
/plugin install spec-drive@cerodb
```

Optional ClawHub wrapper skill:

```bash
clawhub install spec-drive
```
