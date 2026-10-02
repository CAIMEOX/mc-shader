"""Create tokenizer and C numerical fixtures for raw NBT string prompts."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from pathlib import Path
import json
import struct
import subprocess
import sys
import jinja2
from tokenizers import Tokenizer

from scripts.common.paths import ROOT


def main():
    from scripts.verify.reference.build import build

    binary = build()
    tokenizer = Tokenizer.from_file(str(ROOT / "model/tokenizer.json"))
    config = json.loads((ROOT / "model/tokenizer_config.json").read_text())
    template = jinja2.Environment().from_string(config["chat_template"])
    render = lambda content: template.render(
        messages=[{"role": "user", "content": content}],
        add_generation_prompt=True,
        enable_thinking=False,
    )
    marker = "QWEN_USER_INPUT"
    prefix, suffix = render(marker).split(marker)
    output = ROOT / "build/reference"
    output.mkdir(exist_ok=True)
    (output / "chat.json").write_text(
        json.dumps({"prefix": prefix, "suffix": suffix}, ensure_ascii=False, indent=2)
        + "\n"
    )
    cases = [
        "What is 2 + 2? Answer briefly.",
        "用中文回答：一加一等于几？",
        "Hello, 123!\nWhat's café?",
        "Cafe\u0301 and 각",
        "Print ONLY numbers 1 to 100 separated by commas. Start immediately with 1.",
    ]
    manifest = []
    for i, prompt in enumerate(cases):
        ids = tokenizer.encode(render(prompt), add_special_tokens=False).ids
        path = output / f"prompt-{i}.bin"
        path.write_bytes(
            struct.pack("<i", len(ids)) + struct.pack("<" + "i" * len(ids), *ids)
        )
        record = {"name": f"prompt-{i}", "prompt": prompt, "token_ids": ids}
        if i < 2 or i == 4:
            result = output / f"result-{i}.json"
            subprocess.run(
                [
                    str(binary),
                    str(ROOT / "build/model/reference.bin"),
                    str(path),
                    "40" if i == 4 else "8",
                    str(result),
                ],
                check=True,
            )
            value = json.loads(result.read_text())
            record["reference"] = value
            record["decoded"] = tokenizer.decode(
                value["generated"], skip_special_tokens=True
            )
            print(i, record["decoded"], value, flush=True)
        manifest.append(record)
    (output / "fixtures.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    )


if __name__ == "__main__":
    main()
