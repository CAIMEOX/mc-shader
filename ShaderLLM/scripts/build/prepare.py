"""Compile model assets with the Haskell exporter, reusing verified local assets."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import subprocess
import argparse
import json
from scripts.build.compile import compiler
from scripts.common.paths import ROOT
from scripts.build.build import build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Compile assets from the current model files",
    )
    args = parser.parse_args()
    executable = compiler()
    source_config = json.loads((ROOT / "model/config.json").read_text())
    manifest = ROOT / "build/model/weights.json"
    changed = not manifest.exists()
    if manifest.exists():
        compiled = json.loads(manifest.read_text())["config"]
        changed = any(
            source_config.get(key) != value for key, value in compiled.items()
        )
    for command, marker in [
        ("weights", "model/weights.json"),
        ("tokenizer", "tokenizer/tokenizer-layout.json"),
        ("fonts", "fonts/font-layout.json"),
    ]:
        if (
            args.force
            or (changed and command in ("weights", "tokenizer"))
            or not (ROOT / "build" / marker).exists()
        ):
            destination = ROOT / "build" / marker.split("/")[0]
            subprocess.run(
                [str(executable), command, str(ROOT / "model"), str(destination)],
                check=True,
            )
    chat = ROOT / "build/reference/chat.json"
    chat.parent.mkdir(parents=True, exist_ok=True)
    import jinja2

    config = json.loads((ROOT / "model/tokenizer_config.json").read_text())
    template = jinja2.Environment().from_string(config["chat_template"])
    marker = "QWEN_USER_INPUT"
    text = template.render(
        messages=[{"role": "user", "content": marker}],
        add_generation_prompt=True,
        enable_thinking=False,
    )
    prefix, suffix = text.split(marker)
    chat.write_text(
        json.dumps({"prefix": prefix, "suffix": suffix}, ensure_ascii=False) + "\n"
    )
    build()


if __name__ == "__main__":
    main()
