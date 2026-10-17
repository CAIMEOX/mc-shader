"""Download Minecraft dependencies and prepare the Java harness."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import argparse
import subprocess
from scripts.common.gradle import gradle_command


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    subprocess.run(
        gradle_command(
            "configureClientLaunch",
            "compileGametestJava",
            "compilePlayJava",
            offline=False,
        ),
        check=True,
    )


if __name__ == "__main__":
    main()
