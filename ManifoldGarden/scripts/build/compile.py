"""Build the Haskell resource compiler through Cabal."""

import shutil
import subprocess
from pathlib import Path

from scripts.common.paths import ROOT


def compiler():
    cabal = shutil.which("cabal")
    if not cabal:
        raise RuntimeError("GHC and Cabal are required to build Manifold")
    subprocess.run([cabal, "build", "exe:manifold-codegen"], cwd=ROOT, check=True)
    return Path(
        subprocess.check_output(
            [cabal, "list-bin", "exe:manifold-codegen"], cwd=ROOT, text=True
        ).strip()
    )
