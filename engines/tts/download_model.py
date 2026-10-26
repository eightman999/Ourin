#!/usr/bin/env python3
"""Download the pinned optional Irodori snapshot, or verify an existing one.

Use a destination under the user's shared model store. No deletion/replacement
of existing data is performed; existing snapshots must match all pinned hashes.
"""
import argparse
import hashlib
import json
from pathlib import Path


def verify(root, files):
    for name, expected in files.items():
        path = root / name
        if not path.is_file() or path.stat().st_size != expected['bytes']:
            raise ValueError('missing or incorrect model file: ' + name)
        digest = hashlib.sha256()
        with path.open('rb') as source:
            for block in iter(lambda: source.read(1024 * 1024), b''):
                digest.update(block)
        if digest.hexdigest() != expected['sha256']:
            raise ValueError('model checksum mismatch: ' + name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    metadata = json.loads(Path(__file__).with_name('DEPENDENCIES.json').read_text())['model']
    destination = args.destination.expanduser().absolute()
    if not destination.exists():
        from huggingface_hub import snapshot_download
        snapshot_download(repo_id=metadata['repo'], revision=metadata['revision'],
                          local_dir=str(destination), token=False,
                          allow_patterns=list(metadata['files']) + ['README.md'])
    verify(destination, metadata['files'])
    print(destination.resolve())


if __name__ == '__main__':
    main()
