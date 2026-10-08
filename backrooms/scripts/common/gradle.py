"""Commands for the visible Minecraft verification and playground clients."""

import os
from pathlib import Path

from scripts.common.paths import ROOT


def gradle_command(task):
    java_home = Path(
        os.environ.get(
            "BACKROOMS_JAVA_HOME",
            os.environ.get("JAVA_HOME", "/opt/homebrew/opt/openjdk@25"),
        )
    )
    return [
        str(java_home / "bin/java"),
        f"-Dorg.gradle.java.home={java_home}",
        "-classpath",
        str(ROOT / "harness/gradle/wrapper/gradle-wrapper.jar"),
        "org.gradle.wrapper.GradleWrapperMain",
        "-p",
        str(ROOT / "harness"),
        "--offline",
        "--console=plain",
        task,
    ]
