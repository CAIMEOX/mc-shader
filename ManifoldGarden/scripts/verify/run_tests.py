"""Build Manifold and run its visible native Minecraft tests."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
from scripts.build.build import build
from scripts.common.paths import ROOT
from scripts.common.gradle import gradle_command
from scripts.run.vanilla import write_bootstrap
from scripts.verify.tick_trace import summarize


def collect():
    run = ROOT / "harness/build/run/clientGameTest"
    report = json.loads((run / "manifold-report.json").read_text())
    build_info = json.loads((ROOT / "build/artifacts.json").read_text())
    for kind, loaded in [
        ("resourcepack-test", run / "resourcepacks/manifold.zip"),
        ("resourcepack", run / "resourcepacks/manifold-play.zip"),
        ("datapack", run / "manifold-datapack.zip"),
    ]:
        actual = hashlib.sha256(loaded.read_bytes()).hexdigest()
        if actual != build_info["artifacts"][kind]:
            raise RuntimeError(f"The loaded {kind} differs from the current build")
    report["build"] = build_info
    if report["suite"] in ("all", "entry", "rings", "joinery", "joinery-render"):
        expected = hashlib.sha256(
            (ROOT / "build/launcher.zip").read_bytes()
        ).hexdigest()
        actual = hashlib.sha256(
            (run / "manifold-launch-datapack.zip").read_bytes()
        ).hexdigest()
        if actual != expected:
            raise RuntimeError("The loaded launcher differs from the current build")
        report["launcher_sha256"] = actual
    log = (run / "logs/latest.log").read_text()
    gpu = re.search(r"Using graphics device: ([^\n]+)", log)
    report["graphics_device"] = gpu.group(1) if gpu else None
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    timings = {}
    for check in report["checks"]:
        if check["case"] not in ("runtime_timing", "room_build_timing"):
            continue
        phase = check.get("phase", "room_build")
        timings[phase] = {}
        for metric in (
            "tick_ms",
            "frame_ms",
            "frame_interval_ms",
            "build_ms",
            "entities",
            "proxies",
            "active_objects",
        ):
            values = sorted(
                sample[metric] for sample in check["samples"] if metric in sample
            )
            if values:
                timings[phase][metric] = {
                    "samples": len(values),
                    "median": statistics.median(values),
                    "p95": values[int(0.95 * (len(values) - 1))],
                    "maximum": max(values),
                }
        sample = check["samples"][0]
        if "width" in sample:
            timings[phase]["framebuffer"] = [sample["width"], sample["height"]]
    if timings:
        (reports / "performance.json").write_text(
            json.dumps(
                {
                    "build": build_info,
                    "measurement": "tick_ms measures native server ticks; build_ms measures synchronous room generation; frame_ms measures CPU render submission; frame_interval_ms includes rendering, presentation and the 60 FPS cap. Timings depend on the host and workload.",
                    "phases": timings,
                },
                indent=2,
            )
            + "\n"
        )
        report["runtime_metrics"] = "performance.json"
    shutil.copy2(run / "logs/latest.log", reports / "client.log")
    traces = sorted(run.glob("manifold-tick-*.txt"))
    if traces:
        (reports / "tick-traces").mkdir(exist_ok=True)
        for trace in traces:
            shutil.copy2(trace, reports / "tick-traces" / trace.name)
        report["tick_traces"] = ["tick-traces/" + trace.name for trace in traces]
        metrics = summarize(traces, reports, build_info)
        report["tick_metrics"] = "tick.json"
        for group, metric in (
            ("rings_idle", "runtime_commands"),
            ("rings_build", "command_entries"),
        ):
            names = [f"{group}_{size}" for size in (3, 30, 300)]
            if all(name in metrics["phases"] for name in names):
                counts = [metrics["phases"][name][metric] for name in names]
                passed = len(set(counts)) == 1
                report["checks"].append(
                    {
                        "case": group + "_scaling",
                        "metric": metric,
                        "counts": counts,
                        "passed": passed,
                    }
                )
                if not passed:
                    report["result"] = "failed"
                    report["failure"] = (
                        f"{group} workload changes with distant sleeping objects: {counts}"
                    )
    for directory in (run / "screenshots", run / "test-screenshots"):
        if directory.is_dir():
            shutil.copytree(directory, reports / "screenshots", dirs_exist_ok=True)
            current = {p.name for p in directory.glob("*.png")}
            for previous in (reports / "screenshots").glob(
                "[0-9][0-9][0-9][0-9]_manifold-*.png"
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
    parser.add_argument(
        "--suite",
        choices=(
            "all",
            "hybrid",
            "flight",
            "entry",
            "shader",
            "rings",
            "joinery",
            "joinery-render",
            "continuity",
            "rendering",
            "ui",
        ),
        default=os.environ.get("MANIFOLD_TEST_SUITE", "all"),
        help="Select native client checks (default: all)",
    )
    args = parser.parse_args()
    if args.collect:
        return 0 if collect() else 1
    subprocess.run(
        ["cabal", "test", "semantics", "--test-show-details=direct"]
        + (
            ["--test-options=joinery"]
            if args.suite in ("joinery", "joinery-render")
            else []
        ),
        cwd=ROOT,
        check=True,
    )
    build()
    bootstrap = ROOT / "build/launcher"
    write_bootstrap(
        bootstrap,
        "manifold:joinery/session"
        if args.suite in ("joinery", "joinery-render")
        else "manifold:three_rings/session"
        if args.suite == "rings"
        else "manifold:session/start",
    )
    shutil.make_archive(str(ROOT / "build/launcher"), "zip", bootstrap)
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    stale = ROOT / "harness/build/run/clientGameTest/manifold-report.json"
    stale.unlink(missing_ok=True)
    for trace in stale.parent.glob("manifold-tick-*.txt"):
        trace.unlink()
    with (reports / "gradle.log").open("w") as output:
        result = subprocess.run(
            gradle_command("runClientGameTest"),
            stdout=output,
            stderr=subprocess.STDOUT,
            env={**os.environ, "MANIFOLD_TEST_SUITE": args.suite},
        )
    if stale.exists():
        passed = collect()
    else:
        passed = False
        print("\n".join((reports / "gradle.log").read_text().splitlines()[-45:]))
    return 0 if result.returncode == 0 and passed else 1


if __name__ == "__main__":
    sys.exit(main())
