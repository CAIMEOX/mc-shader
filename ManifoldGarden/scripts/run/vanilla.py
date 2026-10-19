"""Open Manifold in the official, unmodified Java 26.3 client on macOS."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import uuid
import zipfile

from scripts.common.paths import ROOT
import fcntl


def locked(world):
    lock = world / "session.lock"
    if not lock.exists():
        return False
    with lock.open("rb") as stream:
        try:
            fcntl.lockf(stream, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.lockf(stream, fcntl.LOCK_UN)
    return False


def write_bootstrap(bootstrap, entry="manifold:session/start"):
    """Write the demo world's entry pack, shared with the native entry checks."""
    (bootstrap / "data/minecraft/tags/function").mkdir(parents=True, exist_ok=True)
    (bootstrap / "data/manifold_launch/function").mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(ROOT / "build/datapack.zip") as pack:
        (bootstrap / "pack.mcmeta").write_bytes(pack.read("pack.mcmeta"))
    for event in ("load", "tick"):
        (bootstrap / f"data/minecraft/tags/function/{event}.json").write_text(
            json.dumps({"values": [f"manifold_launch:{event}"]}) + "\n"
        )
    functions = {
        "load": [
            "scoreboard objectives add manifold.launch dummy",
            "scoreboard objectives add manifold.launch_seen dummy",
            "scoreboard players add #generation manifold.launch 1",
            "gamerule minecraft:fall_damage false",
        ],
        "tick": [
            "execute as @a unless score @s manifold.launch_seen = #generation manifold.launch at @s run function manifold_launch:start",
        ],
        "start": [
            "execute if entity @s[nbt={Health:0.0f}] run return 0",
            "execute unless entity @s[tag=manifold.pilot] run gamemode spectator @s",
            "execute in minecraft:overworld run forceload add 0 0",
            "execute in minecraft:overworld unless loaded 0 64 0 run return 0",
            "execute in minecraft:overworld run fill 0 64 0 8 64 8 minecraft:quartz_block",
            "execute in minecraft:overworld run fill 0 65 0 8 69 8 minecraft:air",
            "execute in minecraft:overworld run setworldspawn 4 65 4",
            "execute in minecraft:overworld run spawnpoint @s 4 65 4",
            "execute unless entity @s[tag=manifold.pilot] in minecraft:overworld run tp @s 4.5 65.0 4.5 0 20",
            "execute unless entity @s[tag=manifold.pilot] run gamemode adventure @s",
            f"execute unless entity @s[tag=manifold.pilot] at @s run function {entry}",
            "execute unless entity @s[tag=manifold.pilot] run return 0",
            "data modify storage manifold:session position set value [4.5d,65.0d,4.5d]",
            "data modify storage manifold:session rotation set value [0.0f,20.0f]",
            'data modify storage manifold:session dimension set value "minecraft:overworld"',
            "scoreboard players set #g.savedmode manifold 2",
            "scoreboard players operation @s manifold.launch_seen = #generation manifold.launch",
            "execute in minecraft:overworld run forceload remove 0 0",
        ],
    }
    for name, commands in functions.items():
        (bootstrap / f"data/manifold_launch/function/{name}.mcfunction").write_text(
            "\n".join(commands) + "\n"
        )


def prepare(level="atrium"):
    if platform.system() != "Darwin":
        raise RuntimeError("This local launcher uses the macOS runtime cache")
    cache = Path.home() / ".gradle/caches"
    runtime = cache / "fabric-loom/26.3"
    metadata = json.loads((runtime / "mojang_minecraft_info.json").read_text())
    client = runtime / "minecraft-client.jar"
    if (
        hashlib.sha1(client.read_bytes()).hexdigest()
        != metadata["downloads"]["client"]["sha1"]
    ):
        raise RuntimeError("The client must match Mojang's official version metadata")
    classpath = [client]
    for library in metadata["libraries"]:
        allowed = not library.get("rules")
        for rule in library.get("rules", []):
            os_rule = rule.get("os", {})
            if os_rule.get("name", "osx") == "osx" and "arch" not in os_rule:
                allowed = rule["action"] == "allow"
        if not allowed:
            continue
        name = library["name"]
        if "natives-macos" in name:
            arm = platform.machine() == "arm64"
            if ("arm64" in name) != arm:
                continue
        group, artifact, version, *_ = name.split(":")
        info = library["downloads"]["artifact"]
        filename = Path(info["path"]).name
        candidates = (cache / "modules-2/files-2.1" / group / artifact / version).glob(
            "*/" + filename
        )
        path = next(
            (
                p
                for p in candidates
                if hashlib.sha1(p.read_bytes()).hexdigest() == info["sha1"]
            ),
            None,
        )
        if path is None:
            raise RuntimeError(
                "Prepare the Minecraft harness runtime first; missing library: " + name
            )
        classpath.append(path)

    output = ROOT / "vanilla-playground"
    world_name, entry = {
        "atrium": ("Manifold", "manifold:session/start"),
        "three-rings": ("Three Rings", "manifold:three_rings/session"),
        "joinery": ("Joinery Court", "manifold:joinery/session"),
    }[level]
    world = output / "saves" / world_name
    if locked(world):
        raise RuntimeError(f"{world_name} is already open")
    if not (world / "level.dat").exists():
        source = ROOT / "harness/build/run/clientGameTest/saves/New World"
        if (
            not (source / "level.dat").exists()
            or not (ROOT / "reports/native.json").exists()
        ):
            raise RuntimeError(
                "Run scripts/verify/run_tests.py successfully before creating this world"
            )
        report = json.loads((ROOT / "reports/native.json").read_text())
        artifacts = json.loads((ROOT / "build/artifacts.json").read_text())
        if (
            report["result"] != "passed"
            or report["build"] != artifacts
            or locked(source)
        ):
            raise RuntimeError(
                "Run scripts/verify/run_tests.py successfully before creating this world"
            )
        shutil.copytree(source, world, ignore=shutil.ignore_patterns("session.lock"))
    for source, destination in [
        (ROOT / "build/resourcepack.zip", output / "resourcepacks/manifold.zip"),
        (ROOT / "build/datapack.zip", world / "datapacks/manifold.zip"),
    ]:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    write_bootstrap(world / "datapacks/manifold_launch", entry)
    options = output / "options.txt"
    configured = {
        "resourcePacks": '["vanilla","file/manifold.zip"]',
        "bobView": "false",
        "renderDistance": "5",
        "maxFps": "120",
        "pauseOnLostFocus": "false",
        "inactivityFpsLimit": '"minimized"',
        "perspective": "0",
    }
    lines = options.read_text().splitlines() if options.exists() else []
    options.write_text(
        "\n".join(
            [line for line in lines if line.split(":", 1)[0] not in configured]
            + [key + ":" + value for key, value in configured.items()]
        )
        + "\n"
    )
    assets = cache / "fabric-loom/assets"
    java = (
        Path(os.environ.get("MANIFOLD_JAVA_HOME", "/opt/homebrew/opt/openjdk@25"))
        / "bin/java"
    )
    command = [
        str(java),
        "-XstartOnFirstThread",
        "-Xmx2G",
        "--enable-native-access=ALL-UNNAMED",
        "--add-exports",
        "java.base/jdk.internal.misc=ALL-UNNAMED",
        "-Dorg.lwjgl.system.SharedLibraryExtractPath=" + str(output / "natives"),
        "-cp",
        os.pathsep.join(map(str, classpath)),
        metadata["mainClass"],
        "--username",
        "ManifoldExplorer",
        "--uuid",
        str(uuid.uuid3(uuid.NAMESPACE_DNS, "manifold-explorer")),
        "--accessToken",
        "0",
        "--version",
        "26.3",
        "--versionType",
        "release",
        "--gameDir",
        str(output),
        "--assetsDir",
        str(assets),
        "--assetIndex",
        "26.3-34",
        "--width",
        "1280",
        "--height",
        "900",
        "--quickPlaySingleplayer",
        world_name,
    ]
    (output / "runtime.json").write_text(
        json.dumps(
            {
                "minecraft": "26.3",
                "level": level,
                "world": world_name,
                "main_class": metadata["mainClass"],
                "client_sha1": metadata["downloads"]["client"]["sha1"],
                "classpath": [str(p) for p in classpath],
            },
            indent=2,
        )
        + "\n"
    )
    return output, command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument(
        "--level",
        choices=("atrium", "three-rings", "joinery"),
        default="atrium",
    )
    args = parser.parse_args()
    output, command = prepare(args.level)
    if args.prepare_only:
        print(output)
        return 0
    message = (
        "Opening Joinery Court · Aim the Joinery Tool at timber and right-click · Ctrl gravity · Space jump"
        if args.level == "joinery"
        else "Opening Three Rings · Right-click cubes · Ctrl gravity · Space jump"
        if args.level == "three-rings"
        else "Opening Atrium · Explore the lattice · Ctrl gravity · Space jump"
    )
    print(message, flush=True)
    with (output / "launcher.log").open("w") as log:
        result = subprocess.run(
            command, cwd=output, stdout=log, stderr=subprocess.STDOUT
        )
    if result.returncode:
        print("\n".join((output / "launcher.log").read_text().splitlines()[-40:]))
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
