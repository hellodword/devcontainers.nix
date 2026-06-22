#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    for script_name in [
        "check-gui-env.py",
        "check-vscode-extension-projector.py",
        "check-task-runner.py",
        "check-devpkg.py",
    ]:
        subprocess.run([sys.executable, str(script_dir / script_name)], check=True)
    print("runtime-tools-check ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
