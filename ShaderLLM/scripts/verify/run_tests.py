"""Run visible Minecraft transport or inference checks on selected graphics backends."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile

from scripts.build.build import build
from scripts.build.transport import build as build_transport
from scripts.common.gradle import gradle_command
from scripts.common.paths import ROOT
from scripts.verify.reference.fixtures import main as prepare_reference
from scripts.verify.configuration import main as verify_configuration


def native_run(backend, transport_only):
    mode = "transport" if transport_only else "inference"
    label = f"{mode}-{backend or 'auto'}"
    reports = ROOT / "reports" / label
    reports.mkdir(parents=True, exist_ok=True)
    run = ROOT / "harness/build/run/clientGameTest"
    run.mkdir(parents=True, exist_ok=True)
    resultfile = run / "qwen-report.json"
    resultfile.unlink(missing_ok=True)
    options = run / "options.txt"
    lines = options.read_text(encoding="utf-8").splitlines() if options.exists() else []
    settings = {
        "enableVsync": "false",
        "pauseOnLostFocus": "false",
        "inactivityFpsLimit": '"minimized"',
    }
    options.write_text(
        "\n".join(
            [line for line in lines if line.split(":", 1)[0] not in settings]
            + [f"{key}:{value}" for key, value in settings.items()]
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )
    with (reports / "gradle.log").open("wb") as log:
        result = subprocess.run(
            gradle_command(
                "runClientGameTest", backend=backend, transport_only=transport_only
            ),
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    if resultfile.exists():
        report = json.loads(resultfile.read_text(encoding="utf-8"))
    else:
        report = {
            "result": "failed",
            "failure": "Minecraft exited without writing a test report",
        }
    report["requested_backend"] = backend or "auto"
    report["exit_code"] = result.returncode
    if result.returncode:
        report["result"] = "failed"
    if (
        backend
        and report.get("result") == "passed"
        and report.get("graphics_backend", "").lower() != backend
    ):
        report.update(
            result="failed",
            failure="Minecraft did not use the requested graphics backend",
        )
    metadata = {"artifacts": {}}
    if not transport_only:
        metadata.update(
            json.loads((ROOT / "model-source.json").read_text(encoding="utf-8"))
        )
        metadata["limits"] = json.loads(
            (ROOT / "build/pipeline/limits.json").read_text(encoding="utf-8")
        )
    for name, loaded, built in [
        (
            "resourcepack",
            run / "resourcepacks/qwen.zip",
            ROOT
            / "build"
            / ("transport-resourcepack.zip" if transport_only else "resourcepack.zip"),
        ),
        ("datapack", run / "qwen-datapack.zip", ROOT / "build/datapack.zip"),
    ]:
        if loaded.exists():
            with zipfile.ZipFile(loaded) as a, zipfile.ZipFile(built) as b:
                if {
                    n: (a.getinfo(n).CRC, a.getinfo(n).file_size) for n in a.namelist()
                } != {
                    n: (b.getinfo(n).CRC, b.getinfo(n).file_size) for n in b.namelist()
                }:
                    report.update(
                        result="failed",
                        failure=f"Loaded {name} differs from the current build",
                    )
            with loaded.open("rb") as stream:
                metadata["artifacts"][name] = hashlib.file_digest(
                    stream, "sha256"
                ).hexdigest()
    report.update(build=metadata, minecraft="26.3", framebuffer=[1280, 720])
    (reports / "native.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    for name in ("screenshots", "test-screenshots"):
        if (run / name).exists():
            shutil.copytree(run / name, reports / "screenshots", dirs_exist_ok=True)
    if (run / "logs/latest.log").exists():
        shutil.copy2(run / "logs/latest.log", reports / "client.log")
    print(
        f"{label}: {report['result']} ({len(report.get('checks', []))} checks)",
        flush=True,
    )
    if report["result"] != "passed":
        print(report.get("failure", "See the Minecraft log"), flush=True)
        print(
            "\n".join(
                (reports / "gradle.log")
                .read_text(encoding="utf-8", errors="replace")
                .splitlines()[-40:]
            )
        )
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument(
        "--transport-only",
        action="store_true",
        help="Verify pixel requests without model weights",
    )
    parser.add_argument(
        "--backend",
        choices=("opengl", "vulkan", "both"),
        help="Select graphics backends; default uses Minecraft's choice",
    )
    args = parser.parse_args()
    subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", "scripts/tests"],
        cwd=ROOT,
        check=True,
    )
    subprocess.run(
        [
            "cabal",
            "test",
            "shader-semantics",
            "resource-encoding",
            "--test-show-details=direct",
        ],
        cwd=ROOT,
        check=True,
    )
    if not args.skip_build:
        (build_transport if args.transport_only else build)()
    if not args.transport_only:
        verify_configuration()
        prepare_reference()
    backends = ("opengl", "vulkan") if args.backend == "both" else (args.backend,)
    reports = [native_run(backend, args.transport_only) for backend in backends]
    passed = all(report["result"] == "passed" for report in reports)
    if not args.transport_only:
        summary = dict(reports[-1])
        summary["result"] = "passed" if passed else "failed"
        summary["backend_runs"] = [
            {
                key: report.get(key)
                for key in ("requested_backend", "graphics_backend", "result")
            }
            for report in reports
        ]
        (ROOT / "reports/native.json").write_text(
            json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
