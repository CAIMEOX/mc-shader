"""Launch the visible Qwen shader playground with normal keyboard and mouse."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pathlib import Path
import fcntl
import json
import shutil
import subprocess
from scripts.common.paths import ROOT
from scripts.common.gradle import gradle_command


def main():
    report = ROOT / "reports/native.json"
    if not report.exists() or json.loads(report.read_text())["result"] != "passed":
        raise RuntimeError("Run python3 scripts/verify/run_tests.py successfully first")
    directory = ROOT / "playground"
    directory.mkdir(exist_ok=True)
    with (directory / ".launch.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        world = directory / "saves/Qwen Playground"
        if (world / "session.lock").exists():
            with (world / "session.lock").open("rb") as session:
                fcntl.lockf(session, fcntl.LOCK_SH | fcntl.LOCK_NB)
                fcntl.lockf(session, fcntl.LOCK_UN)
        if not (world / "level.dat").exists():
            source = ROOT / "harness/build/run/clientGameTest/saves/New World"
            with (source / "session.lock").open("rb") as session:
                fcntl.lockf(session, fcntl.LOCK_SH | fcntl.LOCK_NB)
                fcntl.lockf(session, fcntl.LOCK_UN)
            shutil.copytree(
                source, world, ignore=shutil.ignore_patterns("session.lock")
            )
            (directory / ".setup").touch()
        for source, dest in [
            (ROOT / "build/resourcepack.zip", directory / "resourcepacks/qwen.zip"),
            (ROOT / "build/datapack.zip", world / "datapacks/qwen.zip"),
        ]:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
        options = directory / "options.txt"
        lines = options.read_text().splitlines() if options.exists() else []
        settings = {
            "resourcePacks": '["vanilla","file/qwen.zip"]',
            "enableVsync": "false",
            "pauseOnLostFocus": "false",
            "inactivityFpsLimit": '"minimized"',
            "renderDistance": "5",
            "maxFps": "120",
        }
        options.write_text(
            "\n".join(
                [l for l in lines if l.split(":", 1)[0] not in settings]
                + [k + ":" + v for k, v in settings.items()]
            )
            + "\n"
        )
        print("Qwen Playground · R submits the NBT prompt", flush=True)
        with (directory / "launcher.log").open("w") as log:
            result = subprocess.run(
                gradle_command("runPlayClient"), stdout=log, stderr=subprocess.STDOUT
            )
        if result.returncode:
            print(
                "\n".join((directory / "launcher.log").read_text().splitlines()[-40:])
            )
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
