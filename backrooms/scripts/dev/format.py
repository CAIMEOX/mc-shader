"""Format sources with Ruff, Ormolu and clang-format."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import argparse
import os
import shutil
import subprocess

from scripts.common.paths import ROOT


def tool(name, variable):
    resolved = shutil.which(os.environ.get(variable, name))
    if not resolved:
        raise RuntimeError(f"Install {name} or set {variable}")
    return resolved


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    ruff = tool("ruff", "BACKROOMS_RUFF")
    ormolu = tool("ormolu", "BACKROOMS_ORMOLU")
    clang = tool("clang-format", "BACKROOMS_CLANG_FORMAT")
    python = sorted((ROOT / "scripts").rglob("*.py"))
    haskell = sorted((ROOT / "codegen").rglob("*.hs"))
    native = sorted((ROOT / "harness/src").rglob("*.java")) + sorted(
        p
        for p in (ROOT / "shaders").rglob("*")
        if p.suffix in {".glsl", ".fsh", ".vsh", ".inc"}
    )
    commands = [
        [
            ruff,
            "check",
            "--select",
            "I",
            *([] if args.check else ["--fix"]),
            *map(str, python),
        ],
        [ruff, "format", *(["--check"] if args.check else []), *map(str, python)],
    ]
    commands += [
        [
            ormolu,
            "--mode",
            "check" if args.check else "inplace",
            "--ghc-opt",
            "-XGHC2021",
            str(p),
        ]
        for p in haskell
    ]
    commands += [
        [
            clang,
            "--style=file",
            *(["--dry-run", "--Werror"] if args.check else ["-i"]),
            *map(str, native),
        ]
    ]
    for command in commands:
        subprocess.run(command, cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
