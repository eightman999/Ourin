#!/usr/bin/env python3
"""Self-authored integration fixtures against the built KAGARI/Lua dylibs.

Usage: python3 engines/kagari/tests/test_native_modules.py --library /path/libkagari.dylib
Does not download ghosts, access the network, or change the clipboard.
"""
import argparse
import ctypes as C
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def child(library):
    lua = C.CDLL(str(library.parent / 'liblua.5.4.dylib'), mode=C.RTLD_GLOBAL)
    lib = C.CDLL(str(library), mode=C.RTLD_GLOBAL)
    lua.luaL_newstate.restype = C.c_void_p
    for name in ('luaL_openlibs', 'lua_close'):
        getattr(lua, name).argtypes = [C.c_void_p]
    lua.luaL_loadstring.argtypes = [C.c_void_p, C.c_char_p]
    lua.luaL_loadstring.restype = C.c_int
    lua.lua_pcallk.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_ssize_t, C.c_void_p]
    lua.lua_pcallk.restype = C.c_int
    lua.lua_tolstring.argtypes = [C.c_void_p, C.c_int, C.c_void_p]
    lua.lua_tolstring.restype = C.c_char_p
    lib.ourin_kagari_preload_modules.argtypes = [C.c_void_p, C.c_char_p]
    before = os.getcwd()
    def run(state, code):
        rc = lua.luaL_loadstring(state, code.encode())
        if rc == 0:
            rc = lua.lua_pcallk(state, 0, 0, 0, 0, None)
        if rc:
            raise AssertionError(lua.lua_tolstring(state, -1, None).decode())
        assert os.getcwd() == before, 'module changed host process cwd'
    with tempfile.TemporaryDirectory(prefix='ourin-kagari-modules-') as tmp:
        roots = [Path(tmp).resolve() / name for name in ('one', 'two')]
        # Self-authored POSIX SAORI fixture verifies the actual long-length ABI.
        native_source = Path(tmp) / 'saori.c'
        native_source.write_text('''#include <stdlib.h>
#include <string.h>
int loadu(char *path, long size) { int ok = size > 0 && path[0] == '/'; free(path); return ok; }
int unload(void) { return 1; }
char *request(char *input, long *size) {
free(input); const char *text = "SAORI/1.0 200 OK\\r\\nResult: fixture\\r\\n\\r\\n";
*size = strlen(text); char *out = malloc(*size); memcpy(out, text, *size); return out;
}''')
        native_library = Path(tmp) / 'fixture.dylib'
        subprocess.run(['/usr/bin/clang', '-dynamiclib', str(native_source), '-o', str(native_library)], check=True, timeout=20)
        states = []
        try:
            for index, root in enumerate(roots):
                (root / 'child').mkdir(parents=True)
                (root / 'tag.txt').write_text(str(index))
                (root / 'snippet.lua').write_text('return 42')
                state = lua.luaL_newstate(); states.append(state)
                lua.luaL_openlibs(state)
                lib.ourin_kagari_preload_modules(state, str(root).encode())
                run(state, f'''
                    local f = assert(io.open('tag.txt')); assert(f:read('*a') == '{index}'); f:close()
                    assert(dofile('snippet.lua') == 42)
                    assert(assert(loadfile('snippet.lua'))() == 42)
                    assert(io.lines('tag.txt')() == '{index}')
                    local lc = require('luachild')
                    local found = false
                    for name in lc.dir('.') do if name.name == 'tag.txt' then found = true end end
                    assert(found)
                    assert(lc.chdir('child'))
                    assert(lc.currentdir() == {json.dumps(str(root / 'child'))})
                    local r, w = lc.pipe()
                    local p = assert(lc.spawn{{'/bin/pwd', stdout=w}})
                    w:close(); assert(r:read('*l') == lc.currentdir()); r:close(); p:wait()
                    assert(lc.chdir('..'))
                    assert(not lc.chdir('does-not-exist'))
                ''')
            # Alternate two live states: neither can inherit the other's root.
            for _ in range(5):
                for index, state in enumerate(states):
                    run(state, f"local f=assert(io.open('tag.txt')); assert(f:read('*a')=='{index}'); f:close()")
            run(states[0], f'''
                local module = require('saori_universal.native')({json.dumps(str(Path(tmp) / 'fixture.dll'))})
                assert(module:load({json.dumps(str(roots[0]))}))
                assert(module:request('EXECUTE SAORI/1.0\\r\\n\\r\\n'):find('Result: fixture'))
                assert(module:unload()); assert(module:unload())
                assert(module:request('EXECUTE SAORI/1.0\\r\\n\\r\\n'):find('503'))
            ''')
            run(states[0], r'''
                local utf = require('lua-utf8'); assert(utf.len('桜鈴') == 2)
                local iconv = require('iconv')
                local cp = assert(iconv.new('CP932', 'UTF-8')):iconv('桜鈴')
                assert(assert(iconv.new('UTF-8', 'CP932')):iconv(cp) == '桜鈴')
                local no, err = assert(iconv.new('UTF-8', 'UTF-8')):iconv(string.char(255))
                assert(no == nil and err == 2)
                local socket = require('socket.core'); assert(type(socket.gettime()) == 'number')
                local lpeg = require('lpeg'); assert(lpeg.match(lpeg.P('hello'), 'hello') == 6)
                assert(type(require('clipboard').set) == 'function') -- no live clipboard write
                local rand = require('rand.native'); local a, b = rand(123), rand(123)
                for i=1,100 do local n=a(); assert(n==b() and n>=0 and n<2^32) end
                local n=a:uniform(7); assert(n>=0 and n<7)
                assert(type(a:normal_distribution(0, 1)) == 'number')
                assert(not pcall(function() a:uniform(-1) end))
                local saori = require('saori_universal.native')('missing.dll')
                assert(saori:load('.') == false)
                assert(saori:request('EXECUTE SAORI/1.0\r\n\r\n'):find('503'))
                assert(saori:unload())
                local lc, fh = require('luachild'), require('fh')
                local r,w=lc.pipe(); assert(fh.blocking(r,false)); assert(not fh.readable(r))
                w:write('x'); w:flush(); assert(fh.readable(r)); assert(r:read(1)=='x')
                r:close(); w:close(); assert(not pcall(fh.readable,r))
            ''')
        finally:
            for state in states: lua.lua_close(state)
        assert os.getcwd() == before
        # Exercise the actual KAGARI ABI, including two simultaneous instances.
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from verify_kagari_mosu import Kagari
        api = Kagari(library)
        ids = []
        source = '''local lc=require('luachild')
return {load=function() return true end,
unload=function() return true end,
request=function()
local f=assert(io.open('tag.txt')); local text=f:read('*a'); f:close()
assert(lc.chdir('child')); assert(lc.chdir('..'))
return 'SHIORI/3.0 200 OK\\r\\nValue: '..text..'\\r\\n\\r\\n' end}'''
        for root in roots:
            (root / 'index.lua').write_text(source)
            instance = api.load(root); assert instance >= 0; ids.append(instance)
            assert os.getcwd() == before
        try:
            for _ in range(5):
                for index, instance in enumerate(ids):
                    assert f'Value: {index}\r\n' in api.request(instance, 'OnBoot')
                    assert os.getcwd() == before
        finally:
            for instance in ids: assert api.lib.kagari_unload(instance)
        assert os.getcwd() == before
        bad = Path(tmp) / 'invalid'; bad.mkdir(); (bad / 'index.lua').write_text('error("expected")')
        assert api.load(bad) < 0
        assert os.getcwd() == before
    print(json.dumps({'status':'pass','checks':['two_lua_roots','two_kagari_instances','host_cwd_unchanged','child_spawn_cwd','relative_io','native_modules','native_saori_abi','missing_saori','load_failure_cwd']}))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--child', action='store_true')
    args = parser.parse_args()
    if args.child:
        child(args.library.resolve())
    else:
        subprocess.run([sys.executable, __file__, '--library', str(args.library.resolve()), '--child'], check=True, timeout=30, env={**os.environ, 'PYTHONDONTWRITEBYTECODE':'1'})
