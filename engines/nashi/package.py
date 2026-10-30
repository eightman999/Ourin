#!/usr/bin/env python3
"""Stage the nashi macOS engine for Ourin's SHIORI plugin packager."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=ROOT / 'build/engines/nashi')
    args = parser.parse_args()
    source = args.source.resolve()
    if not (source / 'BUILD.json').is_file():
        subprocess.run([sys.executable, HERE / 'build.py', '--output', str(source)], check=True)
    target = args.destination.resolve() / 'nashi'
    target.mkdir(parents=True, exist_ok=True)
    for name in ['nashi-shiolink', 'upstream-LICENSE', 'upstream-README.md',
                 'upstream-CHANGELOG.md', 'upstream-VERSION', 'UPSTREAM.json', 'BUILD.json']:
        shutil.copyfile(source / name, target / name)
    shutil.copyfile(HERE / 'README.md', target / 'README.Ourin.md')
    build = json.loads((source / 'BUILD.json').read_text())
    (target / 'nashi-shiolink').chmod(0o755)
    entries = [{'id': 'nashi', 'name': 'なし栞 1.0.4-alpha系（macOS移植）', 'kind': 'shiolink',
                'executable': 'nashi/nashi-shiolink', 'arguments': [], 'charset': 'UTF-8', 'moduleNames': ['nashi.dll'],
                'markers': ['ghost.json', 'nashi.json'], 'architectures': build['architectures'],
                'minimumOSVersion': build['minimumOSVersion'], 'licenseScope': 'redistributable',
                'limitations': '許諾されたmain 1.0.4-alpha系のmacOS移植。上流version応答は1.0.0。Windows PE SAORIやなしスタジオは対象外。macOSのSAORIはmalloc/free・C long ABIが必要。'}]
    (args.destination / 'nashi-manifest.json').write_text(json.dumps(entries, ensure_ascii=False, indent=2) + '\n')
    print('Staged nashi engine plugin: ' + str(target))


if __name__ == '__main__':
    main()
