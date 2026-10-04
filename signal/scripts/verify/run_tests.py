"""Verify the shader message channel in a visible Minecraft client."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import argparse
import sys

from scripts.build.build import build, message_argument
from scripts.common.client import launch, playground_session, prepare_world
from scripts.common.paths import ROOT
from scripts.verify.checks import check_semantics
from scripts.verify.ping_analysis import analyze_ping
from scripts.verify.reports import archive_previous, collect


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--message", type=message_argument, default="hi from shader")
    parser.add_argument("--collect", action="store_true")
    args = parser.parse_args()
    if args.collect:
        return 0 if collect(analyze_ping, "pingpong") else 1
    with playground_session():
        check_semantics()
        archive_previous()
        build(ping_message=args.message)
        directory = prepare_world()
        (directory / "signal-report.json").unlink(missing_ok=True)
        launch(
            "runProbeClient",
            ROOT / "reports/gradle.log",
            ["-PpingPong", "-PstopwatchOnly", "-PsignalPower=4"],
        )
        return 0 if collect(analyze_ping, "pingpong") else 1


if __name__ == "__main__":
    sys.exit(main())
