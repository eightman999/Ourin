#!/usr/bin/env python3
"""Build pinned, licensed nashi main core with a macOS platform boundary."""
import argparse
from concurrent.futures import ThreadPoolExecutor
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/engines/nashi')
    parser.add_argument('--cache', type=Path, default=ROOT / 'build/deps/nashi')
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--arch', choices=['arm64', 'x86_64', 'universal2'], default='universal2')
    parser.add_argument('--cxx', default='/Library/Developer/CommandLineTools/usr/bin/clang++')
    parser.add_argument('--sdk', type=Path, default=Path('/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk'))
    args = parser.parse_args()
    pin = json.loads((HERE / 'UPSTREAM.json').read_text())
    output, cache = args.output.resolve(), args.cache.resolve()
    output.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    archive = args.archive or cache / (pin['revision'] + '.tar.gz')
    if not archive.is_file():
        with urllib.request.urlopen(pin['url'], timeout=60) as response:
            data = response.read(32 * 1024 * 1024 + 1)
        if len(data) > 32 * 1024 * 1024:
            raise ValueError('nashi archive too large')
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != pin['sha256']:
        raise ValueError('nashi upstream archive SHA256 mismatch')
    with tempfile.TemporaryDirectory(prefix='ourin-nashi-build-') as temp:
        temp = Path(temp)
        source = temp / 'source'
        source.mkdir()
        with tarfile.open(archive) as tar:
            total = 0
            for member in tar:
                parts = PurePosixPath(member.name).parts
                if member.name.startswith('/') or '..' in parts or member.issym() or member.islnk():
                    raise ValueError('unsafe nashi archive member')
                if len(parts) < 2:
                    continue
                relative = PurePosixPath(*parts[1:])
                if not (str(relative).startswith(('shiori/', 'docs/', 'ui/samples/')) or str(relative) in {'LICENSE', 'README.md', 'VERSION', 'CHANGELOG.md'}):
                    continue
                target = source.joinpath(*relative.parts)
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    total += member.size
                    if total > 128 * 1024 * 1024:
                        raise ValueError('expanded nashi source too large')
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with tar.extractfile(member) as incoming, target.open('wb') as destination:
                        shutil.copyfileobj(incoming, destination)
                else:
                    raise ValueError('unsupported nashi archive member')
        src = source / 'shiori/src'
        # Both core and upstream SAORI logic are compiled byte-for-byte. The
        # Windows DLL entry and tiny CRT are replaced by Ourin/POSIX boundaries.
        names = ['json.cpp', 'program.cpp', 'interp.cpp', 'shiori.cpp', 'util.cpp', 'saori.cpp']
        hashes = {name: hashlib.sha256((src / name).read_bytes()).hexdigest() for name in names}
        architectures = ['arm64', 'x86_64'] if args.arch == 'universal2' else [args.arch]
        products = []
        processes = []
        for architecture in architectures:
            objects = temp / architecture
            objects.mkdir()
            flags = ['-std=c++14', '-O2', '-DNDEBUG', '-fPIC', '-mmacosx-version-min=13.0',
                     '-arch', architecture, '-isysroot', str(args.sdk), '-I' + str(HERE / 'compat'), '-I' + str(src)]
            inputs = [src / name for name in names] + [HERE / 'compat/windows.cpp', HERE / 'entry.cpp']

            def compile_one(item):
                index, path = item
                obj = objects / (str(index) + '.o')
                subprocess.run([args.cxx, *flags, '-c', str(path), '-o', str(obj)], check=True, timeout=120)
                return obj

            with ThreadPoolExecutor(max_workers=4) as pool:
                object_files = list(pool.map(compile_one, enumerate(inputs)))
            library = objects / 'libnashi.dylib'
            subprocess.run([args.cxx, *flags, '-dynamiclib', '-install_name', '@rpath/libnashi.dylib',
                            '-o', str(library), *[str(path) for path in object_files], '-liconv', '-lpthread'],
                           check=True, timeout=120)
            products.append(library)
            host_object = objects / 'shiolink.o'
            subprocess.run([args.cxx, *flags, '-c', str(HERE / 'shiolink.cpp'), '-o', str(host_object)], check=True, timeout=120)
            host = objects / 'nashi-shiolink'
            subprocess.run([args.cxx, *flags, '-o', str(host), *[str(path) for path in object_files[:-1]],
                            str(host_object), '-liconv', '-lpthread'], check=True, timeout=120)
            processes.append(host)
        module = output / 'libnashi.dylib'
        if len(products) == 2:
            subprocess.run(['/usr/bin/lipo', '-create', *[str(path) for path in products], '-output', str(module)], check=True)
        else:
            shutil.copyfile(products[0], module)
        actual = subprocess.check_output(['/usr/bin/lipo', '-archs', str(module)], text=True).split()
        if set(actual) != set(architectures):
            raise ValueError('nashi architecture slices do not match requested build')
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(module)], check=True)
        executable = output / 'nashi-shiolink'
        if len(processes) == 2:
            subprocess.run(['/usr/bin/lipo', '-create', *[str(path) for path in processes], '-output', str(executable)], check=True)
        else:
            shutil.copyfile(processes[0], executable)
        executable.chmod(0o755)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(executable)], check=True)
        (output / 'libnashi.dylib.plist').write_bytes(plistlib.dumps({'OurinShioriABI': 'ourin'}))
        for name in ('LICENSE', 'README.md', 'CHANGELOG.md', 'VERSION'):
            shutil.copyfile(source / name, output / ('upstream-' + name))
        samples = output / 'upstream-fixtures'
        shutil.copytree(source / 'shiori/test', samples, dirs_exist_ok=True)
        # Original behavior.js/lib/host.js expect this tree and filenames.
        test_tree = output / 'upstream-tests'
        shutil.copytree(source / 'shiori/test', test_tree / 'shiori/test', dirs_exist_ok=True)
        test_dist = test_tree / 'shiori/dist'
        test_dist.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(module, test_dist / 'nashi.dll')
        common = ['-std=c++14', '-O2', '-mmacosx-version-min=13.0', '-isysroot', str(args.sdk)]
        subprocess.run([args.cxx, *common, str(HERE / 'test_host.cpp'), '-o', str(test_dist / 'test_host.exe')], check=True, timeout=60)
        subprocess.run([args.cxx, *common, '-dynamiclib', '-I' + str(HERE / 'compat'),
                        str(source / 'shiori/test/saori/slow_saori.cpp'), str(HERE / 'compat/windows.cpp'),
                        '-o', str(test_dist / 'slow_saori.dll'), '-liconv'], check=True, timeout=60)
        shutil.copyfile(HERE / 'UPSTREAM.json', output / 'UPSTREAM.json')
        shutil.copyfile(HERE / 'README.md', output / 'README.Ourin.md')
        (output / 'BUILD.json').write_text(json.dumps({
            'version': pin['version'], 'architectures': architectures, 'minimumOSVersion': '13.0',
            'abi': 'SHIOLINK UTF-8 (one real Shiori per process)', 'standalone_test_dylib_abi': 'ourin', 'upstream_core_unchanged': hashes,
            'platform_changes': 'POSIX Win32 boundary, UTF-8 module paths, Ourin load/request/unload exports; original interpreter, JSON, protocol, persistence, SAORI and utility sources unchanged.',
            'upstream_reported_shiori_version': '1.0.0 (unchanged upstream metadata constant)',
        }, ensure_ascii=False, indent=2) + '\n')
    print('Built real nashi SHIORI ' + pin['version'] + ': ' + str(module))


if __name__ == '__main__':
    main()
