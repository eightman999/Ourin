#!/usr/bin/env python3
"""SHIOLINK transport for the real upstream phiori Python engine.

Run outside ghost/master: phiori executes every *.py in that directory as a dictionary.
"""
import contextlib
import importlib
import os
from pathlib import Path
import sys
import traceback

LIMIT = 1_048_576

def line(stream):
    value = stream.readline(LIMIT + 1)
    if len(value) > LIMIT: raise ValueError('SHIOLINK line too large')
    if not value: return None
    if not value.endswith(b'\n'): raise EOFError('incomplete SHIOLINK line')
    return value.rstrip(b'\n').removesuffix(b'\r')

def main():
    incoming, outgoing = sys.stdin.buffer, sys.stdout.buffer
    engine = None
    try:
        while (command := line(incoming)) is not None:
            if command.startswith(b'*L:'):
                if engine is not None: raise ValueError('duplicate load')
                root = Path(command[3:].decode('utf-8')).resolve(strict=True)
                if not root.is_dir(): raise ValueError('load path is not a directory')
                os.chdir(root) # this isolated engine process only; matches upstream C host
                sys.path.insert(0, str(root))
                with contextlib.redirect_stdout(sys.stderr):
                    engine = importlib.import_module('phiori')
                    if not engine.load(str(root) + os.sep): raise RuntimeError('phiori load failed')
            elif command.startswith(b'*S:'):
                if engine is None: raise ValueError('request before load')
                outgoing.write(command + b'\r\n'); outgoing.flush()
                request = bytearray()
                while True:
                    item = line(incoming)
                    if item is None: raise EOFError('incomplete SHIORI request')
                    request.extend(item + b'\r\n')
                    if len(request) > LIMIT: raise ValueError('SHIORI request too large')
                    if not item: break
                with contextlib.redirect_stdout(sys.stderr):
                    response = engine.request(bytes(request))
                if not isinstance(response, bytes) or len(response) > LIMIT:
                    raise ValueError('invalid phiori response')
                outgoing.write(response); outgoing.flush()
            elif command == b'*U:':
                return 0
            else:
                raise ValueError('unknown SHIOLINK command')
        return 0
    except EOFError:
        return 0
    except Exception:
        traceback.print_exc(file=sys.stderr)
        return 1
    finally:
        if engine is not None:
            with contextlib.redirect_stdout(sys.stderr):
                engine.unload()

if __name__ == '__main__':
    sys.exit(main())
