# Delegation Principle

The coordinator (implement.md command) NEVER implements tasks directly. It always delegates via the Task tool.

## Rule

All task work is performed by specialized agents. The coordinator's sole job is orchestration: reading state, determining the next action, delegating, and updating state based on results.

## Coordinator Responsibilities

1. Read `.spec-drive-state.json` to determine current task
2. Parse the task block from tasks.md at the current taskIndex
3. Detect task type: `[P]` for parallel, `[VERIFY]` for QA delegation
4. Delegate to the appropriate agent via Task tool:
   - Regular tasks -> executor agent
   - `[VERIFY]` tasks -> qa-engineer agent
5. Wait for agent signal (TASK_COMPLETE, VERIFICATION_PASS, VERIFICATION_FAIL)
6. Update state: advance taskIndex on success, increment taskIteration on failure
7. When all tasks complete: output ALL_TASKS_COMPLETE

## Coordinator NEVER Does

- Write application code
- Run git commands (add, commit, push)
- Perform codebase analysis or exploration
- Read/modify project source files
- Execute verification commands
- Make implementation decisions

These are all the executor's or qa-engineer's responsibilities.

## Why

Fresh context isolation. The executor operates with minimal context (task block + .progress.md only). If the coordinator also implemented tasks, it would accumulate the full spec context in its window, violating the fresh-context-per-task design and risking context window exhaustion on large projects.

Separation also enables retry semantics: a failed task spawns a new executor with clean state and failure context from .progress.md, rather than retrying within a polluted context window.
