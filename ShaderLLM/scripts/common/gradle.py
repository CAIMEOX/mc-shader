"""Construct the native harness Gradle launcher command."""

from pathlib import Path
from scripts.common.paths import ROOT


def gradle_command(task):
    java = Path("/opt/homebrew/opt/openjdk@25")
    return [
        str(java / "bin/java"),
        f"-Dorg.gradle.java.home={java}",
        "-classpath",
        str(ROOT / "harness/gradle/wrapper/gradle-wrapper.jar"),
        "org.gradle.wrapper.GradleWrapperMain",
        "-p",
        str(ROOT / "harness"),
        "--offline",
        "--console=plain",
        task,
    ]
