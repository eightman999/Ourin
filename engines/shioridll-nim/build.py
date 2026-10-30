#!/usr/bin/env python3
"""Build fixed upstream Nim SHIORI examples with an explicit malloc/cint POSIX ABI.

The compiler lives only in a temporary build directory. No nimble/global setup.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def extract(pin, destination, supplied=None):
    archive = supplied or destination.parent / (destination.name + '.tar')
    if supplied is None:
        with urllib.request.urlopen(pin['url'], timeout=60) as response:
            data = response.read(64 * 1024 * 1024 + 1)
        if len(data) > 64 * 1024 * 1024:
            raise ValueError('archive size limit exceeded')
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != pin['sha256']:
        raise ValueError('upstream SHA256 mismatch: ' + pin['url'])
    destination.mkdir()
    with tarfile.open(archive) as tar:
        total = 0
        for member in tar.getmembers():
            parts = PurePosixPath(member.name).parts
            if member.name.startswith('/') or '..' in parts or member.issym() or member.islnk():
                raise ValueError('unsafe archive entry')
            if len(parts) < 2:
                continue
            target = destination.joinpath(*parts[1:])
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                total += member.size
                if total > 512 * 1024 * 1024:
                    raise ValueError('expanded archive size limit exceeded')
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, target.open('wb') as out:
                    shutil.copyfileobj(source, out)
                target.chmod(member.mode & 0o777)
            else:
                raise ValueError('unsupported archive entry')


def patch_interface(path):
    source = path.read_text()
    replacements = [
        ('  proc shioriAlloc(size: Natural): MemoryHandle {.inline.} = cast[ptr cchar](alloc(size))\n'
         '  proc shioriFree(p: MemoryHandle): void {.inline.} = dealloc(p)',
         '  # Ourin POSIX ABI: only exported buffers use libc malloc/free.\n'
         '  proc cMalloc(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}\n'
         '  proc cFree(p: pointer) {.importc: "free", header: "<stdlib.h>".}\n'
         '  proc shioriAlloc(size: Natural): MemoryHandle {.inline.} = cast[MemoryHandle](cMalloc(csize_t(size)))\n'
         '  proc shioriFree(p: MemoryHandle): void {.inline.} = cFree(cast[pointer](p))'),
        ('proc load(h: MemoryHandle, len: clong): bool', 'proc load(h: MemoryHandle, len: clong): cint'),
        ('  shioriLoadCallback(dirpathStr)\n', '  cint(ord(shioriLoadCallback(dirpathStr)))\n'),
        ('proc unload(): bool', 'proc unload(): cint'),
        ('  shioriUnloadCallback()\n', '  cint(ord(shioriUnloadCallback()))\n'),
        ('  let responseStr = cstring(shioriRequestCallback(requestStr))',
         '  let response = shioriRequestCallback(requestStr)\n  let responseStr = cstring(response)'),
    ]
    for original, replacement in replacements:
        if source.count(original) != 1:
            raise ValueError('fixed upstream ABI patch no longer matches')
        source = source.replace(original, replacement)
    path.write_text(source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=['arm64', 'x86_64', 'universal2'], default='arm64',
                        help='Target slices; the pinned build compiler itself runs on arm64')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/engines/shioridll-nim')
    parser.add_argument('--archive', type=Path, help='Offline pinned shioridll archive')
    parser.add_argument('--compiler-archive', type=Path, help='Offline pinned official Nim archive')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('This pinned compiler package supports macOS arm64 only.')
    pin = json.loads((HERE / 'UPSTREAM.json').read_text())
    architectures = ['arm64', 'x86_64'] if args.arch == 'universal2' else [args.arch]
    sdk = subprocess.check_output(['/usr/bin/xcrun', '--show-sdk-path'], text=True).strip()
    clang_version = subprocess.check_output(['/usr/bin/clang', '--version'], text=True).splitlines()[0]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-nim-shiori-build-') as tmp:
        temporary = Path(tmp).resolve()
        source, compiler = temporary / 'source', temporary / 'compiler'
        extract(pin['shioridll'], source, args.archive)
        extract(pin['nim'], compiler, args.compiler_archive)
        version = subprocess.check_output([str(compiler / 'bin/nim'), '--version'], text=True)
        if pin['nim']['version'] not in version or pin['nim']['revision'] not in version:
            raise ValueError('Nim compiler version/revision mismatch')
        # Keep exact upstream sample bytes: patch only its imported DLL boundary.
        basic_hash = hashlib.sha256((source / 'example/basic.nim').read_bytes()).hexdigest()
        patch_interface(source / 'shioridll.nim')
        for name, example in [('upstream-basic', source / 'example/basic.nim'),
                              ('nimshiori', HERE / 'example/japanese.nim')]:
            library = output / ('lib' + name + '.dylib')
            slices = []
            for architecture in architectures:
                thin = temporary / (name + '-' + architecture + '.dylib')
                target_cpu = 'amd64' if architecture == 'x86_64' else 'arm64'
                subprocess.run([str(compiler / 'bin/nim'), 'c', '--app:lib', '--cc:clang',
                                '--clang.exe:/usr/bin/clang', '--clang.linkerexe:/usr/bin/clang',
                                '--os:macosx', '--cpu:' + target_cpu,
                                '--mm:arc', '--threads:on', '--tlsEmulation:off',
                                '--skipUserCfg:on', '--skipParentCfg:on', '--skipProjCfg:on',
                                '-d:release', '--passC:-arch', '--passC:' + architecture,
                                '--passL:-arch', '--passL:' + architecture,
                                '--passL:-Wl,-install_name,@rpath/' + library.name,
                                '--passC:-mmacosx-version-min=13.0', '--passL:-mmacosx-version-min=13.0',
                                '--path:' + str(source),
                                '--nimcache:' + str(temporary / ('cache-' + name + '-' + architecture)),
                                '--out:' + str(thin), str(example)], check=True, timeout=120,
                               env={**os.environ, 'NIMBLE_DIR': str(temporary / 'nimble'), 'SDKROOT': sdk})
                actual = subprocess.check_output(['/usr/bin/lipo', '-archs', str(thin)], text=True).split()
                if actual != [architecture]: raise ValueError('Unexpected Nim output slices: ' + ', '.join(actual))
                slices.append(thin)
            if len(slices) == 1: shutil.copyfile(slices[0], library)
            else: subprocess.run(['/usr/bin/lipo', '-create', *map(str, slices), '-output', str(library)], check=True)
            actual = subprocess.check_output(['/usr/bin/lipo', '-archs', str(library)], text=True).split()
            if set(actual) != set(architectures): raise ValueError('Missing target slices: ' + ', '.join(actual))
            library.with_suffix('.dylib.plist').write_bytes(plistlib.dumps({'OurinShioriABI': pin['abi']}))
        shutil.copyfile(compiler / pin['nim']['license_file'], output / 'LICENSE.Nim.txt')
        shutil.copyfile(source / 'shioridll.nim', output / 'shioridll.patched.nim')
        shutil.copyfile(source / 'Readme.md', output / 'README.upstream-shioridll.md')
        shutil.copyfile(source / 'shioridll.nimble', output / 'shioridll.nimble')
        shutil.copyfile(source / 'example/basic.nim', output / 'basic.upstream.nim')
        shutil.copyfile(HERE / 'UPSTREAM.json', output / 'UPSTREAM.json')
        (output / 'BUILD.json').write_text(json.dumps({
            'compiler': version.strip(), 'upstream_example_sha256': basic_hash,
            'shioridll_revision': pin['shioridll']['revision'], 'abi': pin['abi'],
            'architecture': args.arch, 'slices': architectures, 'builder_architecture': platform.machine(),
            'sdk_path': sdk, 'clang': clang_version, 'minimum_macos': '13.0', 'external_nimble_dependencies': [],
            'memory_manager': 'arc', 'threads': True, 'tls_emulation': False,
        }, indent=2) + '\n')
        (output / 'NOTICE.shioridll.txt').write_text(
            'shioridll by Narazaka; fixed revision ' + pin['shioridll']['revision'] + '\n'
            'Upstream declares MIT in shioridll.nim and shioridll.nimble.\n'
            'License reference: ' + pin['shioridll']['license_reference'] + '\n'
            'The reference website was unavailable during integration; retained upstream declarations\n'
            'are not a verified copy of its linked full license text. Review before redistribution.\n'
            'Altered POSIX interface: malloc/free exported buffers, cint load/unload, retained response string.\n')
    print('Built actual Nim SHIORI modules: ' + str(output))


if __name__ == '__main__':
    main()
