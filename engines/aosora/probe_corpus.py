#!/usr/bin/env python3
"""Standard sandbox corpus probe with Aosora source-integrity evidence."""
from pathlib import Path
import hashlib
import sys

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'scripts'))
import probe_corpus_content as probe
from corpus_probe.io_util import validate_extracted_root

original = probe.probe_ghost


def dictionary_digest(root):
    files = sorted(p for p in root.rglob('*') if p.is_file() and p.suffix.lower() in {'.as', '.asproj'})
    digest = hashlib.sha256()
    for path in files:
        digest.update(str(path.relative_to(root)).encode())
        digest.update(b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return {'files': len(files), 'sha256': digest.hexdigest()}


def checked(root, *args):
    error = validate_extracted_root(root)
    if error:
        return original(root, *args)
    before = dictionary_digest(root)
    result = original(root, *args)
    after = dictionary_digest(root)
    result.setdefault('checks', {})['dictionary_integrity'] = {
        'before': before, 'after': after, 'unchanged': before == after,
        'scope': 'All .as and .asproj files; generated savedata is separate',
    }
    if before != after:
        result['status'] = 'error'
        result['reason'] = 'dictionary_changed'
    return result


probe.probe_ghost = checked
if __name__ == '__main__':
    raise SystemExit(probe.main())
