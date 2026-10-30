#!/usr/bin/env python3
"""Locally build pinned aktk with a real fixed mruby SDK and SHIOLINK host."""
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


def extract(pin, destination, archive=None):
    if archive is None:
        archive = destination.parent / 'upstream.tar.gz'
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
    text = source.decode('latin1')
    start = text.index('BOOL __cdecl load(')
    end = text.index('\n\nwstring s2w(', start)
    text = '#include "portability.h"\n' + text[start:end]
    replacements = [
        ('SetCurrentDirectory(s2w(param).c_str());', 'if (chdir(param.c_str()) != 0) return false;'),
        ('fopen_s(&f, "index.rb", "rb");', 'f = fopen("index.rb", "rb");\n\tif (!f) return false;'),
        ('mrb_load_file(mrb, f);\n\tfclose(f);', 'mrb_load_file(mrb, f);\n\tfclose(f);\n\tif (mrb->exc) { mrb_close(mrb); mrb = nullptr; return false; }'),
        ('return mrb_bool(r);', 'bool success = !mrb->exc && mrb_bool(r);\n\tif (!success) { mrb_close(mrb); mrb = nullptr; }\n\treturn success;'),
        ('bool ret = mrb_bool(r);\n\tmrb_close(mrb);\n\treturn false;',
         'bool ret = !mrb->exc && mrb_bool(r);\n\tmrb_close(mrb);\n\tmrb = nullptr;\n\treturn ret;'),
        ('string ret=string(RSTRING_PTR(r));',
         'string ret;\n\tif (mrb->exc || !mrb_string_p(r)) {\n'
         '\t\tmrb->exc = nullptr;\n'
         '\t\tret = "SHIORI/3.0 500 Internal Server Error\\r\\nCharset: UTF-8\\r\\n\\r\\n";\n'
         '\t} else {\n\t\tret.assign(RSTRING_PTR(r), RSTRING_LEN(r));\n\t}\n'
         '\tmrb_gc_arena_restore(mrb, arena);'),
    ]
    for old, new in replacements:
        if text.count(old) != 1: raise ValueError('fixed aktk patch mismatch: ' + old)
        text = text.replace(old,new)
    boundary = 'HGLOBAL __cdecl request('
    start = text.index(boundary)
    request = text[start:]
    needle = 'mrb_value r = mrb_funcall('
    if request.count(needle) != 1: raise ValueError('fixed request arena patch mismatch')
    request = request.replace(needle,'int arena = mrb_gc_arena_save(mrb);\n\t' + needle)
    return (text[:start]+request).encode('latin1')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/engines/aktk')
    parser.add_argument('--ruby', type=Path, default=Path('/opt/homebrew/opt/ruby/bin/ruby'))
    parser.add_argument('--rake', type=Path, default=Path('/opt/homebrew/opt/ruby/bin/rake'))
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--mruby-archive', type=Path)
    args = parser.parse_args()
    pin = json.loads((HERE / 'UPSTREAM.json').read_text())
    ruby_version = subprocess.check_output([str(args.ruby), '--version'], text=True).strip()
    rake_version = subprocess.check_output([str(args.ruby), str(args.rake), '--version'], text=True).strip()
    if 'ruby 4.0.7 ' not in ruby_version or rake_version != 'rake, version 13.3.1':
        raise ValueError('Ruby/Rake differ from the recorded local build tools')
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-aktk-build-') as tmp:
        root = Path(tmp); upstream, sdk = root / 'upstream', root / 'mruby'
        extract(pin['aktk'], upstream, args.archive)
        extract(pin['mruby'], sdk, args.mruby_archive)
        config = root / 'mruby-config.rb'; shutil.copyfile(HERE / config.name, config)
        subprocess.run([str(args.ruby), str(args.rake)], cwd=sdk,
                       env={**os.environ, 'MRUBY_CONFIG': str(config)}, check=True, timeout=240)
        original = (upstream / pin['aktk']['entry_source']).read_bytes()
        (root / 'dllmain.posix.cpp').write_bytes(port(original))
        for name in ['portability.h','main.cpp']:
            shutil.copyfile(HERE / name, root / name)
        library = sdk / 'build/host/lib/libmruby.a'
        subprocess.run(['/usr/bin/clang++','-std=c++17','-O2','-Wall','-Wextra',
                        '-mmacosx-version-min=13.0','-DMRB_UTF8_STRING','-I'+str(sdk/'include'),
                        str(root/'main.cpp'), str(library), '-lm', '-o', str(output/'aktk-shiolink')],
                       check=True, timeout=60)
        for license_name in ['LICENSE','LEGAL']:
            shutil.copyfile(sdk/license_name,output/('mruby.'+license_name))
        shutil.copyfile(upstream/'aktk/ReadMe.txt',output/'ReadMe.upstream.txt')
        shutil.copyfile(HERE/'UPSTREAM.json',output/'UPSTREAM.json')
        (output/'dllmain.posix.cpp').write_bytes(port(original))
        example = output/'example';example.mkdir(exist_ok=True)
        shutil.copyfile(HERE/'example/index.rb',example/'index.rb')
        (output/'BUILD.json').write_text(json.dumps({
            'mruby_version':pin['mruby']['version'], 'mruby_revision':pin['mruby']['revision'],
            'sdk_library_sha256':hashlib.sha256(library.read_bytes()).hexdigest(),
            'upstream_entry_sha256':hashlib.sha256(original).hexdigest(),
            'ruby':ruby_version, 'rake':rake_version, 'transport':'SHIOLINK UTF-8',
            'example_origin':'self-authored: no upstream dictionary exists',
            'external_mrbgems':False,
        },indent=2)+'\n')
        (output/'NOTICE.aktk.txt').write_text('aktk '+pin['aktk']['revision']+'\n'
            'No upstream redistribution license found; optional local build only.\n')
    print('Built real mruby-backed aktk SHIOLINK child: '+str(output/'aktk-shiolink'))


if __name__ == '__main__':
    main()
