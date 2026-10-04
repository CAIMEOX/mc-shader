"""Compile the Haskell generator and package its Minecraft resources."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import argparse
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
        "SIGNAL_CLIENT_JAR",
        str(Path.home() / ".gradle/caches/fabric-loom/26.3/minecraft-client.jar"),
    )
)


def message_argument(value):
    if not 1 <= len(value) <= 64 or any(not 32 <= ord(c) <= 126 for c in value):
        raise argparse.ArgumentTypeError(
            "--message requires 1 to 64 printable ASCII characters"
        )
    return value


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


def build(
    payload_start=1000,
    rates=(200, 500, 1000, 2000),
    levels=(0, 20, 32, 48),
    ping_message="hi from shader",
    fall_seed=None,
    rotate_stream_seed=None,
):
    if ping_message is not None:
        message_argument(ping_message)
    if fall_seed is not None and rotate_stream_seed is not None:
        raise ValueError("Select one frame-stream receiver")
    stream_seed = fall_seed if fall_seed is not None else rotate_stream_seed
    stream_profile = "fall" if fall_seed is not None else "rotate_stream"
    if stream_seed is not None and not 1 <= stream_seed <= 64000:
        raise ValueError("Stream seed must be in 1..64000")
    executable = compiler()
    output = ROOT / "build"
    output.mkdir(exist_ok=True)
    for name in ("resourcepack", "datapack"):
        destination = output / name
        if destination.exists():
            if not (destination / ".signal-owned").exists():
                raise RuntimeError(
                    f"Generated directory has no ownership marker: {destination}"
                )
            shutil.rmtree(destination)
        destination.mkdir()
        (destination / ".signal-owned").touch()
    vanilla = output / "vanilla"
    vanilla.mkdir(exist_ok=True)
    with zipfile.ZipFile(CLIENT) as jar:
        version = json.loads(jar.read("version.json"))
        if version["id"] != "26.3":
            raise RuntimeError("This build targets Minecraft 26.3")
        for shader in ("item", "entity", "block"):
            for extension in ("vsh", "fsh"):
                filename = f"{shader}.{extension}"
                (vanilla / filename).write_bytes(
                    jar.read(f"assets/minecraft/shaders/core/{filename}")
                )
    arguments = (
        [stream_profile.replace("_", "-"), str(stream_seed)]
        if stream_seed is not None
        else (
            [str(payload_start), ",".join(map(str, rates)), ",".join(map(str, levels))]
            if ping_message is None
            else ["pingpong", ping_message]
        )
    )
    subprocess.run([str(executable), str(ROOT), *arguments], check=True)
    post = output / "resourcepack/assets/signal/shaders/post"
    post.mkdir(parents=True, exist_ok=True)
    shaders = (
        ["stream_work", "stream_composite", "copy", "stream_state"]
        if stream_seed is not None
        else [
            "work",
            "composite",
            "copy",
            "state" if ping_message is None else "ping_state",
        ]
    )
    for shader in shaders:
        shutil.copy2(ROOT / "shaders/post" / f"{shader}.fsh", post / f"{shader}.fsh")
    shutil.copytree(
        ROOT / "shaders/include",
        output / "resourcepack/assets/signal/shaders/include",
        dirs_exist_ok=True,
    )
    core = output / "resourcepack/assets/minecraft/shaders/core"
    core.mkdir(parents=True, exist_ok=True)
    for shader in ("item", "entity", "block"):
        for extension in ("vsh", "fsh"):
            original = (vanilla / f"{shader}.{extension}").read_text()
            patch = (ROOT / f"shaders/core/carrier.{extension}.inc").read_text()
            if original.count("void main() {") != 1:
                raise RuntimeError("Expected one vanilla core entry point")
            (core / f"{shader}.{extension}").write_text(
                original.replace("void main() {", patch, 1)
            )
    texture = output / "resourcepack/assets/signal/textures/block/carrier.png"
    texture.parent.mkdir(parents=True, exist_ok=True)
    texture.write_bytes(png((output / "carrier.rgba").read_bytes(), 8, 4))
    artifacts = {}
    for kind, name in [("resource", "resourcepack"), ("data", "datapack")]:
        directory = output / name
        formats = version["pack_version"]
        format_version = [formats[f"{kind}_major"], formats[f"{kind}_minor"]]
        (directory / "pack.mcmeta").write_text(
            json.dumps(
                {
                    "pack": {
                        "description": "Signal: frame timing channel"
                        if stream_seed is not None
                        else "Signal: shader timing channel experiment"
                        if ping_message is None
                        else "Signal: ping-pong shader message channel",
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
                        path.relative_to(directory).as_posix(),
                        date_time=(1980, 1, 1, 0, 0, 0),
                    )
                    entry.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(entry, path.read_bytes())
        artifacts[name] = hashlib.sha256(
            (output / f"{name}.zip").read_bytes()
        ).hexdigest()
    (output / "artifacts.json").write_text(
        json.dumps(
            {
                "minecraft": version["id"],
                "profile": stream_profile
                if stream_seed is not None
                else "signal"
                if ping_message is None
                else "pingpong",
                "client_sha1": hashlib.sha1(CLIENT.read_bytes()).hexdigest(),
                "artifacts": artifacts,
            },
            indent=2,
        )
        + "\n"
    )
    print(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--message", type=message_argument, default="hi from shader")
    args = parser.parse_args()
    build(ping_message=args.message)
