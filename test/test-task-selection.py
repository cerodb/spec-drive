"""Regression contracts for prompt-driven selection (not a live model E2E)."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMAND = (ROOT / "commands/implement.md").read_text()


def select(plan, previous_index=0):
    # Fixture reader only: execute the reference from the actual command, not
    # an independently maintained copy of its selection algorithm.
    tasks = [{"id": match[1], "completed": match[0].lower() == "x"}
             for match in re.findall(r"^- \[([ xX])\] (\d+\.\d+)\b", plan, re.M)]
    blocks = re.findall(r"```python\n(.*?)```", COMMAND, re.S)
    rule = next(block for block in blocks if "# Task selection reference:" in block)
    scope = {"tasks": tasks, "taskIndex": previous_index}
    exec(compile(rule, "implement.md selection reference", "exec"), scope)
    return scope["taskIndex"], scope["totalTasks"]


class TaskSelection(unittest.TestCase):
    def test_sequence_and_completion(self):
        plan = "- [ ] 1.1 A\n- [ ] 1.2 B\n- [ ] 1.3 C\n"
        seen = []
        for index in range(3):
            current, count = select(plan, index)
            self.assertEqual((current, count), (index, 3))
            seen.append(current)
            plan = plan.replace(f"- [ ] 1.{index + 1}", f"- [x] 1.{index + 1}")
        self.assertEqual(seen, [0, 1, 2])
        self.assertEqual(select(plan, 2), (3, 3))

    def test_resume_ignores_stale_cursor(self):
        plan = "- [X] 1.1 A\n- [ ] 1.2 B\n- [ ] 1.3 C\n"
        for stale in (0, 1, 2, 3, 99):
            self.assertEqual(select(plan, stale), (1, 3))

    def test_partial_parallel_batch_does_not_skip_failure(self):
        plan = "- [x] 1.1 [P] A\n- [ ] 1.2 [P] B\n- [x] 1.3 [P] C\n- [ ] 2.1 D\n"
        self.assertEqual(select(plan, 3), (1, 4))

    def test_nested_acceptance_checkboxes_are_not_tasks(self):
        plan = "- [x] 1.1 A\n  - [ ] 9.9 nested criterion\n- [ ] 1.2 B\n"
        self.assertEqual(select(plan), (1, 2))

    def test_instruction_guards(self):
        for text in (
            "every loop and resume", "a missing/empty plan is not successful completion",
            "STOP for supervised reconciliation", "Do not reset retry counters",
            "A stored index alone never proves completion",
            '"<completedTaskIndex>"', "never advance twice",
        ):
            self.assertIn(text, COMMAND)
        self.assertNotIn("Index to `taskIndex` (0-based)", COMMAND)
        self.assertNotIn("Advance `taskIndex` by 1", COMMAND)

    def test_ownership_is_consistent(self):
        self.assertIn("coordinator MUST independently re-run Verify", COMMAND)
        self.assertIn("coordinator owns task-scoped git staging, commits", COMMAND)
        self.assertNotIn("NEVER run git commands", COMMAND)
        self.assertNotIn("NEVER run verification commands", COMMAND)
        for filename in ("executor.md", "executor-subprocess.md"):
            executor = (ROOT / "agents" / filename).read_text()
            self.assertIn("The coordinator owns git", executor)
            self.assertIn("MUST NOT run git commands", executor)
            self.assertIn("Verify", executor)
        hook = (ROOT / "hooks/scripts/stop-watcher.sh").read_text()
        self.assertIn("first pending numbered task in the full list", hook)
        self.assertIn("coordinator independently re-runs Verify", hook)
        self.assertNotIn("If taskIndex >= totalTasks: output ALL_TASKS_COMPLETE", hook)


if __name__ == "__main__":
    unittest.main()
