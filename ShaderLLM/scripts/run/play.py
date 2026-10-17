"""Launch the visible Qwen shader playground with normal keyboard and mouse."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pathlib import Path
import argparse
from contextlib import ExitStack
import json
import shutil
import subprocess
from scripts.common.paths import ROOT
from scripts.common.gradle import gradle_command
from scripts.common.locking import file_lock


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", choices=("opengl", "vulkan"))
    args = parser.parse_args()
    report = ROOT / "reports/native.json"
    if args.backend:
        report = ROOT / "reports" / f"inference-{args.backend}" / "native.json"
    if (
        not report.exists()
        or json.loads(report.read_text(encoding="utf-8"))["result"] != "passed"
    ):
        raise RuntimeError("Run python3 scripts/verify/run_tests.py successfully first")
    directory = ROOT / "playground"
    directory.mkdir(exist_ok=True)
    with file_lock(directory / ".launch.lock", create=True):
        world = directory / "saves/Qwen Playground"
        with ExitStack() as locks:
            if (world / "session.lock").exists():
                locks.enter_context(file_lock(world / "session.lock", shared=True))
            if not (world / "level.dat").exists():
                source = ROOT / "harness/build/run/clientGameTest/saves/New World"
                with file_lock(source / "session.lock", shared=True):
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
        lines = (
            options.read_text(encoding="utf-8").splitlines() if options.exists() else []
        )
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
            + "\n",
            encoding="utf-8",
            newline="\n",
        )
        print("Qwen Playground · R submits the NBT prompt", flush=True)
        with (directory / "launcher.log").open(
            "w", encoding="utf-8", newline="\n"
        ) as log:
            result = subprocess.run(
                gradle_command("runPlayClient", backend=args.backend),
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        if result.returncode:
            print(
                "\n".join(
                    (directory / "launcher.log")
                    .read_text(encoding="utf-8")
                    .splitlines()[-40:]
                )
            )
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
