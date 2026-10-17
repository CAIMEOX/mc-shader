"""Shared resource-pack metadata, archives, and the pixel transport shaders."""

import json
import shutil
import zipfile

from scripts.common.gradle import minecraft_client


def archive(root, destination):
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=1) as z:
        for p in sorted(root.rglob("*")):
            if p.is_file():
                z.write(p, p.relative_to(root))


def write_pack_metadata(root, description):
    (root / "pack.mcmeta").write_text(
        json.dumps(
            {
                "pack": {
                    "description": description,
                    "min_format": [97, 1],
                    "max_format": [97, 1],
                }
            }
        ),
        encoding="utf-8",
        newline="\n",
    )


def install_wire(rp, fonts):
    for directory in (
        "assets/qwen/font",
        "assets/qwen/textures/font",
        "assets/minecraft/shaders/core",
    ):
        (rp / directory).mkdir(parents=True, exist_ok=True)
    shutil.copy2(fonts / "wire.json", rp / "assets/qwen/font/wire.json")
    shutil.copy2(fonts / "wire.png", rp / "assets/qwen/textures/font/wire.png")
    with zipfile.ZipFile(minecraft_client()) as z:
        vertex = z.read("assets/minecraft/shaders/core/text.vsh").decode("utf-8")
        fragment = z.read("assets/minecraft/shaders/core/text.fsh").decode("utf-8")
    for source in (vertex, fragment):
        if source.count("void main() {") != 1 or not source.rstrip().endswith("}"):
            raise RuntimeError(
                "Unexpected Minecraft core text shader; use the Minecraft 26.3 client JAR"
            )
    declaration = "\nuniform sampler2D Sampler0;\n#include <minecraft:globals.glsl>\nlayout(location=4) flat out ivec3 wire;\n"
    vertex = vertex.replace(
        "void main() {", declaration + "void main() {\n    wire=ivec3(-1);"
    )
    inject = """
    ivec2 atlasSize=textureSize(Sampler0,0);
    ivec2 uv=ivec2(floor(UV0*vec2(atlasSize)));
    ivec4 marker=ivec4(0);
    for(int oy=-1;oy<=0;oy++)for(int ox=-1;ox<=0;ox++){
        ivec2 at=ivec2(clamp(uv.x+ox,0,atlasSize.x-1),clamp(uv.y+oy,0,atlasSize.y-1));
        ivec4 c=ivec4(round(texelFetch(Sampler0,at,0)*255.0));
        if(c.a==247&&c.b>=235&&c.b<=239)marker=c;
    }
    if(marker.a==247){
        int kind=marker.b,index=(int(round(Color.r*255.))<<8)|int(round(Color.g*255.));
        int cell=kind==237?0:(kind==236?1:(kind==235?2:3+index));
        int corner=gl_VertexIndex%4;
        vec2 offset=vec2(corner>=2?2.:0.,(corner==1||corner==2)?2.:0.);
        vec2 pixel=vec2((cell%32)*2,(cell/32)*2)+offset;
        // Zero is inside both clip-depth ranges used by the renderer.
        gl_Position=vec4(pixel.x/ScreenSize.x*2.0-1.0,1.0-pixel.y/ScreenSize.y*2.0,0.0,1.0);
        wire=kind==239?ivec3(marker.g,marker.r,239):ivec3(index>>8,index&255,kind);
    }
"""
    vertex = vertex.rstrip()[:-1] + inject + "}\n"
    fragment = fragment.replace(
        "void main() {",
        "layout(location=4) flat in ivec3 wire;\nvoid main() {\n    if(wire.z>=235){\n#ifdef OIT_ALPHA_ONLY\n        executeAlphaOnlyPhase(gl_FragCoord.z,1.);\n#else\n        fragColor=vec4(vec3(wire)/255.,1.);\n#endif\n        return;\n    }",
    )
    (rp / "assets/minecraft/shaders/core/text.vsh").write_text(
        vertex, encoding="utf-8", newline="\n"
    )
    (rp / "assets/minecraft/shaders/core/text.fsh").write_text(
        fragment, encoding="utf-8", newline="\n"
    )
