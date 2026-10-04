"""Format Python, Haskell, Java, GLSL, and JSON project sources."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path

from scripts.common.paths import ROOT


def executable(name, variable):
    candidate = os.environ.get(variable, name)
    resolved = shutil.which(candidate)
    if not resolved:
        raise RuntimeError(f"Install {name} or set {variable} to its executable")
    return resolved


def format_json(path, check):
    source = path.read_text(encoding="utf-8")
    formatted = json.dumps(json.loads(source), indent=2, ensure_ascii=False) + "\n"
    if source == formatted:
        return True
    if check:
        print(f"{path}: JSON formatting required")
        return False
    path.write_text(formatted, encoding="utf-8")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    ruff = executable("ruff", "SIGNAL_RUFF")
    ormolu = executable("ormolu", "SIGNAL_ORMOLU")
    clang = executable("clang-format", "SIGNAL_CLANG_FORMAT")
    python = sorted((ROOT / "scripts").rglob("*.py"))
    haskell = sorted((ROOT / "codegen").rglob("*.hs"))
    native = sorted((ROOT / "harness/src").rglob("*.java"))
    native += sorted(
        p
        for p in (ROOT / "shaders").rglob("*")
        if p.suffix in {".glsl", ".fsh", ".vsh", ".inc"}
    )
    commands = [
        [ruff, "check", *([] if args.check else ["--fix"]), *map(str, python)],
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
    resources = sorted((ROOT / "harness/src").rglob("*.json"))
    valid = [format_json(path, args.check) for path in resources]
    if not all(valid):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
