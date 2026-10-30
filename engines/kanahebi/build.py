#!/usr/bin/env python3
"""Build the pinned, real IronPython Kanahebi module as an optional local SHIOLINK host."""
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
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]


def extract(archive,destination):
    destination.mkdir()
    with tarfile.open(archive) as tar:
        total=0
        for item in tar.getmembers():
            parts=PurePosixPath(item.name).parts
            if item.name.startswith('/') or '..' in parts or item.issym() or item.islnk(): raise ValueError('unsafe archive entry')
            if len(parts)<2: continue
            target=destination.joinpath(*parts[1:])
            if item.isdir(): target.mkdir(parents=True,exist_ok=True)
            elif item.isfile():
                total+=item.size
                if total>64*1024*1024: raise ValueError('expanded archive too large')
                target.parent.mkdir(parents=True,exist_ok=True)
                with tar.extractfile(item) as src,target.open('wb') as out: shutil.copyfileobj(src,out)
            else: raise ValueError('unsupported archive entry')


def prepare(work,source,pin):
    # Preserve the actual engine lifecycle/script invocation byte for byte.
    shutil.copyfile(source/'Kanahebi/ModuleMain.cs',work/'ModuleMain.cs')
    interface=(source/'Kanahebi/UkastreamInterface.cs').read_text(encoding='utf-8-sig')
    old='using System.Net.Configuration;'
    assert interface.count(old)==1
    interface=interface.replace(old,'')
    # Retain the real ModuleMode enum and legacy helper methods; remove only
    # the BRIDGE/1.0 executable entrypoint, replaced by the SHIOLINK host.
    marker='\t\t/// <summary>\n\t\t/// リクエスト処理'
    assert interface.count(marker)==1
    interface=interface[:interface.index(marker)]+'\t}\n}\n'
    (work/'UkastreamInterface.cs').write_text(interface)
    shutil.copyfile(HERE/'host/Program.cs',work/'Program.cs')
    project=work/'KanahebiHost.csproj'
    project.write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType>'
        '<TargetFramework>net10.0</TargetFramework><AssemblyName>KanahebiHost</AssemblyName>'
        '<ImplicitUsings>enable</ImplicitUsings><Nullable>disable</Nullable></PropertyGroup>'
        '<ItemGroup><PackageReference Include="IronPython" Version="[3.4.2]"/><PackageReference Include="IronPython.StdLib" Version="[3.4.2]"/></ItemGroup></Project>')
    return project


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/engines/kanahebi')
    parser.add_argument('--archive',type=Path)
    parser.add_argument('--dotnet',default='/opt/homebrew/bin/dotnet')
    parser.add_argument('--self-contained', action='store_true', help='Include the pinned .NET runtime in the apphost products')
    parser.add_argument('--runtime', choices=['osx-arm64', 'osx-x64'], default='osx-x64' if platform.machine() == 'x86_64' else 'osx-arm64')
    parser.add_argument('--nuget-cache', type=Path, default=ROOT/'build/deps/dotnet-nuget')
    args=parser.parse_args();pin=json.loads((HERE/'UPSTREAM.json').read_text())
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-kanahebi-build-') as temporary:
        work=Path(temporary).resolve()
        env={**os.environ,'DOTNET_CLI_HOME':str(work/'cli-home'),'DOTNET_CLI_TELEMETRY_OPTOUT':'1','NUGET_PACKAGES':str(args.nuget_cache.resolve()),'DOTNET_SKIP_FIRST_TIME_EXPERIENCE':'1','DOTNET_GENERATE_ASPNET_CERTIFICATE':'false'}
        (work/'global.json').write_text(json.dumps({'sdk':{'version':pin['sdk'],'rollForward':'disable'}}))
        version=subprocess.check_output([args.dotnet,'--version'],cwd=work,env=env,text=True).strip()
        if version!=pin['sdk']: raise ValueError('wrong .NET SDK')
        archive=args.archive
        if archive is None:
            archive=work/'upstream.tar.gz'
            with urllib.request.urlopen(pin['url'],timeout=60) as stream: data=stream.read(16*1024*1024+1)
            if len(data)>16*1024*1024: raise ValueError('archive too large')
            archive.write_bytes(data)
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=pin['sha256']: raise ValueError('upstream hash mismatch')
        source=work/'source';extract(archive,source)
        sample=source/'Sample/main.py'
        if hashlib.sha256(sample.read_bytes()).hexdigest()!=pin['upstream_sample_sha256']: raise ValueError('sample hash mismatch')
        project=prepare(work,source,pin)
        # Prevent archived upstream source from being implicitly compiled twice.
        project.write_text(project.read_text().replace('<ItemGroup>','<ItemGroup><Compile Remove="source/**/*.cs"/>',1))
        shutil.copyfile(HERE/'locks'/('packages.'+args.runtime+'.lock.json' if args.self_contained else 'packages.lock.json'),work/'packages.lock.json')
        config=work/'NuGet.Config';config.write_text('<configuration><packageSources><clear/><add key="nuget.org" value="https://api.nuget.org/v3/index.json"/></packageSources></configuration>')
        runtime_args=['--runtime',args.runtime,'-p:SelfContained=true','-p:RuntimeFrameworkVersion=10.0.12'] if args.self_contained else []
        subprocess.run([args.dotnet,'restore',str(project),'--locked-mode','--configfile',str(config)]+runtime_args,cwd=work,env=env,check=True,timeout=300)
        subprocess.run([args.dotnet,'publish',str(project),'-c','Release','--no-restore','--self-contained',str(args.self_contained).lower(),'-o',str(output)]+runtime_args,cwd=work,env=env,check=True,timeout=300)
        shutil.copytree(args.nuget_cache.resolve()/'ironpython.stdlib/3.4.2/content/lib',output/'Lib',dirs_exist_ok=True)
        shutil.copyfile(sample,output/'upstream-sample-main.py')
        shutil.copyfile(HERE/'UPSTREAM.json',output/'UPSTREAM.json')
        shutil.copyfile(HERE/'locks'/('packages.'+args.runtime+'.lock.json' if args.self_contained else 'packages.lock.json'),output/'packages.lock.json')
        shutil.copyfile(source/'readme.md',output/'README.upstream.md')
        notices=output/'NuGetNotices';notices.mkdir(exist_ok=True)
        deps=json.loads((HERE/'locks/packages.lock.json').read_text())['dependencies'][pin['target_framework']]
        for name,info in deps.items():
            package=args.nuget_cache.resolve()/name.lower()/info['resolved']
            for file in package.iterdir():
                if file.is_file() and (file.suffix=='.nuspec' or any(word in file.name.lower() for word in ['license','notice','copying'])):
                    shutil.copyfile(file,notices/(name+'-'+file.name))
        for item in pin['additional_license_files']:
            license_file=HERE/item['path']
            if hashlib.sha256(license_file.read_bytes()).hexdigest()!=item['sha256']: raise ValueError('license hash mismatch')
            shutil.copyfile(license_file,notices/license_file.name)
        (output/'LOCAL_BUILD_ONLY.txt').write_text('Pinned Kanahebi upstream has no project LICENSE. Locally generated engine plug-in only; no public redistribution permission is established. Dependency notices are separate.\n')
        (output/'BUILD.json').write_text(json.dumps({'sdk':version,'framework':pin['target_framework'],'module_main_sha256':hashlib.sha256((work/'ModuleMain.cs').read_bytes()).hexdigest(),'self_contained':args.self_contained,'runtime':args.runtime if args.self_contained else None,'runtime_version':'10.0.12' if args.self_contained else None},indent=2)+'\n')
    print('Built optional local real IronPython Kanahebi host: '+str(output/'KanahebiHost.dll'))

if __name__=='__main__': main()
