#!/usr/bin/env python3
"""Optional local dktrtk builds: historical x86_64 SDK and native ARM64 SDK."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
ADDONS=['scriptarray/scriptarray.cpp','scriptstdstring/scriptstdstring.cpp',
        'scriptstdstring/scriptstdstring_utils.cpp','scriptany/scriptany.cpp',
        'scripthandle/scripthandle.cpp','weakref/weakref.cpp',
        'scriptdictionary/scriptdictionary.cpp','scriptfile/scriptfile.cpp',
        'scriptfile/scriptfilesystem.cpp','scriptmath/scriptmath.cpp',
        'scriptmath/scriptmathcomplex.cpp','scriptgrid/scriptgrid.cpp',
        'scriptbuilder/scriptbuilder.cpp']


def extract(pin,destination,archive=None):
    if archive is None:
        archive=destination.parent/(destination.name+'.tar.gz')
        with urllib.request.urlopen(pin['url'],timeout=60) as stream:
            data=stream.read(16*1024*1024+1)
        if len(data)>16*1024*1024: raise ValueError('archive too large')
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=pin['sha256']: raise ValueError('upstream hash mismatch')
    destination.mkdir()
    if zipfile.is_zipfile(archive):
        total=0
        with zipfile.ZipFile(archive) as bundle:
            for item in bundle.infolist():
                parts=PurePosixPath(item.filename).parts
                if item.filename.startswith('/') or '..' in parts or (item.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError('unsafe ZIP entry')
                target=destination.joinpath(*parts)
                if item.is_dir(): target.mkdir(parents=True,exist_ok=True)
                else:
                    total+=item.file_size
                    if total>64*1024*1024: raise ValueError('expanded archive too large')
                    target.parent.mkdir(parents=True,exist_ok=True)
                    with bundle.open(item) as src,target.open('wb') as out: shutil.copyfileobj(src,out)
        return
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


def port(dn,sdk,arch):
    # Preserve upstream compile, addon registration and script dispatch bodies.
    # Windows DLL entrypoint/conversion helpers are unused in the process host.
    source=(dn/'dktrtk/dllmain.cpp').read_bytes().decode('cp932')
    source=source[source.index('BOOL __cdecl load'):source.index('wstring s2w')]
    old='SetCurrentDirectory(s2w(param).c_str());'
    assert source.count(old)==1
    source=source.replace(old,'if (chdir(param.c_str()) != 0) return false;')
    old='engine->SetEngineProperty(asEP_SCRIPT_SCANNER, 0);'
    assert source.count(old)==1
    source=source.replace(old,'engine->SetMessageCallback(asFUNCTION(Diagnostic), nullptr, asCALL_CDECL);\n\tengine->SetEngineProperty(asEP_SCRIPT_SCANNER, 1);')
    start=source.index('HGLOBAL __cdecl request')
    # Standard C++ cannot return bool from void*. Preserve upstream failure semantics.
    source=source[:start]+source[start:].replace('return false;','return nullptr;')
    prefix=(HERE/'host/posix-prefix.hpp').read_text()
    if arch=='arm64':
        prefix='#include "add_on/datetime/datetime.h"\n'+prefix
        assert source.count('RegisterScriptFileSystem(engine);')==1
        source=source.replace('RegisterScriptFileSystem(engine);','RegisterScriptDateTime(engine);\n\tRegisterScriptFileSystem(engine);')
        source=source.replace('engine->SetEngineProperty(asEP_SCRIPT_SCANNER, 1);','engine->SetEngineProperty(asEP_SCRIPT_SCANNER, 1);\n\tengine->SetEngineProperty(asEP_PROPERTY_ACCESSOR_MODE, 2);')
    (dn/'dktrtk/ported.cpp').write_text(prefix+source)
    # Mach-O atom boundaries must not split inline-assembly CFI ranges. Local
    # labels retain the exact original instruction/branch sequence and CFI.
    if arch != 'x86_64': return
    assembly=sdk/'sdk/angelscript/source/as_callfunc_x64_gcc.cpp'
    text=assembly.read_text()
    for label in ['loopstack','endstack','intret','endcall']:
        assert label+':' in text
        text=text.replace(label,'L'+label)
    assembly.write_text(text)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--arch',choices=['x86_64','arm64'],default='x86_64')
    parser.add_argument('--archive',type=Path);parser.add_argument('--sdk-archive',type=Path)
    parser.add_argument('--cxx',default='clang++')
    args=parser.parse_args()
    if platform.system()!='Darwin': raise ValueError('This port targets macOS')
    pin=json.loads((HERE/'UPSTREAM.json').read_text())
    sdk_pin=pin['angelscript_arm64' if args.arch=='arm64' else 'angelscript']
    output=(args.output or ROOT/('build/engines/dktrtk-arm64' if args.arch=='arm64' else 'build/engines/dktrtk')).resolve()
    output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-dktrtk-build-') as temporary:
        work=Path(temporary).resolve();dn=work/'dktrtk';sdk=work/'angelscript'
        extract(pin['dktrtk'],dn,args.archive);extract(sdk_pin,sdk,args.sdk_archive)
        if args.arch=='arm64':
            # SDK C++ interfaces changed; use its matching official addons in full.
            shutil.copytree(sdk/'sdk/add_on',dn/'dktrtk/add_on',dirs_exist_ok=True)
            # 2.30 registered both length() and length property accessors.
            # Keep both original script entry styles with the modern addons.
            for addon in ['scriptarray/scriptarray.cpp','scriptstdstring/scriptstdstring.cpp']:
                path=dn/'dktrtk/add_on'/addon
                text=path.read_bytes()
                old=b'#if AS_USE_STLNAMES != 1 && AS_USE_ACCESSORS == 1'
                assert text.count(old)==2
                text=text.replace(old,b'#if AS_USE_STLNAMES != 1 // Ourin: retain 2.30 accessors')
                # Automatic get_/set_ property mode keeps length() and .length
                # simultaneously, as SDK 2.30 did, without a named-property clash.
                text=text.replace(b'get_length() const property',b'get_length() const')
                text=text.replace(b'set_length(uint) property',b'set_length(uint)')
                path.write_bytes(text)
        if args.arch=='arm64':
            # 2.38 resolves an auto property before a same-name explicit method.
            # Retain 2.30's array/string length() calls alongside .length access.
            compiler=sdk/'sdk/angelscript/source/as_compiler.cpp'
            text=compiler.read_bytes()
            old=b'SYMBOLTYPE symbolType = SymbolLookup(name, scope, objectType, &lookupResult, node);'
            assert text.count(old)==1
            compatibility=b"""
	// Ourin: SDK 2.30 array/string length method + accessor compatibility.
	if (symbolType == SL_CLASSPROPACCESS && objectType && name == "length" &&
	    engine->ep.propertyAccessorMode == 2 &&
	    (objectType->name == "array" || objectType->name == "string"))
	{
	    asCArray<int> methods;
	    builder->GetObjectMethodDescriptions(name.AddressOf(), objectType, methods, objIsConst);
	    if (methods.GetLength()) symbolType = SL_CLASSMETHOD;
	}
"""
            compiler.write_bytes(text.replace(old,old+compatibility))
        # Validate every file-backed section, including #include files, before parsing.
        builder=dn/'dktrtk/add_on/scriptbuilder/scriptbuilder.cpp'
        text=builder.read_bytes()
        target=b'return ProcessScriptSection(code.c_str(), (unsigned int)(code.length()), filename, 0);'
        assert text.count(target)==1
        declaration=b'#include <cstddef>\nextern bool OurinValidateSourceUTF8(const char*, size_t);\n'
        replacement=b'if (!OurinValidateSourceUTF8(code.data(), code.size())) return -1;\n\t'+target
        builder.write_bytes(declaration+text.replace(target,replacement))
        header=sdk/'sdk/angelscript/include/angelscript.h'
        assert ('#define ANGELSCRIPT_VERSION        '+('23800' if args.arch=='arm64' else '23000')) in header.read_text()
        port(dn,sdk,args.arch)
        command=[args.cxx,'-arch',args.arch,'-std=c++11','-O1','-mmacosx-version-min=13.0',
                 '-Wno-deprecated-declarations','-Wno-nontrivial-memcall',
                 '-I'+str(header.parent),'-I'+str(dn/'dktrtk'),str(HERE/'host/main.cpp'),str(HERE/'host/encoding.cpp')]
        command += [str(x) for x in sorted((sdk/'sdk/angelscript/source').glob('*.cpp'))]
        if args.arch=='arm64':
            command += [str(sdk/'sdk/angelscript/source/as_callfunc_arm64_xcode.S'),str(sdk/'sdk/add_on/datetime/datetime.cpp')]
        command += [str(dn/'dktrtk/add_on'/x) for x in ADDONS]
        command += ['-liconv','-o',str(output/'dktrtk-host')]
        subprocess.run(command,check=True,timeout=180)
        shutil.copyfile(HERE/'UPSTREAM.json',output/'UPSTREAM.json')
        shutil.copyfile(header,output/'AngelScript-license-and-interface.h')
        if args.arch=='arm64':
            notices=[header.read_text().split('*/',1)[0]+'*/\n']
            shutil.copyfile(sdk/'sdk/docs/manual/doc_license.html',output/'AngelScript-SDK-license.html')
            for addon in ADDONS+['datetime/datetime.cpp']:
                notice=(sdk/'sdk/add_on'/addon).read_bytes().split(b'#include',1)[0]
                if notice.strip(): notices.append(addon+'\n'+notice.decode('utf-8',errors='replace'))
            (output/'AngelScript-addon-notices.txt').write_text('\n'.join(notices))
        (output/'LOCAL_BUILD_ONLY.txt').write_text('dktrtk has no project license in pinned upstream. Do not bundle or redistribute this optional local build without permission. AngelScript has its own zlib notice.\n')
        (output/'BUILD.json').write_text(json.dumps({'architecture':args.arch,'compiler':subprocess.check_output([args.cxx,'--version'],text=True).splitlines()[0], 'sdk':'AngelScript '+sdk_pin['version'], 'script_entry':'index.as','registrations':ADDONS+(['datetime/datetime.cpp'] if args.arch=='arm64' else []),'addon_source':'matching official SDK' if args.arch=='arm64' else 'unchanged dktrtk snapshot'},indent=2)+'\n')
    print('Built optional local dktrtk host: '+str(output/'dktrtk-host'))

if __name__=='__main__': main()
