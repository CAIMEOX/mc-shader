"""Run the visible Minecraft shader benchmark and collect native evidence."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pathlib import Path
import json
import hashlib
import zipfile
import shutil
import subprocess
import sys
from scripts.build.build import build
from scripts.common.paths import ROOT


from scripts.common.gradle import gradle_command
from scripts.verify.reference.fixtures import main as prepare_reference
from scripts.verify.configuration import main as verify_configuration


def main():
    subprocess.run(
        ["cabal", "test", "shader-semantics", "--test-show-details=direct"],
        cwd=ROOT,
        check=True,
    )
    if "--skip-build" not in sys.argv:
        build()
    verify_configuration()
    prepare_reference()
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    run = ROOT / "harness/build/run/clientGameTest"
    resultfile = run / "qwen-report.json"
    resultfile.unlink(missing_ok=True)
    run.mkdir(parents=True, exist_ok=True)
    options = run / "options.txt"
    lines = options.read_text().splitlines() if options.exists() else []
    settings = {
        "enableVsync": "false",
        "pauseOnLostFocus": "false",
        "inactivityFpsLimit": '"minimized"',
    }
    options.write_text(
        "\n".join(
            [line for line in lines if line.split(":", 1)[0] not in settings]
            + [k + ":" + v for k, v in settings.items()]
        )
        + "\n"
    )
    with (reports / "gradle.log").open("w") as log:
        result = subprocess.run(
            gradle_command("runClientGameTest"), stdout=log, stderr=subprocess.STDOUT
        )
    if resultfile.exists():
        report = json.loads(resultfile.read_text())
        metadata = json.loads((ROOT / "model-source.json").read_text())
        metadata["limits"] = json.loads(
            (ROOT / "build/pipeline/limits.json").read_text()
        )
        metadata["artifacts"] = {}
        for name, loaded in [
            ("resourcepack", run / "resourcepacks/qwen.zip"),
            ("datapack", run / "qwen-datapack.zip"),
        ]:
            with (
                zipfile.ZipFile(loaded) as a,
                zipfile.ZipFile(ROOT / f"build/{name}.zip") as b,
            ):
                if {
                    n: (a.getinfo(n).CRC, a.getinfo(n).file_size) for n in a.namelist()
                } != {
                    n: (b.getinfo(n).CRC, b.getinfo(n).file_size) for n in b.namelist()
                }:
                    raise RuntimeError(
                        "Loaded artifact differs from the current build: " + name
                    )
            metadata["artifacts"][name] = hashlib.sha256(
                loaded.read_bytes()
            ).hexdigest()
        report["build"] = metadata
        report["minecraft"] = "26.3"
        report["framebuffer"] = [1280, 720]
        (reports / "native.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        )
        print(report, flush=True)
        for name in ("screenshots", "test-screenshots"):
            if (run / name).exists():
                shutil.copytree(run / name, reports / "screenshots", dirs_exist_ok=True)
        shutil.copy2(run / "logs/latest.log", reports / "client.log")
    else:
        print("\n".join((reports / "gradle.log").read_text().splitlines()[-60:]))
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
