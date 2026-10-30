#!/usr/bin/env python3
"""Stage the real pinned emo-gs NAR without rewriting its dictionary or framework."""
import argparse,hashlib,json,stat,urllib.request,zipfile
from pathlib import Path,PurePosixPath
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path)
    parser.add_argument('--output',type=Path,default=ROOT/'build/engines/emo-rs-lua54/distribution/emo-gs')
    args=parser.parse_args();pin=json.loads((HERE/'DISTRIBUTION.json').read_text())
    output=args.output.resolve()
    if output.exists():raise ValueError('Use a new output directory; existing fixtures are preserved')
    archive=args.archive
    if archive is None:
        archive=ROOT/'build/deps/emo-rs-lua54/emo-gs.nar';archive.parent.mkdir(parents=True,exist_ok=True)
        with urllib.request.urlopen(pin['url'],timeout=60) as response:data=response.read(16*1024*1024+1)
        if len(data)>16*1024*1024:raise ValueError('archive too large')
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=pin['sha256']:raise ValueError('NAR checksum mismatch')
    manifest={};total=0
    with zipfile.ZipFile(archive) as nar:
        for item in nar.infolist():
            name=item.filename.replace('\\','/')
            if name=='/' and item.filename=='\\':continue # upstream root directory marker
            parts=PurePosixPath(name).parts
            if name.startswith('/') or '..' in parts or ':' in name or stat.S_ISLNK(item.external_attr>>16):raise ValueError('unsafe NAR entry')
            if name.endswith('/'):continue
            if name in manifest:raise ValueError('duplicate NAR file')
            total+=item.file_size
            if total>128*1024*1024:raise ValueError('expanded archive too large')
            data=nar.read(item);dest=output.joinpath(*parts)
            dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
            manifest[name]=hashlib.sha256(data).hexdigest()
    (output/'OURIN-ORIGINAL-FILES.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
    (output/'OURIN-DISTRIBUTION.json').write_text(json.dumps(pin,indent=2)+'\n')
    print('Staged original distribution: '+str(output))
if __name__=='__main__':main()
