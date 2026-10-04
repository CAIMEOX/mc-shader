"""Launch the Escher playground with normal keyboard, mouse and presentation."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pathlib import Path
import argparse
import fcntl
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from scripts.build.build import build
from scripts.common.paths import ROOT
from scripts.common.gradle import gradle_command

WORLD_NAME = "Escher Gallery"


def locked(world):
    lock = world / "session.lock"
    if not lock.exists():
        return False
    with lock.open("rb") as stream:
        try:
            fcntl.lockf(stream, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.lockf(stream, fcntl.LOCK_UN)
    return False


def prepare():
    directory = ROOT / "playground"
    directory.mkdir(exist_ok=True)
    world = directory / "saves" / WORLD_NAME
    if locked(world):
        raise RuntimeError("Escher Gallery is already open")
    if not (world / "level.dat").exists():
        report = ROOT / "reports/native.json"
        source = ROOT / "harness/build/run/clientGameTest/saves/New World"
        if not report.exists():
            raise RuntimeError(
                "Run python3 scripts/verify/run_tests.py successfully before creating the gallery"
            )
        validated = json.loads(report.read_text())
        build_info = json.loads((ROOT / "build/artifacts.json").read_text())
        if (
            validated["result"] != "passed"
            or validated.get("renderer") != "analytic gallery"
            or validated["build"] != build_info
        ):
            raise RuntimeError("The current gallery build needs a passing visible test")
        if locked(source):
            raise RuntimeError("The native test is still using its world")
        original = hashlib.sha256((source / "level.dat").read_bytes()).digest()
        world.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=world.parent) as temporary:
            staged = Path(temporary) / "world"
            shutil.copytree(
                source, staged, ignore=shutil.ignore_patterns("session.lock")
            )
            if (
                locked(source)
                or hashlib.sha256((source / "level.dat").read_bytes()).digest()
                != original
            ):
                raise RuntimeError("The native test world changed during copying")
            staged.rename(world)
        (directory / ".setup-stage").touch()
    for source, destination in [
        (ROOT / "build/resourcepack.zip", directory / "resourcepacks/escher.zip"),
        (ROOT / "build/datapack.zip", world / "datapacks/escher.zip"),
    ]:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    options = directory / "options.txt"
    lines = options.read_text().splitlines() if options.exists() else []
    replacements = {
        "resourcePacks": '["vanilla","file/escher.zip"]',
        "bobView": "false",
        "renderDistance": "5",
        "maxFps": "120",
        "pauseOnLostFocus": "false",
        "inactivityFpsLimit": '"minimized"',
    }
    lines = [line for line in lines if line.split(":", 1)[0] not in replacements]
    options.write_text(
        "\n".join(lines + [key + ":" + value for key, value in replacements.items()])
        + "\n"
    )
    return directory


def collect_smoke(directory):
    status = json.loads((directory / "escher-play-status.json").read_text())
    if status["status"] != "passed" or status["nativeInput"] is not True:
        raise RuntimeError(
            "The interactive control smoke test failed: " + status.get("failure", "")
        )
    artifacts = json.loads((ROOT / "build/artifacts.json").read_text())
    for kind, path in [
        ("resourcepack", directory / "resourcepacks/escher.zip"),
        ("datapack", directory / "saves" / WORLD_NAME / "datapacks/escher.zip"),
    ]:
        if (
            hashlib.sha256(path.read_bytes()).hexdigest()
            != artifacts["artifacts"][kind]
        ):
            raise RuntimeError(f"The play client loaded a different {kind}")
    status["build"] = artifacts
    status["controls"] = [
        "collision_world",
        "scene_view",
        "shape",
        "quality_low",
        "quality_high",
    ]
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    (reports / "play.json").write_text(
        json.dumps(status, ensure_ascii=False, indent=2) + "\n"
    )
    print("passed", reports / "play.json")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--scene", choices=("gallery", "folding"))
    args = parser.parse_args()
    directory = ROOT / "playground"
    directory.mkdir(exist_ok=True)
    with (directory / ".launch.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("A Escher play client is already running")
        report = ROOT / "reports/native.json"
        fixture = ROOT / "harness/build/run/clientGameTest/saves/New World/level.dat"
        existing = directory / "saves" / WORLD_NAME / "level.dat"
        validated = (
            report.exists()
            and json.loads(report.read_text()).get("result") == "passed"
            and json.loads(report.read_text()).get("renderer") == "analytic gallery"
        )
        if not existing.exists() and (not fixture.exists() or not validated):
            subprocess.run(
                [sys.executable, str(ROOT / "scripts/verify/run_tests.py")], check=True
            )
        elif not all(
            (ROOT / "build" / name).exists()
            for name in ("datapack.zip", "resourcepack.zip", "artifacts.json")
        ):
            build()
        directory = prepare()
        if args.prepare_only:
            print(directory)
            return 0
        command = gradle_command("runPlayClient")
        if args.smoke:
            command.append("-PplaySmoke")
        if args.scene:
            command.append("-PplayScene=" + args.scene)
        (directory / "escher-play-status.json").unlink(missing_ok=True)
        print(
            "Opening Escher: WASD walk · R shape · X collision view · F7 entrance · F6 rebuild",
            flush=True,
        )
        with (directory / "launcher.log").open("w") as output:
            result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            print(
                "\n".join((directory / "launcher.log").read_text().splitlines()[-50:])
            )
        if args.smoke and result.returncode == 0:
            collect_smoke(directory)
        return result.returncode


if __name__ == "__main__":
    sys.exit(main())
