#!/usr/bin/env python3
"""Build the official latest YAYA interpreter using AYA5 config filenames."""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

if __name__ == "__main__":
    subprocess.run([sys.executable, str(HERE.parent / "yaya/build.py"), "--variant", "aya",
                    "--output", str(ROOT / "build/engines/aya"), *sys.argv[1:]], check=True)
