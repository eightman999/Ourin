#!/usr/bin/env python3
"""Build a native .plugin around an unmodified user-owned plugin directory.
No downloads; no third-party content is added to the repository.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid


def read_descriptor(path):
    raw = path.read_bytes()
    try:
        text = raw.decode('utf-8-sig')
    except UnicodeDecodeError:
        text = raw.decode('cp932')
    return {line.split(',', 1)[0].strip().lower(): line.split(',', 1)[1].strip()
            for line in text.splitlines() if ',' in line and not line.lstrip().startswith('//')}


def contained(root, path):
    path = path.resolve()
    if path != root and root not in path.parents:
        raise ValueError('input path escapes source directory')
    return path


def generate(args):
    source = args.source.resolve()
    output = args.output.absolute()
    if output.exists() or output.is_symlink():
        raise ValueError('output already exists; choose a new package path')
    if output.suffix != '.plugin':
        raise ValueError('output must end in .plugin')
    if source == output.resolve() or source in output.resolve().parents:
        raise ValueError('output must not be inside source')
    files = list(source.rglob('*'))
    if len(files) > 20000 or any(p.is_symlink() for p in files):
        raise ValueError('source contains symlinks or too many entries')
    if sum(p.stat().st_size for p in files if p.is_file()) > 512 * 1024 * 1024:
        raise ValueError('source exceeds 512 MiB')
    descriptor = read_descriptor(source / 'descript.txt')
    module = descriptor.get('filename', '').replace('\\', '/')
    config = contained(source, source / Path(module).with_suffix('.txt'))
    identifier = descriptor.get('id') or str(uuid.uuid5(uuid.NAMESPACE_URL, args.source_url or source.as_uri()))
    manifest = {'schema': 1, 'engine': args.engine, 'payload': 'payload',
                'source_url': args.source_url, 'plugin_id': identifier, 'saori_backends': {}}
    if args.engine == 'yaya':
        if not args.helper or not args.collector:
            raise ValueError('YAYA requires --helper and --collector')
        completed = subprocess.run([str(args.collector.resolve()), str(config), str(source)],
                                   capture_output=True, text=True, check=True, timeout=60)
        load = json.loads(completed.stdout)
        root = contained(source, Path(load['ghost_root']))
        for entry in load.get('dic_entries', []):
            contained(root, root / entry['path'])
        if not load.get('dic_entries'):
            raise ValueError('no YAYA dictionaries resolved')
        load['ghost_root'] = str(Path('payload') / root.relative_to(source))
        # Ourin JSON persistence must not overwrite original YAYA text/encrypted saves.
        load['save_file'] = 'state/yaya-variables.json'
        manifest.update(load=load, helper='yaya_core', config=str(config.relative_to(source)))
    else:
        if not args.engine_library:
            raise ValueError('Akari requires --engine-library')
        manifest.update(engine_library='libakari.dylib', config=str(Path(module).with_suffix('.txt')))
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.ourin-plugin-', dir=output.parent))
    try:
        resources = stage / 'Contents/Resources'
        executable = stage / 'Contents/MacOS/OurinPluginAdapter'
        resources.mkdir(parents=True)
        (resources / 'state').mkdir()
        executable.parent.mkdir(parents=True)
        shutil.copytree(source, resources / 'payload')
        shutil.copy2(args.adapter, executable)
        if args.engine == 'yaya':
            shutil.copy2(args.helper, resources / 'yaya_core')
        else:
            shutil.copy2(args.engine_library, resources / 'libakari.dylib')
            shutil.copy2(args.adapter.parent / 'akari_helper', resources / 'akari_helper')
        for value in args.saori_backend:
            key, separator, path = value.partition('=')
            if not separator:
                raise ValueError('backend syntax is module.dll=/path/to/trusted.dylib')
            key = key.replace('\\', '/').lower()
            while key.startswith('./'):
                key = key[2:]
            target = 'backends/' + hashlib.sha256(key.encode()).hexdigest()[:16] + '.dylib'
            (resources / 'backends').mkdir(exist_ok=True)
            shutil.copy2(path, resources / target)
            manifest['saori_backends'][key] = target
        (resources / 'adapter.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        # Preserve the source descriptor too; metadata for the native package lives in Info.plist.
        shutil.copy2(source / 'descript.txt', resources / 'descript.txt')
        info = {'CFBundleIdentifier': 'com.furinlab.ourin.port.' + hashlib.sha256(identifier.encode()).hexdigest()[:24],
                'CFBundleExecutable': executable.name, 'CFBundlePackageType': 'BNDL',
                'CFBundleName': descriptor.get('name', source.name), 'CFBundleVersion': '1',
                'OurinModuleABI': 'ourin', 'OurinPluginID': identifier, 'OurinPluginPortEngine': args.engine,
                'OurinPluginSourceURL': args.source_url or '', 'LSMinimumSystemVersion': '13.0'}
        (stage / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(stage)], check=True, capture_output=True)
        if output.exists():
            raise ValueError('output appeared during generation')
        stage.rename(output)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--engine', choices=['yaya', 'akari'], required=True)
    parser.add_argument('--adapter', type=Path, required=True)
    parser.add_argument('--helper', type=Path)
    parser.add_argument('--collector', type=Path)
    parser.add_argument('--engine-library', type=Path)
    parser.add_argument('--source-url')
    parser.add_argument('--saori-backend', action='append', default=[])
    args = parser.parse_args()
    try:
        print(generate(args))
    except (ValueError, OSError, subprocess.SubprocessError, KeyError) as error:
        parser.exit(1, f'Package generation failed: {error}\n')


if __name__ == '__main__':
    main()
