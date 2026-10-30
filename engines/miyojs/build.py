#!/usr/bin/env python3
"""Stage pinned MiyoJS/SanaJK packages; never install packages at app runtime."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/engines/miyojs')
    parser.add_argument('--node', type=Path, default=Path(shutil.which('node') or '/opt/homebrew/bin/node'))
    parser.add_argument('--npm', type=Path, default=Path(shutil.which('npm') or '/opt/homebrew/bin/npm'))
    args = parser.parse_args()
    pin = json.loads((HERE / 'UPSTREAM.json').read_text())
    if hashlib.sha256((HERE / 'package-lock.json').read_bytes()).hexdigest() != pin['package_lock_sha256']:
        raise ValueError('MiyoJS dependency lock SHA256 mismatch')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for name in ('package.json', 'package-lock.json'):
        shutil.copyfile(HERE / name, output / name)
    node = args.node.resolve(strict=True)
    environment = {**os.environ, 'PATH': str(node.parent) + os.pathsep + os.environ.get('PATH', '')}
    subprocess.run([str(args.npm), 'ci', '--ignore-scripts', '--omit=dev', '--no-audit', '--no-fund'],
                   cwd=output, env=environment, check=True, timeout=180)
    package = output / 'node_modules/miyojs'
    if json.loads((package / 'package.json').read_text())['version'] != pin['version']:
        raise ValueError('MiyoJS resolved version differs from pin')
    # Keep an audit record of every shipped npm package and its license declaration.
    dependencies = []
    notices = output / 'licenses'
    notices.mkdir(exist_ok=True)
    for metadata in sorted((output / 'node_modules').rglob('package.json')):
        if metadata.parent.name.startswith('.'):
            continue
        obj = json.loads(metadata.read_text())
        if not obj.get('name') or not obj.get('version'):
            continue
        relative = metadata.parent.relative_to(output / 'node_modules')
        dependencies.append({'path': str(relative), 'name': obj['name'], 'version': obj['version'],
                             'license': obj.get('license', obj.get('licenses', 'unconfirmed'))})
        for text in metadata.parent.iterdir():
            if text.is_file() and text.name.lower().startswith(('license', 'copying', 'notice', 'readme')):
                destination = notices / str(relative).replace('/', '__')
                destination.mkdir(exist_ok=True)
                shutil.copyfile(text, destination / text.name)
    shutil.copyfile(HERE / 'UPSTREAM.json', output / 'UPSTREAM.json')
    (output / 'BUILD.json').write_text(json.dumps({
        'node_version': subprocess.check_output([str(node), '--version'], text=True).strip(),
        'node': str(node), 'transport': 'SHIOLINK UTF-8', 'upstream_source_changes': False,
        'miyo_entry_sha256': hashlib.sha256((package / 'bin/miyo-shiolink.js').read_bytes()).hexdigest(),
        'dependencies': dependencies,
    }, indent=2) + '\n')
    print('Staged pinned MiyoJS and SanaJK: ' + str(output))


if __name__ == '__main__':
    main()
