#!/usr/bin/env python3
"""Stage pinned phiori's actual Python engine for a POSIX SHIOLINK host."""
import argparse, hashlib, json, shutil, subprocess, sys, tarfile, tempfile, urllib.request
from pathlib import Path, PurePosixPath
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python',type=Path,default=Path('/opt/homebrew/bin/python3.14'))
    parser.add_argument('--archive',type=Path)
    parser.add_argument('--output',type=Path,default=ROOT/'build/engines/phiori')
    args=parser.parse_args();pin=json.loads((HERE/'UPSTREAM.json').read_text())
    version=subprocess.check_output([str(args.python),'-I','-c','import platform; print(platform.python_version())'],text=True).strip()
    if version != pin['python_version']: raise ValueError('Python version differs from tested pin: '+version)
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-phiori-build-') as temp:
        temp=Path(temp);archive=args.archive or temp/'source.tar.gz'
        if args.archive is None:
            with urllib.request.urlopen(pin['url'],timeout=60) as response: data=response.read(16*1024*1024+1)
            if len(data)>16*1024*1024: raise ValueError('archive too large')
            archive.write_bytes(data)
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=pin['sha256']: raise ValueError('archive checksum mismatch')
        source=temp/'source';source.mkdir();total=0
        with tarfile.open(archive) as tar:
            for member in tar:
                parts=PurePosixPath(member.name).parts
                if member.name.startswith('/') or '..' in parts or member.issym() or member.islnk(): raise ValueError('unsafe archive')
                if len(parts)<2: continue
                dest=source.joinpath(*parts[1:])
                if member.isdir(): dest.mkdir(parents=True,exist_ok=True)
                elif member.isfile():
                    total+=member.size
                    if total>64*1024*1024: raise ValueError('expanded archive too large')
                    dest.parent.mkdir(parents=True,exist_ok=True)
                    with tar.extractfile(member) as src,dest.open('wb') as out: shutil.copyfileobj(src,out)
                else: raise ValueError('unsupported archive entry')
        sample=output/'upstream-sample'
        if sample.exists(): shutil.rmtree(sample)
        sample.mkdir()
        shutil.copytree(source/'phiori',sample/'phiori')
        for name in ('example.py','config.txt','resource.txt','words.dic'): shutil.copyfile(source/name,sample/name)
        # Without ownerghostname (failed startup / EOF), unload must clear temp.
        module=sample/'phiori/__init__.py';body=module.read_text();needle='del personae[persona]'
        if body.count(needle)!=1: raise ValueError('upstream unload patch changed')
        module.write_text(body.replace(needle,'del personae[persona or "temp"]'))
        shutil.copyfile(HERE/'host.py',output/'phiori-shiolink.py')
        for name in ('LICENSE.MIT.txt','LICENSE.LGPL3.txt','COPYING.txt','README.md'): shutil.copyfile(source/name,output/('upstream-'+name))
        shutil.copyfile(HERE/'UPSTREAM.json',output/'UPSTREAM.json')
        (output/'BUILD.json').write_text(json.dumps({'python':str(args.python.resolve()),'version':version,'example_sha256':hashlib.sha256((source/'example.py').read_bytes()).hexdigest(),'runtime':'external Python; stdlib only','patch':'unload temporary persona when no owner notification arrived'},indent=2)+'\n')
    print('Staged actual phiori Python engine: '+str(output))
if __name__=='__main__':main()
