"""Run Haskell semantics and visible native Minecraft checks."""

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
    report = json.loads((run / "backrooms-report.json").read_text())
    built = json.loads((ROOT / "build/artifacts.json").read_text())
    for kind, path in (
        ("materialpack", run / "resourcepacks/backrooms-level0.zip"),
        ("datapack", run / "backrooms-datapack.zip"),
    ):
        if hashlib.sha256(path.read_bytes()).hexdigest() != built["artifacts"][kind]:
            raise RuntimeError(f"Loaded {kind} differs from the current build")
    report["build"] = built
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    log = (run / "logs/latest.log").read_text()
    gpu = re.search(r"Using graphics device: ([^\n]+)", log)
    report["graphics_device"] = gpu.group(1) if gpu else None
    shutil.copy2(run / "logs/latest.log", reports / "client.log")
    screenshots = []
    for directory in (run / "screenshots", run / "test-screenshots"):
        if directory.exists():
            shutil.copytree(directory, reports / "screenshots", dirs_exist_ok=True)
            screenshots += [
                "screenshots/" + p.name for p in sorted(directory.glob("*.png"))
            ]
    report["screenshots"] = screenshots
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
        ["cabal", "test", "--offline", "semantics", "--test-show-details=direct"],
        cwd=ROOT,
        check=True,
    )
    build()
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    stale = ROOT / "harness/build/run/clientGameTest/backrooms-report.json"
    stale.unlink(missing_ok=True)
    options = stale.parent / "options.txt"
    options.parent.mkdir(parents=True, exist_ok=True)
    lines = options.read_text().splitlines() if options.exists() else []
    settings = {
        "resourcePacks": '["vanilla"]',
        "enableVsync": "false",
        "fullscreen": "false",
        "preferredGraphicsBackend": '"vulkan"',
        "pauseOnLostFocus": "false",
        "inactivityFpsLimit": '"minimized"',
    }
    lines = [line for line in lines if line.split(":", 1)[0] not in settings]
    options.write_text(
        "\n".join(lines + [name + ":" + value for name, value in settings.items()])
        + "\n"
    )
    with (reports / "gradle.log").open("w") as output:
        result = subprocess.run(
            gradle_command("runClientGameTest"), stdout=output, stderr=subprocess.STDOUT
        )
    if stale.exists():
        passed = collect()
    else:
        passed = False
        print("\n".join((reports / "gradle.log").read_text().splitlines()[-60:]))
    return 0 if result.returncode == 0 and passed else 1


if __name__ == "__main__":
    sys.exit(main())
