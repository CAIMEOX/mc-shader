"""Compile the pinned C forward implementation with the benchmark driver."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from pathlib import Path
import subprocess
import json
import os
import sys

from scripts.common.paths import ROOT
from scripts.common.gradle import executable_name


def build():
    config = json.loads(
        (ROOT / "build/model/weights.json").read_text(encoding="utf-8")
    )["config"]
    core = (
        (ROOT / "vendor/qwen3.c/runq.c")
        .read_text(encoding="utf-8")
        .replace("1e-6f", "QWEN_RMS_EPS")
        .replace("powf(1e6,", "powf(QWEN_ROPE_THETA,")
    )
    source = (
        "#define QWEN_RMS_EPS "
        + repr(config["rms_norm_eps"])
        + "f\n#define QWEN_ROPE_THETA "
        + repr(float(config["rope_theta"]))
        + "f\n"
        + "#define main qwen_upstream_main\n"
        + core
        + "\n#undef main\n"
        + Path(__file__).with_name("driver.c").read_text(encoding="utf-8")
    )
    out = ROOT / "build"
    out.mkdir(exist_ok=True)
    generated = out / "reference.c"
    generated.write_text(source, encoding="utf-8", newline="\n")
    binary = out / executable_name("qwen-reference")
    subprocess.run(
        [
            os.environ.get("CC", "cc"),
            "-O3",
            "-Wno-unknown-pragmas",
            "-I",
            str(ROOT / "vendor/qwen3.c"),
            str(generated),
            "-o",
            str(binary),
        ]
        + (["-lm"] if sys.platform != "darwin" else []),
        check=True,
    )
    return binary


if __name__ == "__main__":
    print(build())
