"""Assemble Haskell-generated resources and production GLSL into runnable packs."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pathlib import Path
import json
import shutil
import subprocess
import zipfile
from scripts.build.compile import compiler

from scripts.common.paths import ROOT

CLIENT = Path.home() / ".gradle/caches/fabric-loom/26.3/minecraft-client.jar"


def archive(root, destination):
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=1) as z:
        for p in sorted(root.rglob("*")):
            if p.is_file():
                z.write(p, p.relative_to(root))


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
    (rp / "pack.mcmeta").write_text(
        json.dumps(
            {
                "pack": {
                    "description": "Qwen3 shader inference",
                    "min_format": [97, 1],
                    "max_format": [97, 1],
                }
            }
        )
    )
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
    shutil.copy2(out / "fonts/wire.json", assets / "font/wire.json")
    shutil.copy2(out / "fonts/wire.png", assets / "textures/font/wire.png")
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
    with zipfile.ZipFile(CLIENT) as z:
        vertex = z.read("assets/minecraft/shaders/core/text.vsh").decode()
        fragment = z.read("assets/minecraft/shaders/core/text.fsh").decode()
    declaration = "\nuniform sampler2D Sampler0;\n#include <minecraft:globals.glsl>\nlayout(location=4) flat out ivec3 wire;\n"
    vertex = vertex.replace(
        "void main() {", declaration + "void main() {\n    wire=ivec3(-1);"
    )
    inject = """
    ivec2 size=textureSize(Sampler0,0),uv=ivec2(floor(UV0*vec2(size)));
    ivec4 marker=ivec4(0);
    for(int y=-1;y<=0;y++)for(int x=-1;x<=0;x++){
        ivec4 c=ivec4(round(texelFetch(Sampler0,clamp(uv+ivec2(x,y),ivec2(0),size-1),0)*255.));
        if(c.a==247&&c.b>=235&&c.b<=239)marker=c;
    }
    if(marker.a==247){
        int kind=marker.b,index=(int(round(Color.r*255.))<<8)|int(round(Color.g*255.));
        int cell=kind==237?0:(kind==236?1:(kind==235?2:3+index));
        int corner=gl_VertexIndex%4;
        vec2 offset=vec2(corner>=2?2.:0.,(corner==1||corner==2)?2.:0.);
        vec2 pixel=vec2((cell%32)*2,(cell/32)*2)+offset;
        gl_Position=vec4(pixel.x/ScreenSize.x*2.-1.,1.-pixel.y/ScreenSize.y*2.,-1.,1.);
        wire=kind==239?ivec3(marker.g,marker.r,239):ivec3(index>>8,index&255,kind);
    }
"""
    vertex = vertex.rstrip()[:-1] + inject + "}\n"
    fragment = fragment.replace(
        "void main() {",
        "layout(location=4) flat in ivec3 wire;\nvoid main() {\n    if(wire.z>=235){\n#ifdef OIT_ALPHA_ONLY\n        executeAlphaOnlyPhase(gl_FragCoord.z,1.);\n#else\n        fragColor=vec4(vec3(wire)/255.,1.);\n#endif\n        return;\n    }",
    )
    (rp / "assets/minecraft/shaders/core/text.vsh").write_text(vertex)
    (rp / "assets/minecraft/shaders/core/text.fsh").write_text(fragment)
    archive(rp, out / "resourcepack.zip")
    archive(out / "datapack", out / "datapack.zip")
    print("Built", out / "resourcepack.zip", flush=True)
    return out


if __name__ == "__main__":
    build()
