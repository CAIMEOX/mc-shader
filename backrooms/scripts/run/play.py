"""Open the Backrooms playground with native keyboard and mouse controls."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import argparse
import fcntl
import hashlib
import json
import shutil
import subprocess
import sys
import uuid
from datetime import datetime, timezone

from scripts.build.build import build
from scripts.common.gradle import gradle_command
from scripts.common.paths import ROOT

WORLD = "Backrooms Level 0"


def locked(world):
    path = world / "session.lock"
    if not path.exists():
        return False
    with path.open("rb") as stream:
        try:
            fcntl.lockf(stream, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.lockf(stream, fcntl.LOCK_UN)
    return False


def prepare():
    directory = ROOT / "playground"
    world = directory / "saves" / WORLD
    directory.mkdir(exist_ok=True)
    if locked(world):
        raise RuntimeError("The Backrooms playground is already open")
    built = json.loads((ROOT / "build/artifacts.json").read_text())
    if not preview_current(world, built):
        report = json.loads((ROOT / "reports/native.json").read_text())
        if (
            report["result"] != "passed"
            or report.get("mode") != "WorldGen"
            or report.get("architecture") != "runtime density partitions"
            or report.get("palette") != "level0"
            or report.get("layout_profile") != "runtime_level0"
            or report["build"] != built
        ):
            raise RuntimeError("The current packs need a passing native verification")
        source = ROOT / "harness/build/run/clientGameTest/saves/New World"
        if locked(source):
            raise RuntimeError("The native test world is still running")
        refresh_preview(world, source, built)
    target = world / "datapacks/backrooms.zip"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "build/datapack.zip", target)
    target = directory / "resourcepacks/backrooms-level0.zip"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "build/materialpack.zip", target)
    options = directory / "options.txt"
    lines = options.read_text().splitlines() if options.exists() else []
    settings = {
        "resourcePacks": '["vanilla","file/backrooms-level0.zip"]',
        "bobView": "false",
        "renderDistance": "5",
        "maxFps": "120",
        "pauseOnLostFocus": "false",
        "inactivityFpsLimit": '"minimized"',
        "soundCategory_music": "0.0",
        "textBackgroundOpacity": "0.0",
        "enableVsync": "false",
        "preferredGraphicsBackend": '"vulkan"',
    }
    lines = [line for line in lines if line.split(":", 1)[0] not in settings]
    options.write_text(
        "\n".join(lines + [name + ":" + value for name, value in settings.items()])
        + "\n"
    )
    return directory


def preview_current(world, built):
    stamp = world / ".backrooms-preview.json"
    return (
        (world / "level.dat").exists()
        and stamp.exists()
        and json.loads(stamp.read_text()).get("datapack")
        == built["artifacts"]["datapack"]
    )


def refresh_preview(world, source, built):
    if not (source / "level.dat").exists():
        raise RuntimeError("The verified native preview world is required")
    world.parent.mkdir(parents=True, exist_ok=True)
    stage = world.parent / (".backrooms-preview-" + uuid.uuid4().hex)
    backup = None
    try:
        shutil.copytree(source, stage, ignore=shutil.ignore_patterns("session.lock"))
        (stage / ".backrooms-preview.json").write_text(
            json.dumps(
                {
                    "datapack": built["artifacts"]["datapack"],
                    "layout_profile": "runtime_level0",
                },
                indent=2,
            )
            + "\n"
        )
        if world.exists():
            timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            backup = (
                ROOT
                / "playground/backups"
                / (world.name + "_" + timestamp + "_" + uuid.uuid4().hex[:8])
            )
            backup.parent.mkdir(parents=True, exist_ok=True)
            world.rename(backup)
        stage.rename(world)
    except Exception:
        if backup is not None and backup.exists() and not world.exists():
            backup.rename(world)
        if stage.exists():
            shutil.rmtree(stage)
        raise
    if backup is not None:
        print("Previous preview saved:", backup, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    directory = ROOT / "playground"
    directory.mkdir(exist_ok=True)
    with (directory / ".launch.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("A Backrooms play client is already running")
        report = ROOT / "reports/native.json"
        observed = json.loads(report.read_text()) if report.exists() else {}
        if not (ROOT / "build/artifacts.json").exists():
            build()
        built = json.loads((ROOT / "build/artifacts.json").read_text())
        fixture = ROOT / "harness/build/run/clientGameTest/saves/New World/level.dat"
        if (
            observed.get("result") != "passed"
            or observed.get("mode") != "WorldGen"
            or observed.get("architecture") != "runtime density partitions"
            or observed.get("palette") != "level0"
            or observed.get("layout_profile") != "runtime_level0"
            or observed.get("build") != built
            or (
                not preview_current(directory / "saves" / WORLD, built)
                and not fixture.exists()
            )
        ):
            subprocess.run(
                [sys.executable, str(ROOT / "scripts/verify/run_tests.py")], check=True
            )
        directory = prepare()
        if args.prepare_only:
            print(directory)
            return 0
        command = gradle_command("runPlayClient")
        if args.smoke:
            command.append("-PplaySmoke")
        status = directory / "backrooms-play-status.json"
        status.unlink(missing_ok=True)
        print(
            "Opening Backrooms Level 0: WASD walk · F7 entrance · X exit",
            flush=True,
        )
        with (directory / "launcher.log").open("w") as output:
            result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            print(
                "\n".join((directory / "launcher.log").read_text().splitlines()[-55:])
            )
        if args.smoke and result.returncode == 0:
            observed = json.loads(status.read_text())
            if observed["status"] != "passed":
                raise RuntimeError(
                    observed.get("failure", "Play control verification failed")
                )
            built = json.loads((ROOT / "build/artifacts.json").read_text())
            for kind, target in (
                ("datapack", directory / "saves" / WORLD / "datapacks/backrooms.zip"),
                ("materialpack", directory / "resourcepacks/backrooms-level0.zip"),
            ):
                if (
                    hashlib.sha256(target.read_bytes()).hexdigest()
                    != built["artifacts"][kind]
                ):
                    raise RuntimeError("Play client uses a different pack build")
            observed["build"] = built
            (ROOT / "reports/play.json").write_text(
                json.dumps(observed, ensure_ascii=False, indent=2) + "\n"
            )
            print("passed", ROOT / "reports/play.json")
        return result.returncode


if __name__ == "__main__":
    sys.exit(main())
