"""Use only disposable local repositories, with no network."""
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/tag_version.py"


class TagVersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / "remote.git"
        self.repo = self.root / "repo"
        self.git("init", "--bare", str(self.remote), cwd=self.root)
        self.git("init", "-b", "main", str(self.repo), cwd=self.root)
        self.git("config", "user.name", "Example")
        self.git("config", "user.email", "example@example.invalid")
        self.git("remote", "add", "origin", str(self.remote))
        self.commit = self.new_commit()

    def git(self, *args, cwd=None):
        return subprocess.check_output(
            ["git", "-c", "core.fsmonitor=false", *args],
            cwd=cwd or self.repo, text=True, stderr=subprocess.DEVNULL,
        ).strip()

    def new_commit(self):
        self.git("commit", "--allow-empty", "-m", "test: example")
        self.git("push", "origin", "main")
        return self.git("rev-parse", "HEAD")

    def release(self, commit=None, cwd=None):
        return subprocess.check_output(
            ["python3", str(SCRIPT), commit or self.commit],
            cwd=cwd or self.repo, text=True, stderr=subprocess.DEVNULL,
        )

    def tags(self):
        return self.git("ls-remote", "--tags", "origin")

    def test_first_release_and_retry(self):
        self.release()
        self.assertEqual(self.tags(), f"{self.commit}\trefs/tags/v0.1.0")
        self.assertIn("Already released", self.release())

    def test_numeric_latest_and_annotated_tags(self):
        self.git("tag", "v1.2.9")
        self.git("tag", "-a", "v1.2.10", "-m", "example")
        self.git("tag", "v9.0.0-beta")
        self.git("push", "origin", "--tags")
        self.commit = self.new_commit()
        self.release()
        self.assertIn(f"{self.commit}\trefs/tags/v1.2.11", self.tags())

    def test_superseded_commit_is_not_tagged(self):
        self.new_commit()
        self.assertIn("Skipping", self.release())
        self.assertEqual(self.tags(), "")

    def test_shallow_checkout_fetches_remote_tags(self):
        self.git("tag", "v0.1.5")
        self.git("push", "origin", "--tags")
        self.commit = self.new_commit()
        shallow = self.root / "shallow"
        self.git("clone", "--depth=1", "--no-tags", "--branch", "main",
                 self.remote.as_uri(), str(shallow), cwd=self.root)
        self.release(cwd=shallow)
        self.assertIn(f"{self.commit}\trefs/tags/v0.1.6", self.tags())


if __name__ == "__main__":
    unittest.main()
