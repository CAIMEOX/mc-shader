"""Assemble Haskell-generated resources and production GLSL into runnable packs."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import shutil
import subprocess
from scripts.build.compile import compiler
from scripts.build.resources import archive, install_wire, write_pack_metadata

from scripts.common.paths import ROOT


def build():
    executable = compiler()
    out = ROOT / "build"
    if (out / "pipeline").exists():
        shutil.rmtree(out / "pipeline")
    for command, args in [
        ("context", [out / "model"]),
        (
            "constants",
            [out / "tokenizer", out / "reference/chat.json", out / "include"],
        ),
        ("pipeline", [out / "model", ROOT / "shaders", out / "pipeline"]),
        ("datapack", [out / "datapack"]),
    ]:
        subprocess.run([str(executable), command, *map(str, args)], check=True)
    rp = out / "resourcepack"
    if rp.exists():
        shutil.rmtree(rp)
    assets = rp / "assets/qwen"
    shaders = assets / "shaders"
    textures = assets / "textures/effect"
    for directory in (
        shaders,
        textures,
        assets / "font",
        assets / "textures/font",
        rp / "assets/minecraft/post_effect",
        rp / "assets/minecraft/shaders/core",
    ):
        directory.mkdir(parents=True, exist_ok=True)
    write_pack_metadata(rp, "Qwen3 shader inference")
    licenses = rp / "licenses"
    licenses.mkdir(exist_ok=True)
    for source, name in [
        (ROOT / "model/LICENSE", "Qwen3.txt"),
        (ROOT / "model/unifont-LICENSE.txt", "Unifont.txt"),
        (ROOT / "vendor/qwen3.c/LICENSE", "qwen3.c.txt"),
    ]:
        shutil.copy2(source, licenses / name)
    for p in (out / "model/textures").glob("*.png"):
        shutil.copy2(p, textures / p.name)
    for p in (out / "tokenizer").glob("*.png"):
        shutil.copy2(p, textures / p.name)
    shutil.copy2(out / "fonts/glyphs.png", textures / "glyphs.png")
    for folder in (ROOT / "shaders", out / "pipeline", out / "include"):
        for p in folder.iterdir():
            if p.suffix in (".fsh", ".vsh", ".glsl"):
                shutil.copy2(p, shaders / p.name)
    # Shader include resources live in a separate namespace-relative directory.
    include = shaders / "include"
    include.mkdir(exist_ok=True)
    for p in shaders.glob("*.glsl"):
        shutil.copy2(p, include / p.name)
    shutil.copy2(
        out / "pipeline/pipeline.json",
        rp / "assets/minecraft/post_effect/end_of_frame.json",
    )
    install_wire(rp, out / "fonts")
    archive(rp, out / "resourcepack.zip")
    archive(out / "datapack", out / "datapack.zip")
    print("Built", out / "resourcepack.zip", flush=True)
    return out


if __name__ == "__main__":
    build()
