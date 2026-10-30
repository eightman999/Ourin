#!/usr/bin/env python3
"""Build a native SHIORI development example against pinned lib_skeleton."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def extract(pin, destination, archive=None):
    if archive is None:
        archive = destination.parent / 'upstream.tar.gz'
        with urllib.request.urlopen(pin['url'], timeout=60) as stream:
            data = stream.read(16 * 1024 * 1024 + 1)
        if len(data) > 16 * 1024 * 1024:
            raise ValueError('archive too large')
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != pin['sha256']:
        raise ValueError('upstream SHA256 mismatch')
    destination.mkdir()
    with tarfile.open(archive) as tar:
        total = 0
        for member in tar.getmembers():
            parts = PurePosixPath(member.name).parts
            if member.name.startswith('/') or '..' in parts or member.issym() or member.islnk():
                raise ValueError('unsafe upstream archive')
            if len(parts) < 2: continue
            target = destination.joinpath(*parts[1:])
            if member.isdir(): target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                total += member.size
                if total > 64 * 1024 * 1024: raise ValueError('expanded archive too large')
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, target.open('wb') as out:
                    shutil.copyfileobj(source, out)
            else: raise ValueError('unsupported upstream entry')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/engines/lib_skeleton')
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    pin = json.loads((HERE / 'UPSTREAM.json').read_text())
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-skeleton-build-') as tmp:
        root = Path(tmp); source = root / 'lib_skeleton'
        extract(pin, source, args.archive)
        library = output / 'libskeleton-shiori.dylib'
        command = ['/usr/bin/clang++','-std=c++20','-O2','-Wall','-Wextra','-dynamiclib',
                   '-mmacosx-version-min=13.0','-I'+str(root),str(HERE/'sample.cpp'),'-o',str(library)]
        subprocess.run(command,check=True,timeout=60)
        library.with_suffix('.dylib.plist').write_bytes(plistlib.dumps({'OurinShioriABI':pin['abi']}))
        shutil.copyfile(source / pin['license_file'], output / 'LICENSE.lib_skeleton')
        shutil.copyfile(HERE / 'UPSTREAM.json', output / 'UPSTREAM.json')
        (output / 'BUILD.json').write_text(json.dumps({
            'revision':pin['revision'],'abi':pin['abi'],'upstream_source_changes':False,
            'request_header_sha256':hashlib.sha256((source/'base/request.h').read_bytes()).hexdigest(),
            'response_header_sha256':hashlib.sha256((source/'base/response.h').read_bytes()).hexdigest(),
            'compiler':subprocess.check_output(['/usr/bin/clang++','--version'],text=True).splitlines()[0],
        },indent=2)+'\n')
    print('Built real lib_skeleton parser/builder SHIORI sample: '+str(library))


if __name__ == '__main__': main()
