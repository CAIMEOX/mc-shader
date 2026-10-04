"""Shared visible-client setup and playground locking."""

import fcntl
import json
import shutil
import subprocess
from contextlib import contextmanager

from scripts.common.gradle import gradle_command
from scripts.common.paths import ROOT


@contextmanager
def playground_session():
    directory = ROOT / "playground"
    directory.mkdir(exist_ok=True)
    (ROOT / "reports").mkdir(exist_ok=True)
    with (directory / ".launch.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for name in ["Signal Playground", "Signal Experiment"]:
                unlocked(directory / "saves" / name)
        except BlockingIOError:
            raise RuntimeError("A Signal client is already running") from None
        yield directory


def unlocked(world):
    path = world / "session.lock"
    if path.exists():
        with path.open("rb") as handle:
            fcntl.lockf(handle, fcntl.LOCK_SH | fcntl.LOCK_NB)
            fcntl.lockf(handle, fcntl.LOCK_UN)


def launch(task, logfile, options=()):
    with logfile.open("w") as log:
        result = subprocess.run(
            [*gradle_command(task), *options], stdout=log, stderr=subprocess.STDOUT
        )
    if result.returncode:
        print("\n".join(logfile.read_text().splitlines()[-60:]))
        raise RuntimeError(f"{task} failed; see {logfile}")


def prepare_world(world_name="Signal Experiment", setup_marker=None):
    directory = ROOT / "playground"
    world = directory / "saves" / world_name
    unlocked(world)
    if not (world / "level.dat").exists():
        source = ROOT / "harness/build/run/clientGameTest/saves/New World"
        if not (source / "level.dat").exists():
            launch("runClientGameTest", ROOT / "reports/world-setup.log")
            report = json.loads((source.parents[1] / "signal-world.json").read_text())
            if report["result"] != "passed":
                raise RuntimeError("World fixture did not complete")
        unlocked(source)
        world.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, world, ignore=shutil.ignore_patterns("session.lock"))
        if setup_marker is not None:
            (directory / setup_marker).touch()
    for source, destination in [
        (ROOT / "build/resourcepack.zip", directory / "resourcepacks/signal.zip"),
        (ROOT / "build/datapack.zip", world / "datapacks/signal.zip"),
    ]:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    options = directory / "options.txt"
    lines = options.read_text().splitlines() if options.exists() else []
    settings = {
        "resourcePacks": '["vanilla","file/signal.zip"]',
        "enableVsync": "false",
        "pauseOnLostFocus": "false",
        "inactivityFpsLimit": '"minimized"',
        "bobView": "false",
        "renderDistance": "3",
        "simulationDistance": "5",
        "maxFps": "120",
        "tutorialStep": "none",
    }
    options.write_text(
        "\n".join(
            [line for line in lines if line.split(":", 1)[0] not in settings]
            + [f"{key}:{value}" for key, value in settings.items()]
        )
        + "\n"
    )
    return directory
