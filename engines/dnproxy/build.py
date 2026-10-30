#!/usr/bin/env python3
"""Build an explicit pure-managed D.N.Proxy SHIOLINK host, not Windows DLL exports."""
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


def extract(pin, destination, archive=None):
    if archive is None:
        archive=destination.parent/(destination.name+'.tar.gz')
        with urllib.request.urlopen(pin['url'],timeout=60) as stream: data=stream.read(16*1024*1024+1)
        if len(data)>16*1024*1024: raise ValueError('archive too large')
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=pin['sha256']: raise ValueError('upstream hash mismatch')
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


def prepare(work,dn,crawler):
    # Preserve the real interface and crawler sources. Port only Logger's Windows sink.
    (work/'Interfaces').mkdir(); (work/'Logger').mkdir(); (work/'Crawler').mkdir(); (work/'Probe').mkdir(); (work/'Host').mkdir()
    shutil.copyfile(dn/'src/Ukagaka.NET.Interfaces/Ukagaka.NET.Interfaces.cs',work/'Interfaces/Interfaces.cs')
    logger=(dn/'src/dnutil/Logger.cs').read_text(encoding='utf-8-sig')
    logger=logger.replace('using System.Windows.Forms;','')
    old='Logger.hlogrcvWnd = FindWindow(Logger.CLASSNAME_CHECKTOOL, null);'
    assert logger.count(old)==1
    logger=logger.replace(old,'if (OperatingSystem.IsWindows()) '+old)
    old='set { Logger.hlogrcvWnd = value; }'
    assert logger.count(old)==1
    logger=logger.replace(old,'set { if (value != IntPtr.Zero && !OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Win32 log receiver"); Logger.hlogrcvWnd = value; }')
    (work/'Logger/Logger.cs').write_text(logger)
    for source in (crawler/'ghost/master/src').rglob('*.cs'):
        target=work/'Crawler'/source.relative_to(crawler/'ghost/master/src')
        target.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(source,target)
    for source in (HERE/'host').glob('*.cs'): shutil.copyfile(source,work/'Host'/source.name)
    shutil.copyfile(HERE/'example/ProbeGhost.cs',work/'Probe/ProbeGhost.cs')
    names={'Interfaces':'Ukagaka.NET.Interfaces','Logger':'dnutil','Crawler':'CrawlerGhost','Probe':'DnProxyProbe','Host':'DnProxyHost'}
    refs={'Interfaces':[], 'Logger':[], 'Crawler':['Interfaces','Logger'], 'Probe':['Interfaces','Logger'], 'Host':['Interfaces','Crawler','Probe']}
    for folder,name in names.items():
        references=''.join(f'<ProjectReference Include="../{ref}/{ref}.csproj"/>' for ref in refs[folder])
        (work/folder/(folder+'.csproj')).write_text(f'<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework><AssemblyName>{name}</AssemblyName><ImplicitUsings>enable</ImplicitUsings><Nullable>disable</Nullable>'+('<OutputType>Exe</OutputType>' if folder=='Host' else '')+f'</PropertyGroup><ItemGroup>{references}'+('<PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="[4.14.0]"/><PackageReference Include="Microsoft.CodeAnalysis.VisualBasic" Version="[4.14.0]"/>' if folder=='Host' else '')+'</ItemGroup></Project>')
    return work/'Host/Host.csproj'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/engines/dnproxy')
    parser.add_argument('--archive',type=Path);parser.add_argument('--crawler-archive',type=Path)
    parser.add_argument('--dotnet',default='/opt/homebrew/bin/dotnet')
    parser.add_argument('--self-contained', action='store_true', help='Include the pinned .NET runtime in the apphost products')
    parser.add_argument('--runtime', choices=['osx-arm64', 'osx-x64'], default='osx-x64' if platform.machine() == 'x86_64' else 'osx-arm64')
    parser.add_argument('--nuget-cache', type=Path, default=ROOT/'build/deps/dotnet-nuget')
    args=parser.parse_args(); pin=json.loads((HERE/'UPSTREAM.json').read_text())
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-dnproxy-build-') as temporary:
        work=Path(temporary).resolve()
        env={**os.environ,'DOTNET_CLI_HOME':str(work/'cli-home'),'DOTNET_CLI_TELEMETRY_OPTOUT':'1','NUGET_PACKAGES':str(args.nuget_cache.resolve()),'DOTNET_SKIP_FIRST_TIME_EXPERIENCE':'1','DOTNET_GENERATE_ASPNET_CERTIFICATE':'false'}
        (work/'global.json').write_text(json.dumps({'sdk':{'version':pin['sdk'],'rollForward':'disable'}}))
        version=subprocess.check_output([args.dotnet,'--version'],cwd=work,env=env,text=True).strip()
        if version!=pin['sdk']: raise ValueError('wrong .NET SDK')
        dn,ghost=work/'upstream',work/'ghost'
        extract(pin['dnproxy'],dn,args.archive);extract(pin['crawler'],ghost,args.crawler_archive)
        project=prepare(work,dn,ghost)
        for folder in ['Interfaces','Logger','Crawler','Probe','Host']:
            shutil.copyfile(HERE/'locks'/(folder+('.'+args.runtime if args.self_contained else '')+'.packages.lock.json'),work/folder/'packages.lock.json')
        config=work/'NuGet.Config';config.write_text('<configuration><packageSources><clear/><add key="nuget.org" value="https://api.nuget.org/v3/index.json"/></packageSources></configuration>')
        runtime_args=['--runtime',args.runtime,'-p:SelfContained=true','-p:RuntimeFrameworkVersion=10.0.12'] if args.self_contained else []
        subprocess.run([args.dotnet,'restore',str(project),'--locked-mode','--configfile',str(config)]+runtime_args,cwd=work,env=env,check=True,timeout=300)
        subprocess.run([args.dotnet,'publish',str(project),'-c','Release','--no-restore','--self-contained',str(args.self_contained).lower(),'-o',str(output)]+runtime_args,cwd=work,env=env,check=True,timeout=300)
        shutil.copyfile(dn/'LICENSE',output/'LICENSE.DNProxy.CC0.txt')
        shutil.copyfile(ghost/'readme.txt',output/'LICENSE.Crawler.NYSDL.txt')
        shutil.copyfile(HERE/'UPSTREAM.json',output/'UPSTREAM.json')
        (output/'BUILD.json').write_text(json.dumps({'sdk':version,'target':'net10.0','self_contained':args.self_contained,'runtime':args.runtime if args.self_contained else None,'runtime_version':'10.0.12' if args.self_contained else None,'contract':'IShiori30 load/unload + public string request(string)','external_nuget_dependencies':pin['external_nuget_dependencies']},indent=2)+'\n')
        (output/'dnutil.Logger.ported.cs').write_text((work/'Logger/Logger.cs').read_text())
        hashes={str(file.relative_to(work/'Crawler')):hashlib.sha256(file.read_bytes()).hexdigest() for file in (work/'Crawler').rglob('*.cs')}
        (output/'CRAWLER_SOURCES.json').write_text(json.dumps(hashes,indent=2)+'\n')
        fixture=output/'upstream-crawler'
        shutil.copytree(ghost/'ghost/master/src',fixture/'src',dirs_exist_ok=True)
        shutil.copyfile(ghost/'ghost/master/dnproxy.ini',fixture/'dnproxy.ini')
        (output/'CRAWLER_INI.sha256').write_text(hashlib.sha256((fixture/'dnproxy.ini').read_bytes()).hexdigest()+'\n')
        for lock in (HERE/'locks').glob('*.json'): shutil.copyfile(lock,output/lock.name)
        notices=output/'NuGetNotices';notices.mkdir(exist_ok=True)
        dependencies=json.loads((HERE/'locks/Host.packages.lock.json').read_text())['dependencies']['net10.0']
        for name,info in dependencies.items():
            if info['type']=='Project': continue
            package=args.nuget_cache.resolve()/name.lower()/info['resolved']
            for file in package.iterdir():
                if file.is_file() and (file.suffix=='.nuspec' or any(word in file.name.lower() for word in ['license','notice','copying'])):
                    shutil.copyfile(file,notices/(name+'-'+file.name))
    print('Built real managed D.N.Proxy interface host: '+str(output/'DnProxyHost.dll'))

if __name__=='__main__':main()
