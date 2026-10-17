"""Build a pixel-transport resource pack with the production font and decoder."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import json
import shutil
import subprocess
from scripts.build.compile import compiler
from scripts.build.resources import archive, install_wire, write_pack_metadata
from scripts.common.paths import ROOT


def build():
    executable = compiler()
    out = ROOT / "build"
    for command, target in [("wire", out / "fonts"), ("datapack", out / "datapack")]:
        subprocess.run([str(executable), command, str(target)], check=True)
    pack = out / "transport-pack"
    if pack.exists():
        shutil.rmtree(pack)
    shaders = pack / "assets/qwen/shaders"
    (shaders / "include").mkdir(parents=True)
    effects = pack / "assets/minecraft/post_effect"
    effects.mkdir(parents=True)
    write_pack_metadata(pack, "Qwen pixel transport")
    install_wire(pack, out / "fonts")
    for name in ("screen.vsh", "packet.fsh"):
        shutil.copy2(ROOT / "shaders" / name, shaders / name)
    shutil.copy2(ROOT / "shaders/codec.glsl", shaders / "include/codec.glsl")
    pipeline = {
        "targets": {"packet": {"width": 32, "height": 5, "persistent": True}},
        "passes": [
            {
                "vertex_shader": "qwen:screen",
                "fragment_shader": "qwen:packet",
                "inputs": [{"sampler_name": "Main", "target": "minecraft:main"}],
                "output": "packet",
            }
        ],
    }
    (effects / "end_of_frame.json").write_text(
        json.dumps(pipeline), encoding="utf-8", newline="\n"
    )
    archive(pack, out / "transport-resourcepack.zip")
    archive(out / "datapack", out / "datapack.zip")
    print("Built", out / "transport-resourcepack.zip", flush=True)
    return out


if __name__ == "__main__":
    build()
