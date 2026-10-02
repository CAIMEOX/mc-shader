"""Build Flame and run its visible native Minecraft tests."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys

from scripts.build.build import build
from scripts.common.gradle import gradle_command
from scripts.common.paths import ROOT


def collect():
    run = ROOT / "harness/build/run/clientGameTest"
    report = json.loads((run / "flame-report.json").read_text())
    build_info = json.loads((ROOT / "build/artifacts.json").read_text())
    for kind, loaded in [
        ("resourcepack", run / "resourcepacks/flame.zip"),
        ("datapack", run / "flame-datapack.zip"),
    ]:
        actual = hashlib.sha256(loaded.read_bytes()).hexdigest()
        if actual != build_info["artifacts"][kind]:
            raise RuntimeError(f"The loaded {kind} differs from the current build")
    report["build"] = build_info
    log = (run / "logs/latest.log").read_text()
    gpu = re.search(r"Using graphics device: ([^\n]+)", log)
    report["graphics_device"] = gpu.group(1) if gpu else None
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    shutil.copy2(run / "logs/latest.log", reports / "client.log")
    for directory in (run / "screenshots", run / "test-screenshots"):
        if directory.is_dir():
            shutil.copytree(directory, reports / "screenshots", dirs_exist_ok=True)
            current = {p.name for p in directory.glob("*.png")}
            for previous in (reports / "screenshots").glob(
                "[0-9][0-9][0-9][0-9]_flame-*.png"
            ):
                if previous.name not in current:
                    previous.unlink()
            report["screenshots"] = ["screenshots/" + name for name in sorted(current)]
    (reports / "native.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    )
    print(report["result"], reports / "native.json")
    return report["result"] == "passed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--collect", action="store_true")
    args = parser.parse_args()
    if args.collect:
        return 0 if collect() else 1
    subprocess.run(
        ["cabal", "test", "semantics", "--test-show-details=direct"],
        cwd=ROOT,
        check=True,
    )
    build()
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    stale = ROOT / "harness/build/run/clientGameTest/flame-report.json"
    stale.unlink(missing_ok=True)
    with (reports / "gradle.log").open("w") as output:
        result = subprocess.run(
            gradle_command("runClientGameTest"), stdout=output, stderr=subprocess.STDOUT
        )
    if stale.exists():
        passed = collect()
    else:
        passed = False
        print("\n".join((reports / "gradle.log").read_text().splitlines()[-45:]))
    return 0 if result.returncode == 0 and passed else 1


if __name__ == "__main__":
    sys.exit(main())
