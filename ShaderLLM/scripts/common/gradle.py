"""Construct the native harness Gradle launcher command."""

from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
from scripts.common.paths import ROOT


def java_runtime():
    home = os.environ.get("JAVA_HOME")
    if home:
        java = Path(home).expanduser() / "bin" / executable_name("java")
        if not java.is_file():
            raise RuntimeError(f"JAVA_HOME does not contain a Java executable: {java}")
    else:
        found = shutil.which("java")
        if not found:
            raise RuntimeError("Install Java 25 and set JAVA_HOME or add java to PATH")
        java = Path(found)
    try:
        return java, _java_home(java)
    except RuntimeError:
        if home or sys.platform != "darwin":
            raise
    # macOS may expose an older system Java while a newer JDK is installed.
    commands = [["/usr/libexec/java_home", "-v", "25"]]
    if brew := shutil.which("brew"):
        commands.append([brew, "--prefix", "openjdk@25"])
    for command in commands:
        found = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        if found.returncode == 0 and found.stdout.strip():
            candidate = Path(found.stdout.strip()) / "bin/java"
            if candidate.is_file():
                try:
                    return candidate, _java_home(candidate)
                except RuntimeError:
                    pass
    raise RuntimeError("Install Java 25 and set JAVA_HOME or add java to PATH")


def _java_home(java):
    probe = subprocess.run(
        [str(java), "-XshowSettings:properties", "-version"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
    )
    properties = dict(
        re.findall(
            r"^\s*(java\.[\w.]+)\s*=\s*(.+)$", probe.stderr + probe.stdout, re.MULTILINE
        )
    )
    major = properties.get("java.specification.version", "0")
    if (
        probe.returncode
        or not major.isdigit()
        or int(major) < 25
        or "java.home" not in properties
    ):
        raise RuntimeError(
            f"Java 25 is required; {java} reports version {major}. Set JAVA_HOME to a Java 25 installation."
        )
    return Path(properties["java.home"])


def executable_name(name):
    return name + ".exe" if os.name == "nt" else name


def minecraft_client():
    override = os.environ.get("QWEN_MINECRAFT_CLIENT")
    home = Path(
        os.environ.get("GRADLE_USER_HOME", Path.home() / ".gradle")
    ).expanduser()
    path = (
        Path(override).expanduser()
        if override
        else home / "caches/fabric-loom/26.3/minecraft-client.jar"
    )
    if not path.is_file():
        raise RuntimeError(
            f"Minecraft 26.3 client JAR is missing: {path}. Run python3 scripts/build/setup.py first."
        )
    return path


def gradle_command(*tasks, offline=True, backend=None, transport_only=False):
    if backend not in (None, "opengl", "vulkan"):
        raise ValueError(f"Unknown graphics backend: {backend}")
    java, home = java_runtime()
    command = [
        str(java),
        f"-Dorg.gradle.java.home={home}",
        "-classpath",
        str(ROOT / "harness/gradle/wrapper/gradle-wrapper.jar"),
        "org.gradle.wrapper.GradleWrapperMain",
        "-p",
        str(ROOT / "harness"),
        "--console=plain",
    ]
    if offline:
        command.append("--offline")
    if backend:
        command.append(f"-PqwenGraphicsBackend={backend}")
    if transport_only:
        command.append("-PqwenTransportOnly=true")
    return command + list(tasks)
