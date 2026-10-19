"""Compile the Haskell generator and package its Minecraft resources."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pathlib import Path
import hashlib
import json
import os
import shutil
import struct
import subprocess
import zipfile
import zlib

from scripts.common.paths import ROOT
from scripts.build.compile import compiler
from scripts.build.ui import assets as ui_assets

CLIENT = Path(
    os.environ.get(
        "MANIFOLD_CLIENT_JAR",
        str(Path.home() / ".gradle/caches/fabric-loom/26.3/minecraft-client.jar"),
    )
)


def png(rgba: bytes, width: int, height: int) -> bytes:
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
    for name in ("resourcepack", "resourcepack-test", "datapack"):
        destination = output / name
        if destination.exists():
            if not (destination / ".manifold-owned").exists():
                raise RuntimeError(
                    f"Generated directory has no ownership marker: {destination}"
                )
            shutil.rmtree(destination)
        destination.mkdir()
        (destination / ".manifold-owned").touch()
    vanilla = output / "vanilla"
    vanilla.mkdir(exist_ok=True)
    with zipfile.ZipFile(CLIENT) as jar:
        version = json.loads(jar.read("version.json"))
        interface_assets = ui_assets(jar.namelist(), png)
        if version["id"] != "26.3":
            raise RuntimeError("This build targets Minecraft 26.3")
        for shader in ("item", "entity", "block"):
            for extension in ("vsh", "fsh"):
                filename = f"{shader}.{extension}"
                (vanilla / filename).write_bytes(
                    jar.read(f"assets/minecraft/shaders/core/{filename}")
                )
    subprocess.run([str(executable), "build", str(ROOT)], check=True)
    for name in ("resourcepack", "resourcepack-test"):
        texture = output / name / "assets/manifold/textures/block/carrier.png"
        texture.parent.mkdir(parents=True, exist_ok=True)
        pixels = (output / "carrier.rgba").read_bytes()
        texture.write_bytes(png(pixels, len(pixels) // 16, 4))
        for relative, content in interface_assets.items():
            target = output / name / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
    artifacts = {}
    for kind, name in [
        ("resource", "resourcepack"),
        ("resource", "resourcepack-test"),
        ("data", "datapack"),
    ]:
        directory = output / name
        formats = version["pack_version"]
        format_version = [formats[f"{kind}_major"], formats[f"{kind}_minor"]]
        (directory / "pack.mcmeta").write_text(
            json.dumps(
                {
                    "pack": {
                        "description": "Manifold: six-axis gravity and periodic architecture",
                        "min_format": format_version,
                        "max_format": format_version,
                    }
                },
                indent=2,
            )
            + "\n"
        )
        with zipfile.ZipFile(
            output / f"{name}.zip", "w", zipfile.ZIP_DEFLATED
        ) as archive:
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
        artifacts[name] = hashlib.sha256(
            (output / f"{name}.zip").read_bytes()
        ).hexdigest()
    (output / "artifacts.json").write_text(
        json.dumps(
            {
                "minecraft": version["id"],
                "client_sha1": hashlib.sha1(CLIENT.read_bytes()).hexdigest(),
                "artifacts": artifacts,
            },
            indent=2,
        )
        + "\n"
    )
    print(output)


if __name__ == "__main__":
    build()
