"""Run the Haskell and Python semantic suites."""

import subprocess
import sys

from scripts.common.paths import ROOT


def check_semantics():
    subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", "scripts", "-t", "."],
        cwd=ROOT,
        check=True,
    )
    subprocess.run(
        ["cabal", "test", "semantics", "--test-show-details=direct"],
        cwd=ROOT,
        check=True,
    )
