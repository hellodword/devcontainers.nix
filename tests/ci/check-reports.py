#!/usr/bin/env python3
import pathlib
import runpy
import sys


if __name__ == "__main__":
    script = pathlib.Path(__file__).with_name("check-report-bundle.py")
    sys.argv[0] = str(script)
    runpy.run_path(str(script), run_name="__main__")
