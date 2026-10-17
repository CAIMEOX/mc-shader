"""Exercise process-level exclusion and shared world locks."""

from contextlib import contextmanager
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

from scripts.common.locking import file_lock
from scripts.common.paths import ROOT


@contextmanager
def owner(path, shared):
    source = """
import sys
from pathlib import Path
from scripts.common.locking import file_lock
with file_lock(Path(sys.argv[1]), shared=sys.argv[2] == 'shared'):
    print('locked', flush=True)
    sys.stdin.readline()
"""
    child = subprocess.Popen(
        [sys.executable, "-c", source, str(path), "shared" if shared else "exclusive"],
        cwd=ROOT,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    try:
        if child.stdout.readline().strip() != "locked":
            raise AssertionError(child.stderr.read())
        yield
        child.communicate("\n", timeout=10)
        if child.returncode:
            raise AssertionError(f"Lock owner exited with {child.returncode}")
    finally:
        if child.poll() is None:
            child.kill()
        child.communicate()


class LockingTest(unittest.TestCase):
    def test_exclusive_owner_blocks_other_processes(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "session.lock"
            path.write_bytes("☃".encode("utf-8"))
            with owner(path, shared=False):
                with self.assertRaises(RuntimeError):
                    with file_lock(path, shared=True):
                        pass
            with file_lock(path):
                pass

    def test_shared_owners_allow_readers_and_exclude_writers(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "session.lock"
            path.write_bytes(b"lock")
            with owner(path, shared=True):
                with file_lock(path, shared=True):
                    pass
                with self.assertRaises(RuntimeError):
                    with file_lock(path):
                        pass


if __name__ == "__main__":
    unittest.main()
