#!/usr/bin/env python3
"""Exercise the actual Mach-O module's POSIX ownership and SAORI byte contracts."""
import ctypes
from pathlib import Path
import sys

module = ctypes.CDLL(str(Path(sys.argv[1]).resolve()))
libc = ctypes.CDLL(None)
libc.malloc.argtypes = [ctypes.c_size_t]
libc.malloc.restype = ctypes.c_void_p
libc.free.argtypes = [ctypes.c_void_p]
module.load.argtypes = [ctypes.c_void_p, ctypes.c_long]
module.load.restype = ctypes.c_int
module.unload.restype = ctypes.c_int
module.request.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_long)]
module.request.restype = ctypes.c_void_p

def owned(data):
    pointer = libc.malloc(len(data) + 1)
    assert pointer
    ctypes.memmove(pointer, data + b'\0', len(data) + 1)
    return pointer

def request(data):
    count = ctypes.c_long(len(data))
    pointer = module.request(owned(data), ctypes.byref(count))
    assert pointer and 0 < count.value < 1048576
    try:
        return ctypes.string_at(pointer, count.value)
    finally:
        libc.free(pointer)

for _ in range(2):
    assert module.load(owned(b'/tmp/'), 5) == 1
    assert request(b'GET Version SAORI/1.0\r\n\r\n').startswith(b'SAORI/1.0 200')
    for encoding, charset in [('utf-8', 'UTF-8'), ('cp932', 'Shift_JIS')]:
        values = [s.encode(encoding) for s in ('文字列1', '文字列2', '文字列3')]
        head = b'EXECUTE SAORI/1.0\r\nCharset: ' + charset.encode() + b'\r\n'
        for value in values + [b'', b'one, two: three']:
            response = request(head + b'Argument0: ' + value + b'\r\n\r\n')
            assert b'Charset: ' + charset.encode() + b'\r\n' in response
            assert b'Result: ' + value + b'\r\n' in response
        arguments = b''.join(b'Argument%d: ' % i + value + b'\r\n' for i, value in enumerate(values))
        for _ in range(128):
            response = request(head + arguments + b'\r\n')
            result = response.split(b'Result: ', 1)[1].split(b'\r\n', 1)[0]
            assert result in values
    for bad in [b'', b'EXECUTE SAORI/1.0\r\n\r\n',
                b'EXECUTE SAORI/1.0\r\nArgument1: gap\r\n\r\n',
                b'EXECUTE SAORI/1.0\r\nArgument0: a\r\nArgument0: b\r\n\r\n']:
        assert request(bad).startswith(b'SAORI/1.0 400')
    assert module.unload() == 1
print('PASS: native load/request/unload/reload; UTF-8/CP932 byte retention; random membership; empty/comma values; malformed requests')
