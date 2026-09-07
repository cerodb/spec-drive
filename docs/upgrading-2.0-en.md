# Upgrading to Spec-Drive 2.0

**2.1 compatibility update:** existing pre-kernel projects now select the shared
[legacy conductor](legacy-mode-en.md) automatically per project. Use the usual
`/spec-drive:status` and `/spec-drive:implement` commands to continue partial work
without reinstalling 1.x. Existing kernel projects continue through the kernel.
The following describes the original 2.0 execution contract and remains the
guidance for new kernel specs; there is still no automatic state migration.

2.0.0 is prepared as an unpublished candidate. It changes execution state and acceptance
contracts. The planning sequence remains idea, research, requirements, design and tasks.

Before switching an active project, preserve its artifacts, current state, worktrees and Git
checkpoint. Finish an index-only legacy execution with its original driver, or start a fresh
2.0 execution spec with reviewed artifacts and explicit approvals. The kernel preserves and
rejects legacy index-only state; it does not migrate that state automatically. Do not replace
an active ledger or treat old checkbox positions as new acceptance evidence.

Install Node.js >=18 alongside Bash, Git and jq. Contributors run `npm ci` before `npm test`;
Ajv validates emitted state in the test suite and is not a runtime dependency of the kernel.

Every artifact approval includes its SHA-256 and explicit approval evidence, including in
auto mode. Task IDs remain stable across execution and recovery. Parallel-marked tasks run
serially. `next` resolves the existing CLI model profile and returns the adapter mechanism,
model and command. The ledger remains authoritative across agent, subprocess and inherited
execution. These adapter contracts have fixture coverage; this release does not claim a new
live-model benchmark or a measured token saving.

The executor reports work; the kernel independently runs Verify and accepts it. A nonzero
test result enables a new attempt within the existing budget. Exit 126/127 and timeout are
treated as environment failures and need `recover` with explicit evidence after the environment
is repaired. Verify mutation of candidate bytes, HEAD or index requires inspection and
restoration of the recorded candidate before recovery. Worktree bytes remain available.

Verify runs once in the attempt worktree and once on the target for code tasks. Configure
disposable output such as coverage reports in `$SPEC_DRIVE_VERIFY_TMPDIR` or `$TMPDIR`.
Each invocation gets its own directory, which is removed afterward. Outputs needed as product
artifacts must be produced by the implementation task and declared in Files; Verify validates
them without modifying them. Ignored files inside the repository are still protected.

A spec can live under the target repository. The exact kernel state file and unmodified
kernel task/progress projections do not count as external product edits. Product commits include
only declared task files; the updated spec state, checkboxes and progress remain unstaged.
After execution is idle, the operator can review and commit those metadata files as a separate
checkpoint. Do not stage metadata during promotion. Other edits and unrelated spec files remain
protected, and existing Git commit-signing settings remain in effect.
