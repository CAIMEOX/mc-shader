"""Collect and preserve native reports with their matching pack hashes."""

import hashlib
import json
import re
import shutil

from scripts.common.paths import ROOT


def collect(analyze, experiment=None):
    run = ROOT / "playground"
    report = json.loads((run / "signal-report.json").read_text())
    if experiment is not None and report.get("experiment") != experiment:
        raise RuntimeError(f"Expected a {experiment} report")
    if report.get("native_scheduling") is not True:
        raise RuntimeError(
            "Timing measurements require native client/server scheduling"
        )
    build_info = json.loads((ROOT / "build/artifacts.json").read_text())
    for kind, loaded in [
        ("resourcepack", run / "resourcepacks/signal.zip"),
        ("datapack", run / "saves/Signal Experiment/datapacks/signal.zip"),
    ]:
        if (
            hashlib.sha256(loaded.read_bytes()).hexdigest()
            != build_info["artifacts"][kind]
        ):
            raise RuntimeError(f"The loaded {kind} differs from the current build")
    report["build"] = build_info
    log = (run / "logs/latest.log").read_text()
    gpu = re.search(r"Using graphics device: ([^\n]+)", log)
    report["graphics_device"] = gpu.group(1) if gpu else None
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    shutil.copy2(run / "logs/latest.log", reports / "client.log")
    if (run / "screenshots").exists():
        shutil.copytree(
            run / "screenshots", reports / "screenshots", dirs_exist_ok=True
        )
    (reports / "native.json").write_text(json.dumps(report, indent=2) + "\n")
    analyze(report, reports)
    print(report["result"], reports / "native.json")
    return report["result"] == "passed"


def archive_previous():
    reports = ROOT / "reports"
    report = reports / "native.json"
    if not report.exists():
        return
    previous = json.loads(report.read_text())
    key = hashlib.sha256(report.read_bytes()).hexdigest()[:16]
    destination = reports / "runs" / key
    destination.mkdir(parents=True, exist_ok=True)
    for name in [
        "native.json",
        "summary.json",
        "samples.csv",
        "client.log",
        "gradle.log",
    ]:
        source = reports / name
        if source.exists() and not (destination / name).exists():
            shutil.copy2(source, destination / name)
    for kind, digest in previous.get("build", {}).get("artifacts", {}).items():
        source = ROOT / "build" / f"{kind}.zip"
        if (
            source.exists()
            and hashlib.sha256(source.read_bytes()).hexdigest() == digest
        ):
            shutil.copy2(source, destination / source.name)
