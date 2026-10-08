"""Assemble Haskell-generated Minecraft resources into reproducible packs."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import gzip
import hashlib
import json
import os
import shutil
import struct
import subprocess
import zipfile
import zlib
from pathlib import Path

from scripts.build.compile import compiler
from scripts.common.paths import ROOT

CLIENT = Path(
    os.environ.get(
        "BACKROOMS_CLIENT_JAR",
        str(Path.home() / ".gradle/caches/fabric-loom/26.3/minecraft-client.jar"),
    )
)


def png(rgba, width, height):
    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data))
        )

    rows = b"".join(
        b"\0" + rgba[y * width * 4 : (y + 1) * width * 4] for y in range(height)
    )
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


def build():
    executable = compiler()
    output = ROOT / "build"
    output.mkdir(exist_ok=True)
    for name in ("resourcepack", "datapack", "materialpack"):
        folder = output / name
        if folder.exists():
            if not (folder / ".backrooms-owned").exists():
                raise RuntimeError(
                    f"Generated output requires its ownership marker: {folder}"
                )
            shutil.rmtree(folder)
        folder.mkdir()
        (folder / ".backrooms-owned").touch()
    vanilla = output / "vanilla"
    vanilla.mkdir(exist_ok=True)
    with zipfile.ZipFile(CLIENT) as jar:
        version = json.loads(jar.read("version.json"))
        if version["id"] != "26.3":
            raise RuntimeError("Backrooms targets Minecraft Java 26.3")
        for shader in ("item", "entity", "block"):
            for ext in ("vsh", "fsh"):
                filename = f"{shader}.{ext}"
                (vanilla / filename).write_bytes(
                    jar.read(f"assets/minecraft/shaders/core/{filename}")
                )
        for path, name in (
            ("data/minecraft/dimension_type/overworld.json", "dimension_type.json"),
            ("data/minecraft/worldgen/biome/plains.json", "biome.json"),
        ):
            (vanilla / name).write_bytes(jar.read(path))
    subprocess.run([str(executable), "build", str(ROOT)], check=True)
    for source in (output / "datapack").rglob("*.nbt.raw"):
        source.with_suffix("").write_bytes(gzip.compress(source.read_bytes(), mtime=0))
        source.unlink()
    texture = output / "resourcepack/assets/backrooms/textures/block/carrier.png"
    texture.parent.mkdir(parents=True, exist_ok=True)
    texture.write_bytes(png((output / "carrier.rgba").read_bytes(), 64, 4))
    for texture in json.loads((output / "materials.json").read_text()):
        target = output / "materialpack" / texture["asset"]
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(
            png(
                (output / texture["source"]).read_bytes(),
                texture["width"],
                texture["height"],
            )
        )
    artifacts = {}
    for kind, name in (
        ("data", "datapack"),
        ("resource", "resourcepack"),
        ("resource", "materialpack"),
    ):
        directory = output / name
        formats = version["pack_version"]
        fmt = [formats[kind + "_major"], formats[kind + "_minor"]]
        (directory / "pack.mcmeta").write_text(
            json.dumps(
                {
                    "pack": {
                        "description": "Backrooms: Procedural Level 0"
                        if kind == "data"
                        else "Backrooms: Level 0 Materials"
                        if name == "materialpack"
                        else "Backrooms: Spatial Lab",
                        "min_format": fmt,
                        "max_format": fmt,
                    }
                },
                indent=2,
            )
            + "\n"
        )
        archive_path = output / (name + ".zip")
        with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(directory.rglob("*")):
                if path.is_file() and not path.name.startswith("."):
                    if path.suffix == ".json":
                        json.loads(path.read_text())
                    entry = zipfile.ZipInfo(
                        path.relative_to(directory).as_posix(), (1980, 1, 1, 0, 0, 0)
                    )
                    entry.compress_type = zipfile.ZIP_DEFLATED
                    entry.external_attr = 0o644 << 16
                    archive.writestr(entry, path.read_bytes())
        artifacts[name] = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    (output / "artifacts.json").write_text(
        json.dumps(
            {
                "minecraft": "26.3",
                "client_sha1": hashlib.sha1(CLIENT.read_bytes()).hexdigest(),
                "artifacts": artifacts,
            },
            indent=2,
        )
        + "\n"
    )
    print(output)
    return output


if __name__ == "__main__":
    build()
