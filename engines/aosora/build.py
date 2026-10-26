#!/usr/bin/env python3
"""Build Aosora locally for personal use; never invoked by engines/package.sh."""
from pathlib import Path
import argparse
import concurrent.futures
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
PIN = json.loads((HERE / 'DEPENDENCIES.json').read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--arch', choices=['arm64', 'x86_64'], default=os.uname().machine)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-aosora-build-') as directory:
        work = Path(directory).resolve()
        archive = work / 'source.tar.gz'
        url = f'https://codeload.github.com/kanadelab/aosora-shiori/tar.gz/{PIN["revision"]}'
        urllib.request.urlretrieve(url, archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != PIN['archive_sha256']:
            raise RuntimeError('Upstream archive SHA-256 mismatch')
        with tarfile.open(archive) as tar:
            members = []
            for member in tar.getmembers():
                if member.issym() or member.islnk():
                    continue  # Upstream launch-script symlinks are not build inputs.
                target = (work / member.name).resolve()
                if not target.is_relative_to(work):
                    raise RuntimeError('Unsafe source archive member')
                members.append(member)
            tar.extractall(work, members=members)
        source = work / ('aosora-shiori-' + PIN['revision'])
        # The upstream root-frame constructor leaves these members indeterminate.
        # A stale break/continue mode can stop root initialization at a class node.
        header = source / 'aosora-shiori/Interpreter/ScriptExecutor.h'
        body = header.read_text(encoding='utf-8-sig')
        old = 'leaveMode(LeaveMode::None),\n\t\t\tisTalkLineEnd(false),'
        new = ('leaveMode(LeaveMode::None),\n\t\t\tloopDepth(0),'
               '\n\t\t\tloopMode(LoopMode::Normal),\n\t\t\ttryDepth(0),'
               '\n\t\t\tisTalkLineEnd(false),')
        if body.count(old) != 1:
            raise RuntimeError('Upstream root-stack constructor changed')
        header.write_text(body.replace(old, new))
        jsoncpp = source / 'thirdparty/jsoncpp-1.9.6'
        files = sorted((source / 'aosora-shiori').rglob('*.cpp'))
        files += sorted((jsoncpp / 'src/lib_json').glob('*.cpp'))
        files += [HERE / 'adapter.cpp']
        flags = ['-std=c++20', '-O2', '-fPIC', '-mmacosx-version-min=13.0', '-arch', args.arch,
                 '-I' + str(source / 'aosora-shiori'), '-I' + str(source / 'aosora-shiori-dll'),
                 '-I' + str(jsoncpp / 'include')]
        def compile_one(item):
            i, path = item
            obj = work / f'{i}.o'
            subprocess.run(['clang++', *flags, '-c', str(path), '-o', str(obj)], check=True)
            return obj
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(6, os.cpu_count() or 1)) as pool:
            objects = list(pool.map(compile_one, enumerate(files)))
        library = output / 'libaosora.dylib'
        subprocess.run(['clang++', '-arch', args.arch, '-dynamiclib', '-mmacosx-version-min=13.0',
                        '-install_name', '@rpath/libaosora.dylib', *map(str, objects), '-o', str(library)], check=True)
        (output / 'libaosora.dylib.plist').write_bytes(plistlib.dumps({'OurinShioriABI': 'aosora'}))
        shutil.copy(source / 'license.txt', output / 'LICENSE.aosora.txt')
        shutil.copy(jsoncpp / 'LICENSE', output / 'LICENSE.jsoncpp.txt')
        shutil.copy(HERE / 'DEPENDENCIES.json', output / 'DEPENDENCIES.json')
        (output / 'PERSONAL-USE-ONLY.txt').write_text(
            'This source-derived library is not approved for redistribution. '
            'Do not include it in an Ourin release. See LICENSE.aosora.txt.\n')
        subprocess.run(['codesign', '--force', '--sign', '-', str(library)], check=True)
        print(library)


if __name__ == '__main__':
    main()
