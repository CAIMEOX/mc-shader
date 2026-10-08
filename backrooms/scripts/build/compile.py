"""Compile the Haskell resource generator."""

import os
import shutil
import subprocess
from pathlib import Path

from scripts.common.paths import ROOT


def compiler():
    cabal = shutil.which("cabal")
    if not cabal:
        raise RuntimeError("GHC and Cabal are required to build Backrooms")
    local = ROOT / "cabal.project.local"
    if not local.exists():
        configured = os.environ.get("BACKROOMS_PACKAGE_DB")
        version = subprocess.check_output(
            ["ghc", "--numeric-version"], text=True
        ).strip()
        candidates = sorted(
            (Path.home() / ".cabal/store").glob(f"ghc-{version}*/package.db")
        )
        database = (
            Path(configured)
            if configured
            else candidates[0]
            if len(candidates) == 1
            else None
        )
        if database is not None:
            local.write_text("package-dbs: " + str(database) + "\n")
    subprocess.run(
        [cabal, "build", "--offline", "exe:backrooms-codegen"], cwd=ROOT, check=True
    )
    return Path(
        subprocess.check_output(
            [cabal, "list-bin", "exe:backrooms-codegen"], cwd=ROOT, text=True
        ).strip()
    )
