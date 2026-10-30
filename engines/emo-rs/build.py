#!/usr/bin/env python3
"""Build the pinned real emo-rs Rust/Lua engine, with a POSIX native ABI."""
import argparse, hashlib, json, os, plistlib, shutil, subprocess, tarfile, urllib.request
from pathlib import Path, PurePosixPath
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

def extract(pin, dest, cache):
    archive = cache / (pin['sha256'] + '.tar.gz')
    if not archive.exists():
        with urllib.request.urlopen(pin['url'], timeout=60) as response:
            content = response.read(32*1024*1024+1)
        if len(content) > 32*1024*1024: raise ValueError('archive too large')
        if hashlib.sha256(content).hexdigest() != pin['sha256']: raise ValueError('upstream checksum mismatch')
        archive.write_bytes(content)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != pin['sha256']: raise ValueError('cache checksum mismatch')
    if dest.exists(): shutil.rmtree(dest)
    dest.mkdir(parents=True)
    total = 0
    with tarfile.open(archive) as tar:
        for member in tar:
            parts = PurePosixPath(member.name).parts
            if member.name.startswith('/') or '..' in parts or member.issym() or member.islnk(): raise ValueError('unsafe archive')
            if len(parts)<2: continue
            target = dest.joinpath(*parts[1:])
            if member.isdir(): target.mkdir(parents=True,exist_ok=True)
            elif member.isfile():
                total += member.size
                if total>128*1024*1024: raise ValueError('expanded archive too large')
                target.parent.mkdir(parents=True,exist_ok=True)
                with tar.extractfile(member) as source, target.open('wb') as out: shutil.copyfileobj(source,out)
            else: raise ValueError('unsupported archive entry')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua', choices=['luajit52','lua54'],default='luajit52')
    args=parser.parse_args()
    suffix='' if args.lua=='luajit52' else '-lua54'
    output=ROOT/('build/engines/emo-rs'+suffix); cache=ROOT/('build/deps/emo-rs'+suffix)
    for directory in (output,cache): directory.mkdir(parents=True,exist_ok=True)
    pin=json.loads((HERE/'UPSTREAM.json').read_text()); source=cache/'source'
    extract(pin['emo'],source,cache)
    extract(pin['shiori3'],source/'third_party/shiori3',cache)
    for name in ('api.rs','lib.rs'):
        path=source/'third_party/shiori3/src'/name
        path.write_text(path.read_text()) # upstream crate uses CRLF; patch is LF
    subprocess.run(['patch','-d',str(source),'-p1','-i',str(HERE/'port.patch')],check=True)
    if args.lua=='lua54':
        manifest=source/'Cargo.toml'; text=manifest.read_text()
        if text.count('"luajit52"') != 1: raise ValueError('Lua feature patch mismatch')
        manifest.write_text(text.replace('"luajit52"','"lua54"')+
                            '\n[build-dependencies]\nlua-src = { version = "=546.0.2", features = ["ucid"] }\n')
    shutil.copyfile(HERE/'posix.rs',source/'src/posix.rs')
    shutil.copyfile(HERE/'posix_encoding.rs',source/'third_party/shiori3/src/posix_encoding.rs')
    lock=HERE/('Cargo.lock' if args.lua=='luajit52' else 'Cargo.lua54.lock')
    shutil.copyfile(lock,source/'Cargo.lock')
    env={**os.environ,'CARGO_TARGET_DIR':str(cache/'target')}
    subprocess.run(['cargo','build','--release','--locked','--manifest-path',str(source/'Cargo.toml')],env=env,check=True)
    library=output/'libemo.dylib'
    shutil.copyfile(cache/'target/release/libemo.dylib',library)
    library.with_suffix('.dylib.plist').write_bytes(plistlib.dumps({'OurinShioriABI':'ukagaka-long'}))
    example=output/'upstream-script'
    if example.exists(): shutil.rmtree(example)
    shutil.copytree(source/'script',example)
    for name,folder in [('emo',source),('shiori3',source/'third_party/shiori3')]:
        for license in folder.glob('LICENSE*'): shutil.copyfile(license,output/(name+'-'+license.name))
    shutil.copyfile(HERE/'UPSTREAM.json',output/'UPSTREAM.json'); shutil.copyfile(lock,output/'Cargo.lock')
    meta=json.loads(subprocess.check_output(['cargo','metadata','--locked','--format-version','1','--manifest-path',str(source/'Cargo.toml')],env=env))
    notices=output/'licenses';notices.mkdir(exist_ok=True)
    for package in meta['packages']:
        folder=Path(package['manifest_path']).parent
        for license in folder.glob('*'):
            if license.is_file() and license.name.upper().startswith(('LICENSE','COPYING','COPYRIGHT')):
                shutil.copyfile(license,notices/(package['name']+'-'+package['version']+'-'+license.name))
    report=[{key:p.get(key) for key in ('name','version','source','license')} for p in meta['packages']]
    (output/'DEPENDENCIES.json').write_text(json.dumps(report,indent=2)+'\n')
    (output/'BUILD.json').write_text(json.dumps({'compiler':subprocess.check_output(['rustc','--version'],text=True).strip(),'abi':'ukagaka-long','lua':args.lua,'unicode_identifiers':args.lua=='lua54','upstream':pin},indent=2)+'\n')
    print('Built actual emo-rs: '+str(library))
if __name__=='__main__': main()
