#!/usr/bin/env python3
"""Build a native SHIORI development example against pinned CSAORI."""
import argparse
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


def extract(pin, destination, archive=None):
    if archive is None:
        archive = destination.parent / 'upstream.tar.gz'
        with urllib.request.urlopen(pin['url'], timeout=60) as stream:
            data = stream.read(32 * 1024 * 1024 + 1)
        if len(data) > 32 * 1024 * 1024:
            raise ValueError('archive too large')
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != pin['sha256']:
        raise ValueError('upstream SHA256 mismatch')
    destination.mkdir()
    with tarfile.open(archive) as tar:
        total = 0
        for member in tar.getmembers():
            parts = PurePosixPath(member.name).parts
            if member.name.startswith('/') or '..' in parts or member.issym() or member.islnk():
                raise ValueError('unsafe upstream archive')
            if len(parts) < 2: continue
            if '/'.join(parts[1:]) not in {'csaori_base.h','csaori_base.cpp','csaori_util.h','csaori_util.cpp','readme.txt'}: continue
            target = destination.joinpath(*parts[1:])
            if member.isdir(): target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                total += member.size
                if total > 64 * 1024 * 1024: raise ValueError('expanded archive too large')
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, target.open('wb') as out:
                    shutil.copyfileobj(source, out)
            else: raise ValueError('unsupported upstream entry')


def port(source,root):
    for name in ['csaori_base.h','csaori_util.h']:
        data=(source/name).read_bytes().decode('latin1')
        data=data.replace('swprintf(buf,L"%d",num);','swprintf(buf,32,L"%d",num);')
        data=data.replace('setlocale( LC_ALL, "Japanese");','/* No process-global locale mutation in this POSIX sample. */')
        (root/name).write_bytes(data.encode('latin1'))
    base=(source/'csaori_base.cpp').read_bytes().decode('latin1')
    base=base[base.index('bool CSAORIInput::parseString'):base.index('std::string CSAORIBase::request')]
    base=base.replace('swprintf(tmptxt,L"%d",','swprintf(tmptxt,32,L"%d",')
    (root/'csaori_protocol.cpp').write_bytes(('#include "csaori_base.h"\n'+base).encode('latin1'))
    util=(source/'csaori_util.cpp').read_bytes().decode('latin1')
    charset=util[util.index('std::wstring CodePagetoString'):util.index('UINT StringtoCodePage')]
    shared=util[util.index('string_t getResultString'):util.index('string_t replaceAll')]
    (root/'csaori_protocol_util.cpp').write_bytes(('#include "csaori_base.h"\nnamespace SAORI_FUNC {\n'+charset+shared+'\n}\n').encode('latin1'))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/engines/csaori')
    parser.add_argument('--archive',type=Path)
    args=parser.parse_args()
    pin=json.loads((HERE/'UPSTREAM.json').read_text())
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-csaori-build-') as tmp:
        root=Path(tmp);source=root/'source'
        extract(pin,source,args.archive)
        port(source,root)
        shutil.copyfile(HERE/'windows.h',root/'windows.h')
        library=output/'libcsaori-shiori.dylib'
        subprocess.run(['/usr/bin/clang++','-std=c++17','-O2','-Wall','-Wextra','-Wno-unknown-pragmas',
                        '-Wno-unused-parameter','-dynamiclib','-mmacosx-version-min=13.0','-I'+str(root),
                        str(HERE/'sample.cpp'),str(root/'csaori_protocol.cpp'),str(root/'csaori_protocol_util.cpp'),
                        '-o',str(library)],check=True,timeout=60)
        library.with_suffix('.dylib.plist').write_bytes(plistlib.dumps({'OurinShioriABI':pin['abi']}))
        shutil.copyfile(source/pin['license_file'],output/'LICENSE.csaori-readme.txt')
        shutil.copyfile(HERE/'UPSTREAM.json',output/'UPSTREAM.json')
        for name in ['csaori_protocol.cpp','csaori_protocol_util.cpp']:
            shutil.copyfile(root/name,output/name)
        (output/'BUILD.json').write_text(json.dumps({
            'revision':pin['revision'],'abi':pin['abi'],'port_scope':'protocol parser/builder only',
            'upstream_base_sha256':hashlib.sha256((source/'csaori_base.cpp').read_bytes()).hexdigest(),
            'upstream_util_sha256':hashlib.sha256((source/'csaori_util.cpp').read_bytes()).hexdigest(),
            'compiler':subprocess.check_output(['/usr/bin/clang++','--version'],text=True).splitlines()[0],
        },indent=2)+'\n')
    print('Built real CSAORI parser/builder SHIORI development sample: '+str(library))


if __name__=='__main__':main()
