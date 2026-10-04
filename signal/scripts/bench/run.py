"""Run shader timing measurements in a visible client with native scheduling."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import argparse
import sys

from scripts.bench.analyze import analyze
from scripts.build.build import build
from scripts.common.client import launch, playground_session, prepare_world
from scripts.common.paths import ROOT
from scripts.verify.checks import check_semantics
from scripts.verify.reports import archive_previous, collect


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--collect", action="store_true")
    parser.add_argument("--rates", type=int, nargs="+")
    parser.add_argument("--payload-start", type=int, default=1000)
    parser.add_argument("--stopwatch-only", action="store_true")
    parser.add_argument("--power", type=int)
    parser.add_argument("--water", action="store_true")
    parser.add_argument("--water-speed", action="store_true")
    parser.add_argument("--water-four", action="store_true")
    parser.add_argument("--rotate", action="store_true")
    parser.add_argument("--fall", action="store_true")
    parser.add_argument("--rotate-stream", action="store_true")
    parser.add_argument("--stream-stage", choices=["full", "controls"], default="full")
    parser.add_argument("--rotate-stage", choices=["probe", "full"], default="full")
    parser.add_argument("--rotate-powers", type=int, nargs="+")
    parser.add_argument("--rotate-activities", action="store_true")
    parser.add_argument("--rotate-fps", action="store_true")
    parser.add_argument("--levels", type=int, nargs=4, default=[0, 20, 32, 48])
    parser.add_argument("--guard-ms", type=int, default=50)
    parser.add_argument("--window-ms", type=int, choices=[300, 400, 500])
    parser.add_argument(
        "--speed-cases", choices=["all", "stable", "continuous", "scan"], default="all"
    )
    parser.add_argument("--skip-scan", action="store_true")
    args = parser.parse_args()
    if args.stream_stage != "full" and not args.rotate_stream:
        parser.error("--stream-stage selects rotation stream checks")
    if sum(
        [args.water_speed, args.water_four, args.rotate, args.fall, args.rotate_stream]
    ) > 1 or ((args.rotate or args.fall or args.rotate_stream) and args.water):
        parser.error("Select one receiver experiment")
    if args.water_four and (args.window_ms is not None or args.speed_cases != "all"):
        parser.error("--window-ms and --speed-cases select short binary trials")
    if args.water_speed or args.water_four:
        args.water = True
    args.rates = args.rates or (
        [200]
        if args.water_speed or args.water_four or args.fall or args.rotate_stream
        else [20, 200]
        if args.water or args.rotate
        else [200, 500, 1000, 2000]
    )
    if args.fall or args.rotate_stream:
        args.stopwatch_only = True
        if args.rates != [200]:
            parser.error("Frame-stream experiments use 200 TPS")
    if args.water or args.rotate:
        args.stopwatch_only = True
        if args.power is None:
            args.power = 32
    if (
        args.stopwatch_only
        and args.power is None
        and not (args.fall or args.rotate_stream)
    ):
        parser.error("--stopwatch-only requires --power to keep the workload fixed")
    if args.power is not None and not 0 <= args.power <= 63:
        parser.error("--power must be in 0..63")
    if args.rotate_powers and (
        any(power < 1 or power > 63 for power in args.rotate_powers)
        or len(set(args.rotate_powers)) != len(args.rotate_powers)
    ):
        parser.error("--rotate-powers requires distinct values in 1..63")
    if not 0 <= args.guard_ms <= 1000:
        parser.error("--guard-ms must be in 0..1000")
    if not all(0 <= power <= 63 for power in args.levels) or any(
        a >= b for a, b in zip(args.levels, args.levels[1:])
    ):
        parser.error("--levels requires four increasing powers in 0..63")
    if args.collect:
        return 0 if collect(analyze) else 1
    with playground_session():
        check_semantics()
        archive_previous()
        build(
            args.payload_start,
            args.rates,
            args.levels,
            ping_message=None,
            fall_seed=args.payload_start if args.fall else None,
            rotate_stream_seed=args.payload_start if args.rotate_stream else None,
        )
        (ROOT / "reports").mkdir(exist_ok=True)
        directory = prepare_world()
        (directory / "signal-report.json").unlink(missing_ok=True)
        options = ["-PstopwatchOnly"] if args.stopwatch_only else []
        if args.fall:
            options.append("-Pfall")
        if args.rotate_stream:
            options.extend(["-ProtateStream", f"-PstreamStage={args.stream_stage}"])
            if args.rotate_activities:
                options.append("-ProtateActivities")
        if args.water:
            options.append("-Pwater")
        if args.rotate:
            options.extend(["-Protate", f"-ProtateStage={args.rotate_stage}"])
            if args.rotate_powers:
                options.append(
                    "-ProtatePowers=" + ",".join(map(str, args.rotate_powers))
                )
            if args.rotate_activities:
                options.append("-ProtateActivities")
            if args.rotate_fps:
                options.append("-ProtateFps")
        if args.water_speed:
            options.extend(
                [
                    "-PwaterSpeed",
                    f"-PguardMs={args.guard_ms}",
                    f"-PspeedCases={args.speed_cases}",
                ]
            )
            if args.window_ms is not None:
                options.append(f"-PwindowMs={args.window_ms}")
            if args.skip_scan:
                options.append("-PskipScan=true")
        if args.water_four:
            options.extend(["-PwaterFour", f"-PguardMs={args.guard_ms}"])
        if args.power is not None:
            options.append(f"-PsignalPower={args.power}")
        launch("runProbeClient", ROOT / "reports/gradle.log", options)
        return 0 if collect(analyze) else 1


if __name__ == "__main__":
    sys.exit(main())
