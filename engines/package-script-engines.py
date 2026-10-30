#!/usr/bin/env python3
"""Embed real JS/Ruby/Python SHIORI engines and their relocatable runtimes.

This is a build-time operation. The resulting app neither invokes npm/gem nor
uses a Homebrew executable or dylib when a ghost starts.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

from macho_bundle import is_macho, relocate_tree, stage_executable

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def run(args, **kwargs):
    return subprocess.check_output([str(x) for x in args], text=True, **kwargs).strip()


def copy_tree(source, destination, ignored=()):
    shutil.copytree(source, destination, dirs_exist_ok=True, symlinks=False,
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '*.dSYM', '*.o', '*.a', *ignored))


def launcher(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('#!/bin/sh\nset -eu\nOURIN_ENGINE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"\n'
                    'if [ "${OURIN_VERIFY_DYLD:-}" = 1 ]; then export DYLD_PRINT_LIBRARIES=1; fi\n' + body)
    path.chmod(0o755)


def record_runtime(directory, version, source):
    files = []
    for path in sorted(directory.rglob('*')):
        if path.is_file() and path.name != 'RUNTIME.json':
            if is_macho(path):
                subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(path)],
                               check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            files.append({'path': str(path.relative_to(directory)),
                          'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    (directory / 'RUNTIME.json').write_text(json.dumps({
        'version': version, 'source_executable_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'files': files,
    }, indent=2) + '\n')


def runtime_platform(directory):
    binaries = [path for path in directory.rglob('*') if is_macho(path)]
    commands = run(['/usr/bin/otool', '-l', *binaries])
    minimums = re.findall(r'\bminos (\d+(?:\.\d+)*)', commands)
    minimum = max(minimums, key=lambda value: tuple(int(part) for part in value.split('.')))
    executable = next((directory / 'bin' / name for name in ('node', 'ruby', 'python3')
                       if (directory / 'bin' / name).is_file()))
    return {'architectures': run(['/usr/bin/lipo', '-archs', executable]).split(),
            'minimumOSVersion': minimum}


def prepare_node(source, destination):
    source = source.resolve(strict=True)
    target = destination / 'node'
    stage_executable(source, target / 'bin/node', target / 'lib')
    license_file = source.parent.parent / 'LICENSE'
    if not license_file.is_file():
        raise ValueError('Node distribution LICENSE (including dependency notices) was not found')
    shutil.copyfile(license_file, target / 'LICENSE.Node.txt')
    record_runtime(target, run([source, '--version']), source)


def prepare_python(source, destination):
    source = source.resolve(strict=True)
    config = json.loads(run([source, '-I', '-c',
        'import json,sys,sysconfig;print(json.dumps(dict(version=sys.version.split()[0],'
        'stdlib=sysconfig.get_path("stdlib"),prefix=sys.base_prefix)))']))
    target = destination / 'python'
    framework_main = Path(config['prefix']) / 'Resources/Python.app/Contents/MacOS/Python'
    if framework_main.is_file():
        source = framework_main
    stdlib = Path(config['stdlib'])
    copy_tree(stdlib, target / 'lib' / stdlib.name, ignored=('site-packages', 'test', 'tests', 'idlelib', 'ensurepip', 'turtledemo'))
    # Homebrew's sitecustomize installs a machine-specific site-packages path.
    # Omit that distributor hook in this independent, isolated app runtime.
    site_hook = target / 'lib' / stdlib.name / 'sitecustomize.py'
    site_hook.unlink(missing_ok=True)
    stage_executable(source, target / 'bin/python3', target / 'lib')
    relocate_tree(target, target / 'lib')
    # A first pass can introduce a dependency whose destination was already in
    # the initial work queue. Normalize its final install ID after all copies.
    relocate_tree(target, target / 'lib')
    license_file = stdlib / 'LICENSE.txt'
    if not license_file.is_file():
        raise ValueError('Python standard-library LICENSE.txt was not found')
    shutil.copyfile(license_file, target / 'LICENSE.Python.txt')
    record_runtime(target, config['version'], source)


def prepare_ruby(source, destination):
    source = source.resolve(strict=True)
    config = json.loads(run([source, '-rjson', '-rrbconfig', '-e',
        'puts JSON.dump({version:RUBY_VERSION,prefix:RbConfig::CONFIG["prefix"],'
        'rubylibprefix:RbConfig::CONFIG["rubylibprefix"]})']))
    target = destination / 'ruby'
    copy_tree(Path(config['rubylibprefix']), target / 'lib/ruby')
    stage_executable(source, target / 'bin/ruby', target / 'lib')
    relocate_tree(target, target / 'lib')
    relocate_tree(target, target / 'lib')
    for name in ('COPYING', 'COPYING.ja'):
        shutil.copyfile(Path(config['prefix']) / name, target / ('LICENSE.Ruby.' + name))
    record_runtime(target, config['version'], source)


def extract_gem(archive, destination):
    """Extract the data payload of a hash-verified pure Ruby gem, without hooks."""
    with tarfile.open(archive) as package:
        payload = package.extractfile('data.tar.gz')
        if payload is None:
            raise ValueError('Ruby gem lacks its data payload')
        with tarfile.open(fileobj=payload, mode='r:gz') as data:
            total = 0
            for member in data:
                parts = PurePosixPath(member.name).parts
                if member.name.startswith('/') or '..' in parts or member.issym() or member.islnk():
                    raise ValueError('unsafe gem member')
                path = destination.joinpath(*parts)
                if member.isdir():
                    path.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    total += member.size
                    if total > 16 * 1024 * 1024:
                        raise ValueError('Ruby gem expanded size exceeded limit')
                    path.parent.mkdir(parents=True, exist_ok=True)
                    with data.extractfile(member) as src, path.open('wb') as out:
                        shutil.copyfileobj(src, out)
                else:
                    raise ValueError('unsupported Ruby gem member')


def prepare_gems(destination, cache):
    pins = json.loads((HERE / 'miyojs/RUBY_GEMS.json').read_text())
    cache.mkdir(parents=True, exist_ok=True)
    directories = []
    for name, pin in pins.items():
        archive = cache / (name + '-' + pin['version'] + '.gem')
        if not archive.is_file():
            with urllib.request.urlopen(pin['url'], timeout=60) as stream:
                data = stream.read(16 * 1024 * 1024 + 1)
            if len(data) > 16 * 1024 * 1024:
                raise ValueError('Ruby gem download size exceeded limit')
            archive.write_bytes(data)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != pin['sha256']:
            raise ValueError('Ruby gem SHA256 mismatch: ' + name)
        directory = destination / 'gems' / (name + '-' + pin['version'])
        extract_gem(archive, directory)
        directories.append(directory)
    shutil.copyfile(HERE / 'miyojs/RUBY_GEMS.json', destination / 'GEMS.json')
    return directories


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', required=True, type=Path)
    parser.add_argument('--node', type=Path, default=Path(shutil.which('node') or '/opt/homebrew/bin/node'))
    parser.add_argument('--ruby', type=Path, default=Path('/opt/homebrew/bin/ruby'))
    parser.add_argument('--python', type=Path, default=Path('/opt/homebrew/bin/python3.14'))
    parser.add_argument('--cache', type=Path, default=ROOT / 'build/deps/script-engines')
    args = parser.parse_args()
    destination = args.destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    cache = args.cache.resolve()
    products = ROOT / 'build/engines/miyojs'
    if not (products / 'BUILD.json').is_file() or (products / 'package-lock.json').read_bytes() != (HERE / 'miyojs/package-lock.json').read_bytes():
        subprocess.run([sys.executable, HERE / 'miyojs/build.py', '--node', args.node], check=True, timeout=240)
    with tempfile.TemporaryDirectory(prefix='ourin-script-engines-', dir=destination.parent) as temp:
        work = Path(temp)
        runtimes = work / 'script-runtimes'
        prepare_node(args.node, runtimes)
        prepare_python(args.python, runtimes)
        prepare_ruby(args.ruby, runtimes)
        for name in ('miyojs', 'sanajk', 'sana', 'phiori'):
            (work / name).mkdir()
        for name in ('miyojs', 'sanajk'):
            npm = work / name / 'packages'
            copy_tree(products / 'node_modules', npm / 'node_modules')
            copy_tree(products / 'licenses', npm / 'licenses')
            shutil.copyfile(HERE / 'miyojs/package-lock.json', npm / 'package-lock.json')
            shutil.copyfile(products / 'BUILD.json', npm / 'BUILD.json')
            copy_tree(runtimes / 'node', work / name / 'runtime')
        copy_tree(runtimes / 'python', work / 'phiori/runtime')
        copy_tree(runtimes / 'ruby', work / 'sana/runtime')
        launcher(work / 'miyojs/bin/miyojs',
            'exec "$OURIN_ENGINE_DIR/runtime/bin/node" '
            '"$OURIN_ENGINE_DIR/host.js" "$@"\n')
        shutil.copyfile(HERE / 'miyojs/host.js', work / 'miyojs/host.js')
        shutil.copyfile(HERE / 'miyojs/entry-selection.js', work / 'miyojs/entry-selection.js')
        launcher(work / 'sanajk/bin/sanajk',
            'export NODE_PATH="$OURIN_ENGINE_DIR/packages/node_modules"\n'
            'exec "$OURIN_ENGINE_DIR/runtime/bin/node" "$OURIN_ENGINE_DIR/entry.js" "$@"\n')
        shutil.copyfile(HERE / 'miyojs/sanajk-entry.js', work / 'sanajk/entry.js')
        shutil.copyfile(HERE / 'miyojs/entry-selection.js', work / 'sanajk/entry-selection.js')
        gem_dirs = prepare_gems(work / 'sana', cache / 'gems')
        ruby_paths = ':'.join('$OURIN_ENGINE_DIR/gems/' + d.name + '/lib' for d in gem_dirs)
        ruby_library = Path(run([args.ruby, '-rrbconfig', '-e', 'puts RbConfig::CONFIG["rubylibdir"]'])).name
        ruby_arch = Path(run([args.ruby, '-rrbconfig', '-e', 'puts RbConfig::CONFIG["rubyarchdir"]'])).name
        ruby_paths += ':$OURIN_ENGINE_DIR/runtime/lib/ruby/' + ruby_library
        ruby_paths += ':$OURIN_ENGINE_DIR/runtime/lib/ruby/' + ruby_library + '/' + ruby_arch
        # RUBYLIB and GEM_PATH explicitly isolate the app from user-installed gems.
        launcher(work / 'sana/bin/sana',
            'export GEM_HOME="$OURIN_ENGINE_DIR/gems" GEM_PATH="$OURIN_ENGINE_DIR/gems"\n'
            'export RUBYLIB="' + ruby_paths + '"\n'
            'exec "$OURIN_ENGINE_DIR/runtime/bin/ruby" --disable-gems -r "$OURIN_ENGINE_DIR/io.rb" "$OURIN_ENGINE_DIR/entry.rb" "$@"\n')
        shutil.copyfile(HERE / 'miyojs/sana-entry.rb', work / 'sana/entry.rb')
        (work / 'sana/io.rb').write_text(
            '$LOAD_PATH.replace(ENV.fetch("RUBYLIB").split(File::PATH_SEPARATOR))\n'
            '$stdout.sync = true\n$stdin.set_encoding("UTF-8")\n')
        phiori_products = ROOT / 'build/engines/phiori'
        if not (phiori_products / 'phiori-shiolink.py').is_file():
            subprocess.run([sys.executable, HERE / 'phiori/build.py', '--python', args.python], check=True, timeout=180)
        copy_tree(phiori_products / 'upstream-sample/phiori', work / 'phiori/python/phiori')
        shutil.copyfile(phiori_products / 'phiori-shiolink.py', work / 'phiori/host.py')
        for name in ('upstream-LICENSE.MIT.txt', 'upstream-LICENSE.LGPL3.txt', 'upstream-COPYING.txt', 'UPSTREAM.json'):
            shutil.copyfile(phiori_products / name, work / 'phiori' / name)
        launcher(work / 'phiori/bin/phiori',
            'export PYTHONHOME="$OURIN_ENGINE_DIR/runtime" PYTHONNOUSERSITE=1\n'
            'export PYTHONPATH="$OURIN_ENGINE_DIR/python"\n'
            'exec "$OURIN_ENGINE_DIR/runtime/bin/python3" -u "$OURIN_ENGINE_DIR/host.py"\n')
        for name in ('miyojs', 'sanajk', 'sana', 'phiori'):
            target = destination / name
            if target.exists():
                shutil.rmtree(target)
            shutil.move(work / name, target)
            shutil.copyfile(HERE / 'miyojs/README.md', target / 'README.Ourin-script-engines.md')
    manifest = [
        {'id': 'miyojs', 'kind': 'shiolink', 'executable': 'miyojs/bin/miyojs', 'arguments': [],
         'charset': 'UTF-8', 'moduleNames': ['miyo.dll', 'miyojs.dll', 'shiolink.dll'],
         'markers': ['miyo.yaml', 'node_modules/miyojs/package.json'],
         'commandHints': ['miyojs', 'miyo-shiolink'], 'licenseScope': 'redistributable'},
        {'id': 'sanajk', 'kind': 'shiolink', 'executable': 'sanajk/bin/sanajk', 'arguments': [],
         'charset': 'UTF-8', 'moduleNames': ['sanajk.dll', 'shiolink.dll'],
         'markers': ['node_modules/sanajk/package.json'], 'commandHints': ['sanajk'], 'licenseScope': 'redistributable'},
        {'id': 'sana', 'kind': 'shiolink', 'executable': 'sana/bin/sana', 'arguments': [],
         'charset': 'UTF-8', 'moduleNames': ['sana.dll', 'shiolink.dll'],
         'markers': ['main.rb'], 'commandHints': ['sana.rb', 'sana-shiolink'], 'licenseScope': 'redistributable'},
        {'id': 'phiori', 'kind': 'shiolink', 'executable': 'phiori/bin/phiori', 'arguments': [],
         'charset': 'UTF-8', 'moduleNames': ['phiori.dll'],
         'markers': ['phiori/__init__.py'], 'licenseScope': 'unconfirmed', 'launchTimeout': 60},
    ]
    for entry in manifest:
        entry.setdefault('launchTimeout', 30)
        entry.update(runtime_platform(destination / entry['id'] / 'runtime'))
    (destination / 'script-engines-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Embedded script SHIORI engines and runtimes: ' + str(destination))


if __name__ == '__main__':
    main()
