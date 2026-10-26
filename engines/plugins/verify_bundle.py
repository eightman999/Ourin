#!/usr/bin/env python3
"""Real bundle C ABI probe. Emit response metadata, never third-party scripts."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import sys

class Plugin:
    def __init__(self, bundle):
        self.bundle = Path(bundle)
        self.lib = ctypes.CDLL(str(self.bundle / 'Contents/MacOS/OurinPluginAdapter'))
        self.lib.plugin_loadu.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        self.lib.plugin_loadu.restype = ctypes.c_int32
        self.lib.plugin_request.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
        self.lib.plugin_request.restype = ctypes.c_void_p
        self.lib.plugin_unload.argtypes = []
        self.lib.plugin_unload.restype = None
        self.libc = ctypes.CDLL(None)
        self.libc.strdup.argtypes = [ctypes.c_char_p]
        self.libc.strdup.restype = ctypes.c_void_p

    def load(self):
        value = (str(self.bundle) + '/').encode()
        return bool(self.lib.plugin_loadu(self.libc.strdup(value), len(value)))

    def request(self, wire):
        data = wire.encode('utf-8') if isinstance(wire, str) else wire
        buf = ctypes.create_string_buffer(data)
        count = ctypes.c_size_t()
        value = self.lib.plugin_request(buf, len(data), ctypes.byref(count))
        if not value or count.value > 4 * 1024 * 1024:
            raise RuntimeError('invalid response buffer')
        return ctypes.string_at(value, count.value)

    def unload(self):
        self.lib.plugin_unload()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--event', action='append', default=[])
    parser.add_argument('--requests-json', type=Path)
    args = parser.parse_args()
    plugin = Plugin(args.bundle)
    result = {'loaded': plugin.load(), 'events': [], 'reloaded': False}
    try:
        if result['loaded']:
            requests = json.loads(args.requests_json.read_text()) if args.requests_json else [
                {'id': event} for event in args.event or ['OnMenuExec']]
            for request in requests:
                event = request['id']
                wire = request.get('method', 'GET') + ' PLUGIN/2.0\r\nID: ' + event + '\r\nCharset: UTF-8\r\n'
                for index, value in enumerate(request.get('references', [])):
                    if '\r' in value or '\n' in value:
                        raise ValueError('reference must use protocol URL escaping')
                    wire += f'Reference{index}: {value}\r\n'
                raw = plugin.request(wire + '\r\n')
                lines = raw.split(b'\r\n')
                result['events'].append({'id': event, 'status_line': lines[0].decode('ascii', errors='replace'),
                    'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
                    'header_names': [line.split(b':', 1)[0].decode('ascii', errors='replace') for line in lines[1:] if b':' in line]})
    finally:
        plugin.unload()
    result['reloaded'] = plugin.load()
    plugin.unload()
    print(json.dumps(result))
    return 0

if __name__ == '__main__':
    sys.exit(main())
