#!/usr/bin/env python3
"""Build pinned Rosalind's real C# scripting host; no global .NET configuration changes."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def extract(archive, destination):
    destination.mkdir()
    with tarfile.open(archive) as tar:
        total = 0
        for item in tar.getmembers():
            parts = PurePosixPath(item.name).parts
            if item.name.startswith('/') or '..' in parts or item.issym() or item.islnk():
                raise ValueError('unsafe Rosalind archive path')
            if len(parts) < 2:
                continue
            target = destination.joinpath(*parts[1:])
            if item.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif item.isfile():
                total += item.size
                if total > 64 * 1024 * 1024:
                    raise ValueError('expanded archive exceeds limit')
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(item) as src, target.open('wb') as out:
                    shutil.copyfileobj(src, out)
            else:
                raise ValueError('unsupported archive entry')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT/'build/engines/rosalind')
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--dotnet', default='/opt/homebrew/bin/dotnet')
    parser.add_argument('--self-contained', action='store_true', help='Include the pinned .NET runtime in the apphost products')
    parser.add_argument('--runtime', choices=['osx-arm64', 'osx-x64'], default='osx-x64' if platform.machine() == 'x86_64' else 'osx-arm64')
    parser.add_argument('--nuget-cache', type=Path, default=ROOT/'build/deps/dotnet-nuget')
    args = parser.parse_args()
    pin = json.loads((HERE/'UPSTREAM.json').read_text())
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-rosalind-build-') as tmp:
        work = Path(tmp).resolve()
        # Isolate SDK first-run state and NuGet cache; no user package sources or credentials.
        env = {**os.environ, 'DOTNET_CLI_HOME': str(work/'cli-home'),
               'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_SKIP_FIRST_TIME_EXPERIENCE': '1', 'DOTNET_GENERATE_ASPNET_CERTIFICATE': 'false',
               'NUGET_PACKAGES': str(args.nuget_cache.resolve())}
        (work/'global.json').write_text(json.dumps({'sdk': {'version': pin['sdk'], 'rollForward': 'disable'}}))
        version = subprocess.check_output([args.dotnet, '--version'], cwd=work, env=env, text=True).strip()
        if version != pin['sdk']:
            raise ValueError('Expected .NET SDK '+pin['sdk']+', found '+version)
        archive = args.archive
        if archive is None:
            archive = work/'upstream.tar.gz'
            with urllib.request.urlopen(pin['url'], timeout=60) as stream:
                data = stream.read(16 * 1024 * 1024 + 1)
            if len(data) > 16 * 1024 * 1024:
                raise ValueError('archive exceeds limit')
            archive.write_bytes(data)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != pin['sha256']:
            raise ValueError('Rosalind archive SHA256 mismatch')
        source = work/'source'
        extract(archive, source)
        subprocess.run(['patch', '-d', str(source), '-p1', '-i', str(HERE/'patches/001-posix-shiolink.patch')], check=True)
        for project, lock in [('Rosalind.Common', 'Common'), ('Rosalind.NET.CSharp', 'CSharp')]:
            shutil.copyfile(HERE/'locks'/(lock+('.'+args.runtime if args.self_contained else '')+'.packages.lock.json'), source/project/'packages.lock.json')
        config = work/'NuGet.Config'
        config.write_text('<configuration><packageSources><clear/><add key="nuget.org" value="https://api.nuget.org/v3/index.json"/></packageSources></configuration>')
        project = source/'Rosalind.NET.CSharp/Rosalind.NET.CSharp.csproj'
        runtime_args = ['--runtime', args.runtime, '-p:SelfContained=true', '-p:RuntimeFrameworkVersion=10.0.12'] if args.self_contained else []
        subprocess.run([args.dotnet, 'restore', str(project), '--locked-mode', '--configfile', str(config)]+runtime_args, cwd=work, env=env, check=True, timeout=300)
        subprocess.run([args.dotnet, 'publish', str(project), '-c', 'Release', '--no-restore', '--self-contained', str(args.self_contained).lower(), '-o', str(output)]+runtime_args, cwd=work, env=env, check=True, timeout=300)
        shutil.copyfile(source/'LICENSE', output/'LICENSE.Rosalind.txt')
        shutil.copyfile(source/'THIRD-PARTY-LIBRARIES.md', output/'THIRD-PARTY-LIBRARIES.upstream.md')
        shutil.copyfile(HERE/'UPSTREAM.json', output/'UPSTREAM.json')
        dependencies = {}
        for lock in (HERE/'locks').glob('*.json'):
            dependencies[lock.name] = json.loads(lock.read_text())
            shutil.copyfile(lock, output/lock.name)
        (output/'DEPENDENCIES.json').write_text(json.dumps(dependencies, indent=2)+'\n')
        notices = output/'NuGetNotices'
        notices.mkdir(exist_ok=True)
        for name, info in dependencies['CSharp.packages.lock.json']['dependencies'][pin['target_framework']].items():
            if info['type'] == 'Project':
                continue
            package = args.nuget_cache.resolve()/name.lower()/info['resolved']
            for file in package.iterdir():
                if file.is_file() and (file.suffix == '.nuspec' or any(word in file.name.lower() for word in ('license', 'notice'))):
                    shutil.copyfile(file, notices/(name+'-'+file.name))
        (output/'BUILD.json').write_text(json.dumps({'sdk': version, 'target_framework': pin['target_framework'], 'revision': pin['revision'], 'self_contained': args.self_contained, 'runtime': args.runtime if args.self_contained else None, 'runtime_version': '10.0.12' if args.self_contained else None}, indent=2)+'\n')
    print('Built real Rosalind C# host: '+str(output/'Rosalind.NET.CSharp.dll'))


if __name__ == '__main__':
    main()
