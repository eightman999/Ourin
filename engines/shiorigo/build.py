#!/usr/bin/env python3
"""Build real upstream Gohst callbacks and shiorigo behind a macOS SHIOLINK host."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def fetch(pin, directory, supplied=None):
    archive = supplied or directory.parent / (directory.name + '.tar.gz')
    if supplied is None:
        with urllib.request.urlopen(pin['url'], timeout=60) as stream:
            data = stream.read(32 * 1024 * 1024 + 1)
        if len(data) > 32 * 1024 * 1024:
            raise ValueError('archive too large')
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != pin['sha256']:
        raise ValueError('upstream SHA256 mismatch')
    directory.mkdir()
    with tarfile.open(archive) as tar:
        total = 0
        for member in tar.getmembers():
            parts = PurePosixPath(member.name).parts
            if member.name.startswith('/') or '..' in parts or member.issym() or member.islnk():
                raise ValueError('unsafe archive path')
            if len(parts) < 2:
                continue
            target = directory.joinpath(*parts[1:])
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                total += member.size
                if total > 128 * 1024 * 1024:
                    raise ValueError('expanded archive too large')
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, target.open('wb') as out:
                    shutil.copyfileobj(source, out)
            else:
                raise ValueError('unsupported archive member')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--go', type=Path, default=Path('/opt/homebrew/bin/go'))
    parser.add_argument('--output', type=Path, default=ROOT / 'build/engines/shiorigo')
    parser.add_argument('--shiorigo-archive', type=Path)
    parser.add_argument('--gohst-archive', type=Path)
    args = parser.parse_args()
    pin = json.loads((HERE / 'UPSTREAM.json').read_text())
    go = args.go.resolve()
    tool_env = {**os.environ, 'GOTOOLCHAIN': 'local', 'GOWORK': 'off', 'GOENV': 'off'}
    version = subprocess.check_output([str(go), 'version'], text=True, env=tool_env).strip()
    if version.split()[2] != pin['go']['version']:
        raise ValueError('Go version differs from fixed build tool version: ' + version)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-shiorigo-build-') as tmp:
        root = Path(tmp)
        shiorigo, gohst = root / 'shiorigo', root / 'gohst'
        fetch(pin['shiorigo'], shiorigo, args.shiorigo_archive)
        fetch(pin['gohst'], gohst, args.gohst_archive)
        # Compile only pure Go callbacks. The upstream Windows/cgo DLL entry,
        # win32file logger and third-party shell artwork are not part of this port.
        build = root / 'host'
        (build / 'internal/requesthandlers').mkdir(parents=True)
        handlers = gohst / pin['gohst']['compiled_path']
        shutil.copyfile(handlers, build / pin['gohst']['compiled_path'])
        shutil.copyfile(HERE / 'main.go', build / 'main.go')
        (build / 'shiorigo').mkdir()
        shutil.copyfile(shiorigo / 'shiori.go', build / 'shiorigo/shiori.go')
        (build / 'shiorigo/go.mod').write_text('module github.com/Narazaka/shiorigo\n\ngo 1.20\n')
        (build / 'go.mod').write_text('module github.com/kurousada/gohst\n\ngo 1.20\n\nrequire github.com/Narazaka/shiorigo v0.0.0\nreplace github.com/Narazaka/shiorigo => ./shiorigo\n')
        environment = {**tool_env, 'GOPROXY': 'off', 'GOSUMDB': 'off', 'CGO_ENABLED': '0',
                       'GOPATH': str(root / 'gopath'), 'GOCACHE': str(root / 'gocache')}
        subprocess.run([str(go), 'vet', '.'], cwd=build, env=environment, check=True, timeout=120)
        subprocess.run([str(go), 'build', '-mod=readonly', '-trimpath', '-o', str(output / 'gohst-shiolink'), '.'],
                       cwd=build, env=environment, check=True, timeout=120)
        modules = subprocess.check_output([str(go), 'list', '-m', 'all'], cwd=build, env=environment, text=True)
        goroot = Path(subprocess.check_output([str(go), 'env', 'GOROOT'], env=tool_env, text=True).strip())
        go_license = next((path for path in [goroot / 'LICENSE', goroot.parent / 'LICENSE'] if path.is_file()), None)
        if go_license is None:
            raise ValueError('Go distribution license was not found')
        shutil.copyfile(go_license, output / 'LICENSE.Go.txt')
        shutil.copyfile(gohst / pin['gohst']['license_file'], output / 'LICENSE.Gohst.md')
        shutil.copyfile(shiorigo / 'Readme.md', output / 'LICENSE.shiorigo-declaration.md')
        shutil.copyfile(handlers, output / 'requesthandlers.upstream.go')
        shutil.copyfile(shiorigo / 'shiori.go', output / 'shiori.upstream.go')
        shutil.copyfile(HERE / 'UPSTREAM.json', output / 'UPSTREAM.json')
        (output / 'BUILD.json').write_text(json.dumps({
            'compiler': version, 'compiler_executable_sha256': hashlib.sha256(go.read_bytes()).hexdigest(),
            'gohst_handler_sha256': hashlib.sha256(handlers.read_bytes()).hexdigest(),
            'shiorigo_parser_sha256': hashlib.sha256((shiorigo / 'shiori.go').read_bytes()).hexdigest(),
            'modules': modules.strip().splitlines(), 'transport': 'SHIOLINK UTF-8',
            'upstream_event_changes': False, 'cgo': False,
        }, indent=2) + '\n')
    print('Built real Gohst + shiorigo SHIOLINK host: ' + str(output / 'gohst-shiolink'))


if __name__ == '__main__':
    main()
