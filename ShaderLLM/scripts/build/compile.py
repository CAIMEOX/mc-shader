"""Build the Haskell resource compiler through the pinned Cabal project."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import shutil
import subprocess

from scripts.common.paths import ROOT


def compiler():
    out = ROOT / "build"
    out.mkdir(exist_ok=True)
    cabal = shutil.which("cabal")
    if not cabal:
        raise RuntimeError("GHC and Cabal are required")
    binary = out / "qwen-codegen"
    subprocess.run(
        [
            cabal,
            "build",
            "exe:qwen-codegen",
        ],
        cwd=ROOT,
        check=True,
    )
    compiled = subprocess.check_output(
        [cabal, "list-bin", "exe:qwen-codegen"], cwd=ROOT, text=True
    ).strip()
    shutil.copy2(compiled, binary)
    return binary


if __name__ == "__main__":
    subprocess.run(
        [str(compiler()), "weights", str(ROOT / "model"), str(ROOT / "build/model")],
        check=True,
    )
