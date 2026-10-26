#!/usr/bin/env python3
"""Compile the production YAYA config collector, before loading external data."""
import argparse
from pathlib import Path
import subprocess
import sys
repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / 'scripts'))
from corpus_probe.build import _collector_sources
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args()
args.output_dir.mkdir(parents=True, exist_ok=True)
body, _ = _collector_sources(repo)
source = args.output_dir / 'collector.swift'
source.write_text(body)
output = args.output_dir / 'yaya_plugin_collector'
subprocess.run(['/usr/bin/swiftc', str(source), '-o', str(output)], check=True)
print(output)
