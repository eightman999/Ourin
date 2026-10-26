#!/usr/bin/env python3
"""Build pinned Lua modules into libkagari; no downloaded ghost libraries used."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent

def source(entry, cache):
    archive = cache / (entry['name'] + '-' + entry['revision'] + '.tar.gz')
    if not archive.exists():
        with urllib.request.urlopen(entry['url'], timeout=60) as stream:
            data = stream.read(16 * 1024 * 1024 + 1)
        if len(data) > 16 * 1024 * 1024:
            raise ValueError('dependency archive too large')
        if hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('dependency checksum mismatch: ' + entry['name'])
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != entry['sha256']:
        raise ValueError('cached dependency checksum mismatch: ' + entry['name'])
    folder = cache / (entry['name'] + '-' + entry['revision'])
    # Re-extract verified source so an earlier local build cannot taint inputs.
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir()
    with tarfile.open(archive) as tar:
        total = 0
        for member in tar.getmembers():
            parts = PurePosixPath(member.name).parts
            if member.name.startswith('/') or '..' in parts or member.issym() or member.islnk():
                raise ValueError('unsafe dependency archive path')
            if len(parts) < 2:
                continue
            target = folder.joinpath(*parts[1:])
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                total += member.size
                if total > 64 * 1024 * 1024:
                    raise ValueError('expanded dependency too large')
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as src, target.open('wb') as out:
                    shutil.copyfileobj(src, out)
            else:
                raise ValueError('unsupported dependency archive entry')
    return folder

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--arch', required=True)
    parser.add_argument('--lua-include', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--objects', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    for path in (args.cache, args.objects, args.output):
        path.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ROOT/'DEPENDENCIES.json').read_text())
    paths = {item['name']: source(item, args.cache) for item in manifest}
    posix = paths['luachild']/'luachild_posix.c'
    body = posix.read_text()
    needle = '  ret = posix_spawnp(&proc->pid, p->command, &p->redirect, 0,'
    if needle not in body:
        raise ValueError('pinned luachild spawn source changed')
    body = body.replace(needle, """  extern const char* ourin_luachild_cwd(lua_State*);
  const char* cwd = ourin_luachild_cwd(L);
  if (cwd) {
    int error = posix_spawn_file_actions_addchdir_np(&p->redirect, cwd);
    if (error) { posix_spawn_file_actions_destroy(&p->redirect); errno = error; return push_error(L); }
  }
""" + needle)
    posix.write_text(body)
    flags = ['-O2' , '-fPIC', '-mmacosx-version-min=13.0', '-arch', args.arch, '-I'+str(args.lua_include)]
    sources = [(paths['luachild']/name, ['-DUSE_POSIX', '-include', 'signal.h']) for name in ('luachild_common.c','luachild_lua_5_3.c','luachild_luajit_2_1.c','luachild_posix.c','luachild_windows.c')]
    sources.append((paths['luautf8']/'lutf8lib.c', ['-Dluaopen_utf8=ourin_luaopen_utf8']))
    sources.extend((paths['luasocket']/'src'/(name+'.c'), ['-DLUASOCKET_NODEBUG']) for name in ('luasocket','timeout','buffer','io','auxiliar','compat','options','inet','usocket','except','select','tcp','udp'))
    sources.extend((path, []) for path in sorted(paths['lpeg'].glob('*.c')))
    for path, extra in sources:
        subprocess.run([os.environ.get('CC','clang'),'-std=gnu99',*flags,*extra,'-c',str(path),'-o',str(args.objects/(path.stem+'.o'))],check=True)
    subprocess.run([os.environ.get('CXX','clang++'),'-std=c++17',*flags,'-c',str(ROOT/'native_modules.cpp'),'-o',str(args.objects/'native_modules.o')],check=True)
    # The original MIT notice is embedded in the POSIX source, not COPYING.txt.
    mit = (paths['luachild']/'luachild_posix.c').read_text().split('*/',1)[0].removeprefix('/*')
    (args.output/'LICENSE.luachild-MIT.txt').write_text(mit.strip()+'\n')
    shutil.copyfile(paths['luachild']/'COPYING.txt',args.output/'LICENSE.luachild-Unlicense.txt')
    shutil.copyfile(paths['luautf8']/'LICENSE',args.output/'LICENSE.luautf8.txt')
    shutil.copyfile(paths['luasocket']/'LICENSE',args.output/'LICENSE.luasocket.txt')
    shutil.copyfile(paths['lpeg']/'lpeg.html',args.output/'LICENSE.lpeg.html')
    shutil.copyfile(ROOT/'DEPENDENCIES.json',args.output/'MODULE_DEPENDENCIES.json')

if __name__ == '__main__':
    main()
