"""Compile the pinned C forward implementation with the benchmark driver."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from pathlib import Path
import subprocess
import json

from scripts.common.paths import ROOT


def build():
    config = json.loads((ROOT / "build/model/weights.json").read_text())["config"]
    core = (
        (ROOT / "vendor/qwen3.c/runq.c")
        .read_text()
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
        + Path(__file__).with_name("driver.c").read_text()
    )
    out = ROOT / "build"
    out.mkdir(exist_ok=True)
    generated = out / "reference.c"
    generated.write_text(source)
    binary = out / "qwen-reference"
    subprocess.run(
        ["cc", "-O3", "-Wno-unknown-pragmas", str(generated), "-o", str(binary)],
        check=True,
    )
    return binary


if __name__ == "__main__":
    print(build())
