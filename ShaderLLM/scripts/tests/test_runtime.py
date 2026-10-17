"""Check runtime selection through its command interface."""

import os
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts.common import gradle


class JavaSelectionTest(unittest.TestCase):
    def test_java_home_selects_the_runtime(self):
        with TemporaryDirectory(prefix="qwen java 中文 ") as directory:
            root = Path(directory)
            java = root / "bin" / ("java.exe" if os.name == "nt" else "java")
            java.parent.mkdir()
            java.touch()
            probe = SimpleNamespace(
                returncode=0,
                stdout="",
                stderr=f"    java.home = {root}\n    java.specification.version = 25\n",
            )
            with (
                patch.dict(os.environ, {"JAVA_HOME": str(root)}),
                patch("subprocess.run", return_value=probe),
            ):
                command = gradle.gradle_command("help")
            self.assertEqual(Path(command[0]), java)
            self.assertIn(f"-Dorg.gradle.java.home={root}", command)

    def test_path_fallback(self):
        probe = SimpleNamespace(
            returncode=0,
            stdout="",
            stderr="java.home = /runtime\njava.specification.version = 25\n",
        )
        with (
            patch.dict(os.environ, {}, clear=True),
            patch.object(gradle.shutil, "which", return_value="/runtime/bin/java"),
            patch("subprocess.run", return_value=probe),
        ):
            java, home = gradle.java_runtime()
        self.assertEqual(java, Path("/runtime/bin/java"))
        self.assertEqual(home, Path("/runtime"))

    def test_unsupported_java_version(self):
        probe = SimpleNamespace(
            returncode=0,
            stdout="",
            stderr="java.home = /runtime\njava.specification.version = 17\n",
        )
        with (
            patch.dict(os.environ, {}, clear=True),
            patch.object(gradle.shutil, "which", return_value="/runtime/bin/java"),
            patch("subprocess.run", return_value=probe),
        ):
            with self.assertRaises(RuntimeError):
                gradle.java_runtime()

    def test_custom_gradle_cache(self):
        with TemporaryDirectory() as directory:
            home = Path(directory)
            jar = home / "caches/fabric-loom/26.3/minecraft-client.jar"
            jar.parent.mkdir(parents=True)
            jar.touch()
            with patch.dict(os.environ, {"GRADLE_USER_HOME": str(home)}, clear=True):
                self.assertEqual(gradle.minecraft_client(), jar)


if __name__ == "__main__":
    unittest.main()
