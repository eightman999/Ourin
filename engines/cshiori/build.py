#!/usr/bin/env python3
"""Build the pinned upstream cshiori SHIOLINK example on macOS.

Portability and example response ownership are adapted; shiori_events.c remains byte-identical.
"""
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/engines/cshiori')
    parser.add_argument('--archive', type=Path, help='Use a previously downloaded archive (hash is always verified)')
    args = parser.parse_args()
    pin = json.loads((HERE / 'UPSTREAM.json').read_text())
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ourin-cshiori-build-') as tmp:
        temporary = Path(tmp)
        archive = args.archive
        if archive is None:
            archive = temporary / 'upstream.tar.gz'
            with urllib.request.urlopen(pin['url'], timeout=60) as response:
                data = response.read(16 * 1024 * 1024 + 1)
            if len(data) > 16 * 1024 * 1024:
                raise ValueError('cshiori archive exceeds size limit')
            archive.write_bytes(data)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != pin['sha256']:
            raise ValueError('cshiori upstream SHA256 mismatch')
        source = temporary / 'source'
        source.mkdir()
        with tarfile.open(archive) as tar:
            total = 0
            for member in tar.getmembers():
                parts = PurePosixPath(member.name).parts
                if member.name.startswith('/') or '..' in parts or member.issym() or member.islnk():
                    raise ValueError('unsafe cshiori archive entry')
                if len(parts) < 2:
                    continue
                target = source.joinpath(*parts[1:])
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    total += member.size
                    if total > 64 * 1024 * 1024:
                        raise ValueError('expanded cshiori archive exceeds size limit')
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with tar.extractfile(member) as stream, target.open('wb') as destination:
                        shutil.copyfileobj(stream, destination)
                else:
                    raise ValueError('unsupported cshiori archive entry')
        example_hash = hashlib.sha256((source / 'shiori_events.c').read_bytes()).hexdigest()
        # Altered source: byte-preserving portability patch. Match expected counts
        # so a pin change cannot silently omit a declaration or call site.
        for filename, expected in [('strutl.c', 1), ('strutl.h', 2), ('cshiolink.c', 2)]:
            path = source / filename
            original = path.read_bytes()
            if original.count(b'getline(') != expected:
                raise ValueError('unexpected getline occurrence count: ' + filename)
            path.write_bytes(original.replace(b'getline(', b'cshiori_getline('))
        # The upstream example returns borrowed string literals while cshiori's
        # response destructor frees header values. Adapt ownership at its entry
        # point, leaving the event source and the framework destructor intact.
        entry = source / 'shiolink.c'
        original = entry.read_bytes()
        include = b'#include "shiori_events.c"'
        if original.count(include) != 1:
            raise ValueError('unexpected example entrypoint')
        wrapper = b"""#define shiori_request cshiori_example_request
#include "shiori_events.c"
#undef shiori_request
/* Ourin macOS adaptation: the upstream example borrows literal strings.
 * Return owned header copies required by cshiori_response_message_delete. */
static struct cshiori_response_message* shiori_request(
    struct cshiori_request_message* req, struct cshiori_response_message* res) {
    res = cshiori_example_request(req, res);
    if (res == NULL) return NULL;
    if (res->value) res->value = strdup(res->value);
    if (res->sender) res->sender = strdup(res->sender);
    if (res->charset) res->charset = strdup(res->charset);
    for (size_t i = 0; i < CSHIORI_RESPONSE_MESSAGE_REFERENCE_SIZE; ++i) {
        if (res->reference[i]) res->reference[i] = strdup(res->reference[i]);
    }
    return res;
}"""
        entry.write_bytes(original.replace(include, wrapper))
        subprocess.run([os.environ.get('CC', '/usr/bin/clang'), '-O3', '-DNDEBUG', '-Wall', '-std=c17',
                        '-mmacosx-version-min=13.0', '-o', str(output / 'shiori'), 'shiolink.c', '-lm'],
                       cwd=source, check=True, timeout=60)
        shutil.copyfile(source / pin['license_file'], output / 'LICENSE.cshiori')
        shutil.copyfile(HERE / 'UPSTREAM.json', output / 'UPSTREAM.json')
        (output / 'BUILD.json').write_text(json.dumps({
            'revision': pin['revision'], 'upstream_example_sha256': example_hash,
            'altered_source': 'Private getline renamed for macOS; entrypoint copies borrowed example response strings to satisfy framework ownership.',
            'example_charset': pin['example_charset'], 'transport': 'SHIOLINK',
        }, indent=2) + '\n')
    print('Built pinned cshiori SHIOLINK example: ' + str(output / 'shiori'))


if __name__ == '__main__':
    main()
