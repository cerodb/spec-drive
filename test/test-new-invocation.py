"""Local shell integration and conversational-contract checks; no model calls."""
import json
import os
from pathlib import Path
import re
import shutil
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
        self.work = Path(self.tmp.name) / "workspace with spaces"
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

    def test_conversational_contract_before_scaffold(self):
        recovery = DOC.index("## Recover Input and Resolve Local Identity")
        self.assertLess(recovery, DOC.index("## Resolve Projects Container"))
        for phrase in ("ask one concise question", "Retain the information already given",
                       "Never turn an arbitrary description into an invented slug",
                       "naming and project-identity conventions", "ask before writing",
                       "Do not silently", "scaffold's validation"):
            self.assertIn(phrase, DOC)


if __name__ == "__main__":
    unittest.main()
