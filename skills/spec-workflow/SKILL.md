# Spec Workflow

Spec-Drive follows a strict document chain where each phase produces an artifact that feeds the next. Agents read predecessor files directly — no template variables or context injection between phases.

## Phase Order

```
idea -> research -> requirements -> design -> tasks -> execution
```

1. **idea**: User creates idea.md via `/spec-drive:new`. Contains vision and constraints.
2. **research**: Researcher agent reads idea.md, produces research.md. Sets awaitingApproval=true (normal mode).
3. **requirements**: Product-manager reads idea.md + research.md, produces requirements.md with US/AC/FR/NFR.
4. **design**: Architect reads idea.md + research.md + requirements.md, produces design.md with components and decisions.
5. **tasks**: Task-planner reads requirements.md + design.md, produces tasks.md with phased task breakdown.
6. **execution**: Coordinator (implement.md) delegates tasks one-by-one to executor or qa-engineer. Stop-watcher continues loop across sessions.

## Document Chain

Each agent reads predecessor files directly via Read tool. No context summaries, no template variable expansion.

| Agent | Reads | Produces |
|-------|-------|----------|
| researcher | idea.md | research.md |
| product-manager | idea.md, research.md | requirements.md |
| architect | idea.md, research.md, requirements.md | design.md |
| task-planner | requirements.md, design.md | tasks.md |
| executor | Current task block, .progress.md | Code changes, commits |
| qa-engineer | [VERIFY] task block, requirements.md | VERIFICATION_PASS/FAIL |

## Approval Gates

In **normal mode** (default), `awaitingApproval=true` is set after each analysis phase completes. The user must review the artifact and explicitly invoke the next phase command.

In **auto mode** (`--auto` flag), spec-definition phases still stop for review. Auto mode is only allowed to continue automatically once the workflow has already reached a validated task plan and enters execution. Phase checklists are still enforced — if a checklist fails, auto mode stops with an error.

## Phase Transition Rules

See [phase-transitions.md](references/phase-transitions.md) for valid transitions and state changes.

## Quality Gates

Phase checklists validate artifact completeness before allowing transition to the next phase. Commands check these before delegating to agents.

See [phase-checklists.md](references/phase-checklists.md) for checklist definitions per transition.

## State Tracking

State is tracked in `.spec-drive-state.json` within the project's spec/ directory. Key fields:

- `phase`: Current phase (enum of the 6 phases)
- `awaitingApproval`: Whether the user needs to review before proceeding
- `mode`: "normal" (default) or "auto" (allows autonomous execution after task planning)
- `taskIndex`: Current task during execution phase
- `taskIteration`: Retry count for current task (resets per task)
- `globalIteration`: Total loop iterations across all tasks

## Project Artifact Topology

Spec-Drive project roots use four canonical destinations:

- `spec/` holds canonical Spec-Drive lifecycle artifacts and workflow state.
- `audit/` holds project-scoped audits, evidence, diagnostics, investigations, and hygiene records that are neither lifecycle canon nor deliverables.
- `input/` holds source material received or collected for the project.
- `output/` holds generated deliverables that are not canonical Spec-Drive lifecycle artifacts.

Agents executing Spec-Drive projects must use these names instead of ad hoc equivalents such as `docs/`, `notes/`, `artifacts/`, `evidence/`, `deliverables/`, or `tmp/` when the content belongs in one of the canonical destinations above.

`audit/`, `input/`, and `output/` are optional. Create each optional directory only immediately before writing its first content. The initial scaffold remains only the project root configuration plus the required `spec/` core.

## Configuration Scope And Portability

Workspace topology may be heterogeneous: a workspace can contain multiple independent project roots, including nested Git repositories, without changing the project artifact contract.

Resolve configuration per key with this precedence:

1. project scope
2. workspace scope
3. legacy XDG scope

Rules:

- Project scope carries portable project identity and project-local overrides.
- Workspace scope carries node-local topology such as the projects container.
- A present but invalid configuration at any scope is an error and must fail instead of being ignored.
- An absent scope falls back to the next scope in precedence order.
- Legacy XDG remains a lowest-precedence compatibility fallback.

## Publication Boundary

The local source repository is separate from any distribution or marketplace sync. Running the project locally, editing local files, and validating changes do not authorize any remote or public action.

Every issue, push, pull request, release, publication, or marketplace/distribution sync requires separate explicit owner approval. Agents must not infer, batch, or bypass that approval.
