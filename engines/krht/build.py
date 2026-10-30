#!/usr/bin/env python3
"""Locally port pinned krht DLL operations to a Tcl SHIOLINK child process."""
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


def extract(pin, destination, archive=None):
    if archive is None:
        archive = destination.parent / (destination.name + '.tar.gz')
        with urllib.request.urlopen(pin['url'], timeout=60) as stream:
            data = stream.read(16 * 1024 * 1024 + 1)
        if len(data) > 16 * 1024 * 1024:
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
            target = destination.joinpath(*parts[1:])
            if member.isdir(): target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                total += member.size
                if total > 64 * 1024 * 1024: raise ValueError('expanded archive too large')
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, target.open('wb') as out:
                    shutil.copyfileobj(source, out)
            else: raise ValueError('unsupported upstream entry')


def port(source):
    # Preserve code bytes without depending on the legacy source comment encoding.
    text = source.decode('latin1')
    start = text.index('BOOL __cdecl load(')
    end = text.index('\n\nwstring s2w(', start)
    text = '#include "portability.h"\n' + text[start:end]
    before = 'SetCurrentDirectory(s2w(param).c_str());'
    if text.count(before) != 1: raise ValueError('fixed path patch mismatch')
    text = text.replace(before, 'if (chdir(param.c_str()) != 0) return false;')
    before = 'interp = Tcl_CreateInterp();'
    text = text.replace(before, before + '\n\tif (Tcl_Init(interp) != TCL_OK) { Tcl_DeleteInterp(interp); interp = nullptr; return false; }')
    before = 'Tcl_Eval(interp, "source index.tcl");'
    text = text.replace(before, 'if (Tcl_Eval(interp, "source index.tcl") != TCL_OK) { Tcl_DeleteInterp(interp); interp = nullptr; return false; }')
    before = 'Tcl_Obj* objv[] = { cmd, arg };'
    if text.count(before) != 2: raise ValueError('fixed object lifetime patch mismatch')
    text = text.replace(before, before + '\n\tTcl_IncrRefCount(cmd); Tcl_IncrRefCount(arg);')
    before = 'Tcl_EvalObjv(interp, 2, objv, TCL_EVAL_DIRECT);'
    if text.count(before) != 2: raise ValueError('fixed invocation patch mismatch')
    text = text.replace(before, 'int evalStatus = Tcl_EvalObjv(interp, 2, objv, TCL_EVAL_DIRECT);\n\tTcl_DecrRefCount(cmd); Tcl_DecrRefCount(arg);')
    before = 'string ret=string(Tcl_GetStringResult(interp));'
    text = text.replace(before, 'if (evalStatus != TCL_OK) { Tcl_DeleteInterp(interp); interp = nullptr; return false; }\n\t' + before)
    text = text.replace('Tcl_Eval(interp, "_unload");', 'int evalStatus = Tcl_Eval(interp, "_unload");')
    before = 'ret = string(Tcl_GetStringResult(interp));'
    text = text.replace(before, before + '\n\tif (evalStatus != TCL_OK) ret = "SHIORI/3.0 500 Internal Server Error\\r\\nCharset: UTF-8\\r\\n\\r\\n";')
    return text.encode('latin1')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=['arm64', 'x86_64'], default=platform.machine(),
                        help='Target Mach-O architecture; defaults to the current Mac architecture')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/engines/krht')
    parser.add_argument('--tcl-prefix', type=Path, default=Path('/opt/homebrew/opt/tcl-tk'))
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--tcl-archive', type=Path)
    parser.add_argument('--existing-tcl', action='store_true', help='Use the old Homebrew dynamic Tcl path (macOS 26)')
    args = parser.parse_args()
    if platform.system() != 'Darwin': raise ValueError('This build targets macOS')
    sdk = subprocess.check_output(['/usr/bin/xcrun', '--show-sdk-path'], text=True).strip()
    compiler = subprocess.check_output(['/usr/bin/clang', '--version'], text=True).splitlines()[0]
    pin = json.loads((HERE / 'UPSTREAM.json').read_text())
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-krht-build-') as tmp:
        root = Path(tmp).resolve(); upstream = root / 'upstream'
        extract(pin['krht'], upstream, args.archive)
        original = (upstream / pin['krht']['entry_source']).read_bytes()
        (root / 'dllmain.posix.cpp').write_bytes(port(original))
        for name in ['portability.h', 'main.cpp']:
            shutil.copyfile(HERE / name, root / name)
        if args.existing_tcl:
            prefix = args.tcl_prefix.resolve()
            version = subprocess.check_output([str(prefix / 'bin/tclsh')], input='puts [info patchlevel]\n', text=True).strip()
            if version != pin['tcl']['version']: raise ValueError('Tcl version mismatch: ' + version)
            library = prefix / 'lib/libtcl9.1.dylib'
            slices = subprocess.check_output(['/usr/bin/lipo', '-archs', str(library)], text=True).split()
            if args.arch not in slices: raise ValueError('Existing Tcl lacks requested architecture ' + args.arch + ': ' + ', '.join(slices))
            include = prefix / 'include/tcl-tk'
            minimum = '26.0'
            extra = []
            license_file = prefix / pin['tcl']['license_file']
        else:
            prefix = root / 'tcl'
            extract(pin['tcl']['source_build'], prefix, args.tcl_archive)
            build = root / 'tcl-build'; build.mkdir()
            env = dict(os.environ, MACOSX_DEPLOYMENT_TARGET='11.0', CC='/usr/bin/clang',
                       SDKROOT=sdk, CFLAGS='-O2 -arch ' + args.arch + ' -isysroot ' + sdk + ' -mmacosx-version-min=11.0',
                       LDFLAGS='-arch ' + args.arch + ' -isysroot ' + sdk + ' -mmacosx-version-min=11.0')
            subprocess.run(['/bin/sh', str(prefix / 'unix/configure'), '--disable-shared', '--disable-zipfs',
                            '--build=' + platform.machine() + '-apple-darwin', '--host=' + args.arch + '-apple-darwin',
                            '--prefix=' + str(root / 'unused-install')], cwd=build, env=env, check=True, timeout=180)
            subprocess.run(['make', '-j4', 'binaries'], cwd=build, env=env, check=True, timeout=600)
            library = build / 'libtcl9.1.a'
            include = prefix / 'generic'
            minimum = '11.0'; version = pin['tcl']['version']
            extra = ['-DOURIN_KRHT_BUNDLED_TCL=1', '-framework', 'CoreFoundation', '-lz', '-lpthread']
            license_file = prefix / 'license.terms'
            scripts = output / 'lib/tcl9.1'
            if scripts.exists(): shutil.rmtree(scripts)
            shutil.copytree(prefix / 'library', scripts)
        subprocess.run(['/usr/bin/clang++', '-arch', args.arch, '-isysroot', sdk, '-std=c++17', '-O2', '-Wall', '-Wextra',
                        '-mmacosx-version-min=' + minimum, '-I' + str(include),
                        str(root / 'main.cpp'), str(library), *extra, '-o', str(output / 'krht-shiolink')],
                       check=True, timeout=60)
        slices = subprocess.check_output(['/usr/bin/lipo', '-archs', str(output / 'krht-shiolink')], text=True).split()
        if slices != [args.arch]: raise ValueError('Unexpected host architecture: ' + ', '.join(slices))
        shutil.copyfile(license_file, output / 'LICENSE.Tcl.terms')
        shutil.copyfile(upstream / 'krht/ReadMe.txt', output / 'ReadMe.upstream.txt')
        shutil.copyfile(HERE / 'UPSTREAM.json', output / 'UPSTREAM.json')
        (output / 'dllmain.posix.cpp').write_bytes(port(original))
        example = output / 'example'
        example.mkdir(exist_ok=True)
        shutil.copyfile(HERE / 'example/index.tcl', example / 'index.tcl')
        (output / 'BUILD.json').write_text(json.dumps({
            'architecture': args.arch, 'builder_architecture': platform.machine(), 'sdk_path': sdk, 'compiler': compiler,
            'tcl_version': version, 'tcl_source': 'existing prefix' if args.existing_tcl else pin['tcl']['source_build'],
            'minimum_macos': minimum, 'tcl_link': 'dynamic' if args.existing_tcl else 'static',
            'tcl_library_sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
            'upstream_entry_sha256': hashlib.sha256(original).hexdigest(),
            'upstream_revision': pin['krht']['revision'], 'transport': pin['transport'],
            'example_origin': 'self-authored: no upstream Tcl dictionary exists',
            'upstream_load_callback': '_request(directory)',
        }, indent=2) + '\n')
        (output / 'NOTICE.krht.txt').write_text('krht upstream: ' + pin['krht']['repository'] + '\n'
            'Fixed revision: ' + pin['krht']['revision'] + '\n'
            'No upstream license or redistribution grant found. Local opt-in port only.\n'
            'POSIX bridge adaptations are documented in engines/krht/PATCHES.md.\n')
    print('Built real Tcl-backed krht SHIOLINK child: ' + str(output / 'krht-shiolink'))


if __name__ == '__main__':
    main()
