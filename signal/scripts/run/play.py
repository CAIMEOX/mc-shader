"""Build and launch the visible ping-pong playground with normal keyboard and mouse."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import argparse
import hashlib
import json
import subprocess
import sys

from scripts.build.build import build, message_argument
from scripts.common.client import playground_session, prepare_world
from scripts.common.gradle import gradle_command
from scripts.common.paths import ROOT
from scripts.verify.reports import archive_previous


def collect_smoke(directory):
    status = json.loads((directory / "signal-play-status.json").read_text())
    if status["status"] != "passed" or not status["native_input"]:
        raise RuntimeError("Play smoke test failed: " + status.get("failure", ""))
    artifacts = json.loads((ROOT / "build/artifacts.json").read_text())
    for kind, path in [
        ("resourcepack", directory / "resourcepacks/signal.zip"),
        ("datapack", directory / "saves/Signal Playground/datapacks/signal.zip"),
    ]:
        if (
            hashlib.sha256(path.read_bytes()).hexdigest()
            != artifacts["artifacts"][kind]
        ):
            raise RuntimeError(f"Play client loaded a different {kind}")
    status["build"] = artifacts
    (ROOT / "reports/play.json").write_text(json.dumps(status, indent=2) + "\n")
    print("passed", ROOT / "reports/play.json")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--message", type=message_argument, default="hi from shader")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()
    with playground_session() as directory:
        archive_previous()
        build(ping_message=args.message)
        prepare_world("Signal Playground", ".setup-signal-play")
        if args.prepare_only:
            print(directory)
            return 0
        (directory / "signal-play-status.json").unlink(missing_ok=True)
        command = gradle_command("runPlayClient")
        if args.smoke:
            command.append("-PplaySmoke")
        print(
            "Opening Signal Playground · R receive · X cancel · OP enabled · 200 TPS",
            flush=True,
        )
        with (directory / "launcher.log").open("w") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            print(
                "\n".join((directory / "launcher.log").read_text().splitlines()[-60:])
            )
        if args.smoke and result.returncode == 0:
            collect_smoke(directory)
        return result.returncode


if __name__ == "__main__":
    sys.exit(main())
