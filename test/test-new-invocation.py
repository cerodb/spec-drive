"""Local shell integration and conversational-contract checks; no model calls."""
import json
import hashlib
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DOC = (ROOT / "commands/new.md").read_text()
RESOLVER = ROOT / "hooks/scripts/resolve-config.sh"
BASH = shutil.which("bash")


class NewInvocation(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="spec-drive-new-")
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name).resolve() / "workspace with spaces"
        self.work.mkdir()
        self.config = self.work / ".spec-drive-config.json"
        self.config.write_text(json.dumps({"projectRoot": "./projects with spaces"}))
        self.env = dict(os.environ, SPEC_DRIVE_PLUGIN_ROOT=str(ROOT),
                        XDG_CONFIG_HOME=str(self.work / "empty-xdg"))

    def validate(self, prefix="", env=None):
        return subprocess.run([BASH, "-c", '. "$1"; ' + prefix +
                               'spec_drive_validate_config_file "$2"',
                               "probe", str(RESOLVER), str(self.config)],
                              env=env or self.env, capture_output=True, text=True)

    def invocation(self, shell):
        section = DOC.split("## Resolve Projects Container", 1)[1]
        block = re.search(r"```bash\n(.*?)```", section, re.S)[1]
        return subprocess.run([shell, "-c", block + '\nprintf "%s" "$PROJECTS_CONTAINER"'],
                              cwd=self.work, env=self.env, capture_output=True, text=True)

    def test_documented_invocation(self):
        for shell in (BASH, "/bin/sh"):
            result = self.invocation(shell)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, str((self.work / "projects with spaces").resolve()))

    @unittest.skipUnless(shutil.which("zsh"), "zsh not installed; no portability claim")
    def test_documented_invocation_from_zsh(self):
        result = self.invocation(shutil.which("zsh"))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_config_stops_documented_invocation(self):
        self.config.write_text("{bad")
        result = self.invocation(BASH)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid JSON", result.stderr)

    def test_diagnostics(self):
        self.assertEqual(self.validate().returncode, 0)
        result = self.validate('PATH="/nonexistent-spec-drive-test"; ')
        self.assertEqual(result.returncode, 3)
        self.assertIn("jq is required but unavailable", result.stderr)
        self.assertNotIn("invalid JSON", result.stderr)
        result = self.validate('jq() { return 127; }; ')
        self.assertIn("environment/I/O error", result.stderr)
        self.assertNotIn("invalid JSON", result.stderr)
        self.config.unlink()
        self.assertIn("cannot read file", self.validate().stderr)

    def test_non_bash_source_rejected(self):
        env = dict(self.env)
        env.pop("BASH_VERSION", None)
        # /bin/sh is Bash on macOS. Select an actual non-Bash interpreter,
        # preferring the reported zsh environment, without installing anything.
        shell = next((shutil.which(name) for name in ("zsh", "dash")
                      if shutil.which(name)), None)
        if shell is None:
            self.skipTest("no zsh or dash available for non-Bash source test")
        args = [shell, "-f"] if Path(shell).name == "zsh" else [shell]
        result = subprocess.run(args + ["-c", '. "$1"', "probe", str(RESOLVER)],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 3)
        self.assertIn("requires Bash", result.stderr)

    def test_unsafe_slug_creates_nothing(self):
        before = sorted(self.work.iterdir())
        result = subprocess.run([BASH, str(ROOT / "hooks/scripts/create-project.sh"),
                                 "--projects-container", str(self.work),
                                 "--project-slug", "whole description as name",
                                 "--goal", "fixture", "--mode", "normal",
                                 "--research-depth", "standard"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 64)
        self.assertEqual(sorted(self.work.iterdir()), before)

    def test_documented_scaffold_preserves_full_identity(self):
        section = DOC.split("## Delegate Project Scaffold", 1)[1]
        block = re.search(r"```bash\n(.*?)```", section, re.S)[1]
        slug = "pg999-fixture"
        env = dict(self.env, PROJECTS_CONTAINER=str(self.work / "projects with spaces"),
                   name=slug, goal="fixture goal", mode="normal", researchDepth="standard",
                   GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
        result = subprocess.run([BASH, "-c", block], cwd=self.work, env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        project = self.work / "projects with spaces" / slug
        for relative in (".spec-drive-config.json", "spec/idea.md",
                         "spec/.spec-drive-state.json", "spec/.progress.md"):
            self.assertIn(slug, (project / relative).read_text())
        self.assertTrue((project / ".git").is_dir())

    def scaffold(self, plugin_root=None):
        block = re.search(r"```bash\n(.*?)```", DOC.split(
            "## Delegate Project Scaffold", 1)[1], re.S)[1]
        env = dict(self.env, PROJECTS_CONTAINER=str(self.work), name="fixture",
                   goal="known goal", mode="auto", researchDepth="deep",
                   GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
        if plugin_root:
            env["SPEC_DRIVE_PLUGIN_ROOT"] = str(plugin_root)
        return subprocess.run([BASH, "-c", block +
                               '\nprintf "%s|%s|%s" "$OUTCOME" "$NEW_ACTION" "$NEXT_COMMAND"'],
                              cwd=self.work, env=env, capture_output=True, text=True)

    def snapshot(self):
        result = {}
        for p in self.work.rglob("*"):
            info = p.lstat()
            kind = stat.S_IFMT(info.st_mode)
            if p.is_symlink():
                value = os.readlink(p)
            elif p.is_file():
                data = p.read_bytes()
                value = (data, hashlib.sha256(data).hexdigest(), info.st_mtime_ns)
            else:
                value = None
            result[str(p.relative_to(self.work))] = (kind, value)
        return result

    def registrar(self, structured=True, env=None):
        args = [BASH, str(ROOT / "hooks/scripts/create-project.sh"),
                "--projects-container", str(self.work), "--project-slug", "fixture",
                "--goal", "PRIVATE fixture goal", "--mode", "normal",
                "--research-depth", "standard"]
        if structured:
            args += ["--result-format", "json"]
        return subprocess.run(args, cwd=self.work, env=env or self.env,
                              capture_output=True, text=True)

    def assert_conflict_twice(self, code, path):
        before = self.snapshot()
        for _ in range(2):
            result = self.registrar()
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(json.loads(result.stdout), {
                "path": str(self.work / "fixture"), "outcome": "conflict",
                "error": {"code": code, "path": path}})
            self.assertNotIn("PRIVATE", result.stdout + result.stderr)
            self.assertEqual(before, self.snapshot())

    def test_additional_filesystem_conflicts(self):
        project = self.work / "fixture"
        cases = (("spec", "file", "wrong-path-type"),
                 (".spec-drive-config.json", "directory", "wrong-path-type"),
                 ("spec/.spec-drive-state.json", "directory", "wrong-path-type"),
                 ("spec/.progress.md", "link", "wrong-path-type"),
                 (".git", "file", "git-root-mismatch"),
                 (".git", "link", "wrong-path-type"),
                 ("spec/idea.md", "identity", "identity-mismatch"),
                 ("spec/.progress.md", "identity", "identity-mismatch"))
        for relative, kind, code in cases:
            with self.subTest(path=relative, kind=kind):
                project.mkdir()
                target = project / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if kind == "directory":
                    target.mkdir()
                elif kind == "link":
                    target.symlink_to(project / "absent")
                else:
                    target.write_text('---\nspec: "other"\n---\nPRIVATE content\n'
                                      if kind == "identity" else "PRIVATE invalid content")
                self.assert_conflict_twice(code, relative)
                shutil.rmtree(project)

    def test_legacy_output_and_repeated_refusal(self):
        result = self.registrar(structured=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(self.work / "fixture") + "\n")
        before = self.snapshot()
        for _ in range(2):
            result = self.registrar(structured=False)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")
            self.assertEqual(before, self.snapshot())

    def test_concurrent_artifact_creation_at_exclusive_link(self):
        project = self.work / "fixture"
        (project / "spec").mkdir(parents=True)
        target = project / ".spec-drive-config.json"
        # Interpose only the actual publication subprocess. The real script
        # still performs classification, staging, os.link and cleanup.
        shim = self.work / "bin"
        shim.mkdir()
        python = shutil.which("python3")
        wrapper = shim / "python3"
        marker = '{"scope":"project","projectSlug":"other"}\n'
        wrapper.write_text("#!" + python + "\nimport os, sys\n"
                           + "target = " + repr(str(target)) + "\n"
                           + "if len(sys.argv) == 4 and sys.argv[3] == target:\n"
                           + "    with open(target, 'x') as stream:\n"
                           + "        stream.write(" + repr(marker) + ")\n"
                           + "os.execv(" + repr(python) + ", ["
                           + repr(python) + "] + sys.argv[1:])\n")
        wrapper.chmod(0o755)
        before = self.snapshot()
        result = self.registrar(env=dict(self.env, PATH=str(shim) + os.pathsep + os.environ["PATH"]))
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(json.loads(result.stdout)["error"],
                         {"code": "concurrent-change", "path": ".spec-drive-config.json"})
        self.assertEqual(target.read_text(), marker)
        after = self.snapshot()
        del after["fixture/.spec-drive-config.json"]
        self.assertEqual(before, after)
        self.assert_conflict_twice("identity-mismatch", ".spec-drive-config.json")

    def test_created_and_resumable_are_distinct(self):
        result = self.scaffold()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "created|research|/spec-drive:research")
        before = self.snapshot()
        result = self.scaffold()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "resumable|route|/spec-drive:research")
        self.assertEqual(before, self.snapshot())

    def test_adopted_initial_research(self):
        project = self.work / "fixture"
        project.mkdir()
        (project / "spec").mkdir()
        (project / "assets").mkdir()
        for relative, content in {
            "README.md": "PRIVATE existing README\n",
            "assets/source.bin": "\x00PRIVATE asset\xff",
            ".spec-drive-config.json": '{ "scope": "project", "projectSlug": "fixture" }\n',
            "spec/idea.md": '---\nspec: "fixture"\nphase: idea\n---\nPRIVATE custom vision\n',
            "spec/.progress.md": '---\nspec: "fixture"\nphase: idea\n---\nPRIVATE custom learnings\n',
        }.items():
            (project / relative).write_text(content)
        def git(*args):
            return subprocess.run(["git", "-C", str(project), *args], env=dict(
                self.env, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null"),
                check=True, capture_output=True, text=True).stdout
        git("init", "-q")
        git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "commit", "--allow-empty", "-qm", "Existing history")
        history = tuple(git(*args) for args in (("rev-parse", "HEAD"),
                        ("log", "--format=%H"), ("rev-parse", "--show-toplevel")))
        before = self.snapshot()
        result = self.scaffold()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "adopted|research|/spec-drive:research")
        after = self.snapshot()
        self.assertEqual(before, {key: after[key] for key in before})
        self.assertEqual(set(after) - set(before), {"fixture/spec/.spec-drive-state.json"})
        state = json.loads((project / "spec/.spec-drive-state.json").read_text())
        self.assertEqual((state["phase"], state["awaitingApproval"]), ("research", False))
        for _ in range(2):
            result = self.registrar()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {"path": str(project),
                             "outcome": "resumable", "phase": "research"})
            self.assertEqual(after, self.snapshot())
            self.assertEqual(history, tuple(git(*args) for args in (("rev-parse", "HEAD"),
                             ("log", "--format=%H"), ("rev-parse", "--show-toplevel"))))

    def test_adopted_background_research_is_preserved(self):
        spec = self.work / "fixture/spec"
        spec.mkdir(parents=True)
        research = spec / "research.md"
        research.write_text("Unapproved background research")
        before = (research.read_bytes(), research.stat().st_mtime_ns)
        result = self.scaffold()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn(str(research), result.stderr)
        self.assertIn("output-path conflict", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(before, (research.read_bytes(), research.stat().st_mtime_ns))

    def test_resumable_phase_and_approval_routes_without_writes(self):
        self.assertEqual(self.scaffold().returncode, 0)
        spec = self.work / "fixture/spec"
        state_path = spec / ".spec-drive-state.json"
        state = json.loads(state_path.read_text())
        for phase, command in (("idea", "research"), ("research", "research"),
                               ("requirements", "design"), ("design", "tasks"),
                               ("tasks", "implement"), ("execution", "implement"),
                               ("completed", "")):
            for approval in (False, True, None):
                with self.subTest(phase=phase, approval=approval):
                    state["phase"] = phase
                    state["awaitingApproval"] = approval
                    if approval is None:
                        del state["awaitingApproval"]
                    state_path.write_text(json.dumps(state))
                    for artifact in ("research", "requirements", "design", "tasks"):
                        (spec / (artifact + ".md")).write_text("existing work")
                    before = self.snapshot()
                    result = self.scaffold()
                    self.assertEqual(result.returncode, 0, result.stderr)
                    next_command = "requirements" if phase == "research" and approval else command
                    expected = ("resumable|report|" if phase == "completed" else
                                "resumable|route|/spec-drive:" + next_command)
                    self.assertEqual(result.stdout, expected)
                    self.assertEqual(before, self.snapshot())

    def test_conflict_reports_structured_code_and_path_without_writes(self):
        project = self.work / "fixture"
        project.mkdir()
        config = project / ".spec-drive-config.json"
        config.write_text("invalid JSON")
        before = self.snapshot()
        result = self.scaffold()
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalid-config", result.stderr)
        self.assertIn(str(config), result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(before, self.snapshot())

    def test_routing_conversational_contract(self):
        for phrase in ("awaiting human review", "not approved", "There is no idea command",
                       "never write state or automatically delegate any phase",
                       "even with `--auto`", "Reuse its unambiguous vision",
                       "Only `NEW_ACTION=research` continues", "existing gate/checklist"):
            self.assertIn(phrase, DOC)

    def fake_scaffold(self, output, status=0):
        root = self.work / "fake-plugin"
        script = root / "hooks/scripts/create-project.sh"
        script.parent.mkdir(parents=True, exist_ok=True)
        script.write_text("cat <<'RESULT'\n" + output + "\nRESULT\nexit " + str(status))
        return root

    def scaffold_block_bytes(self, plugin_root):
        block = re.search(r"```bash\n(.*?)```", DOC.split(
            "## Delegate Project Scaffold", 1)[1], re.S)[1]
        env = dict(self.env, PROJECTS_CONTAINER=str(self.work), name="fixture",
                   goal="known goal", mode="normal", researchDepth="standard",
                   SPEC_DRIVE_PLUGIN_ROOT=str(plugin_root))
        return subprocess.run([BASH, "-c", block], cwd=self.work, env=env,
                              capture_output=True)

    def test_invalid_result_contract_stops(self):
        for output, status in (("/legacy/path", 0), ("{}", 0),
                               ('{"path":"/tmp/x","outcome":"created"}', 2),
                               ('{"path":"/tmp/x","outcome":"resumable"}', 0),
                               ('{"path":"/tmp/x","outcome":"conflict"}', 2)):
            with self.subTest(output=output, status=status):
                result = self.scaffold(self.fake_scaffold(output, status))
                self.assertEqual(result.returncode, 1)
                self.assertIn("Invalid ScaffoldResult", result.stderr)
                self.assertEqual(result.stdout, "")

    def test_real_scaffold_block_preserves_nonzero_status_and_stderr_bytes(self):
        root = self.work / "byte-failure-plugin"
        script = root / "hooks/scripts/create-project.sh"
        script.parent.mkdir(parents=True)
        marker = b"scaffold-error:\xff\x00tail\n"
        script.write_bytes(b"#!/usr/bin/env bash\nprintf 'scaffold-error:\\377\\000tail\\n' >&2\nexit 9\n")
        script.chmod(0o755)
        result = self.scaffold_block_bytes(root)
        self.assertEqual(result.returncode, 9)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, marker)

    def test_guided_resolution_can_resume_without_reinitializing(self):
        created = self.scaffold()
        self.assertEqual(created.returncode, 0, created.stderr)
        self.assertEqual(created.stdout, "created|research|/spec-drive:research")
        project_prefix = "fixture/"
        before = {key: value for key, value in self.snapshot().items()
                  if key == "fixture" or key.startswith(project_prefix)}

        root = self.work / "resolved-plugin"
        script = root / "hooks/scripts/create-project.sh"
        script.parent.mkdir(parents=True)
        script.write_text("printf 'needs inspection\\n' >&2\nexit 7\n")
        first = self.scaffold_block_bytes(root)
        self.assertEqual(first.returncode, 7)
        self.assertEqual(first.stderr, b"needs inspection\n")
        after_failure = {key: value for key, value in self.snapshot().items()
                         if key == "fixture" or key.startswith(project_prefix)}
        self.assertEqual(before, after_failure)

        # Simulate the agent's already-authorized, inspected correction solely
        # inside the plugin fixture. This is a guided shell simulation, not an
        # end-to-end model assertion.
        real = ROOT / "hooks/scripts/create-project.sh"
        spaced_real = root / "inspected scaffold with spaces.sh"
        spaced_real.write_text("#!/usr/bin/env bash\nexec " +
                               shlex.quote(str(real)) + " \"$@\"\n")
        spaced_real.chmod(0o755)
        script.write_text("#!/usr/bin/env bash\nexec " +
                          shlex.quote(str(spaced_real)) + " \"$@\"\n")
        script.chmod(0o755)
        second = self.scaffold(root)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(second.stdout, "resumable|route|/spec-drive:research")
        after_resume = {key: value for key, value in self.snapshot().items()
                        if key == "fixture" or key.startswith(project_prefix)}
        self.assertEqual(before, after_resume)

    def test_adopted_later_state_never_restarts_research(self):
        self.assertEqual(self.scaffold().returncode, 0)
        project = self.work / "fixture"
        state_path = project / "spec/.spec-drive-state.json"
        state = json.loads(state_path.read_text())
        state.update(phase="design", awaitingApproval=True)
        state_path.write_text(json.dumps(state))
        (project / "spec/design.md").write_text("existing design")
        # Defensive routing contract: the current registrar normally emits
        # resumable for a coherent later phase, not adopted.
        root = self.fake_scaffold(json.dumps({"path": str(project), "outcome": "adopted"}))
        before = self.snapshot()
        result = self.scaffold(root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "adopted|route|/spec-drive:tasks")
        self.assertEqual(before, self.snapshot())

    def test_conversational_contract_before_scaffold(self):
        recovery = DOC.index("## Recover Input and Resolve Local Identity")
        self.assertLess(recovery, DOC.index("## Resolve Projects Container"))
        for phrase in ("ask one concise question", "Retain the information already given",
                       "Never turn an arbitrary description into an invented slug",
                       "naming and project-identity conventions", "ask before writing",
                       "Do not silently", "scaffold's validation"):
            self.assertIn(phrase, DOC)

    def test_common_agent_recovery_contract_and_all_incoming_edges(self):
        recovery = DOC.split("## Agent Recovery", 1)[1].split(
            "## Resolve Projects Container", 1)[0]
        recovery_text = " ".join(recovery.split())
        for phrase in ("stop filesystem mutations and dependent dispatches",
                       "real non-zero status", "all diagnostics and structured results still available",
                       "never invent stdout", "Preserve captured bytes exactly",
                       "safe, unequivocal, already-authorized correction",
                       "ask exactly one concise question",
                       "recommended safe action", "reread the actual state",
                       "Do not reinitialize", "blindly repeat",
                       "keep the decision pending",
                       "do not ask it again without new evidence",
                       "evidence that the cause was resolved",
                       "explicit decision authorizing a supervised retry",
                       "Never enter a retry loop"):
            self.assertIn(phrase, recovery_text)
        for edge in ("resolver failures", "non-zero scaffold exit",
                     "invalid `ScaffoldResult`", "structured scaffold conflict",
                     "state changed since the result", "existing `research.md`",
                     "researcher failure"):
            self.assertIn(edge, recovery_text)
        self.assertIn("uncertain partial work", recovery_text)
        self.assertIn("Human escalation is only for a real unresolved decision", recovery_text)


if __name__ == "__main__":
    unittest.main()
