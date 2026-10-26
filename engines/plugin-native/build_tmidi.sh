#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
bundle=${1:?Usage: build_tmidi.sh OUTPUT_BUNDLE.plugin}
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun clang++ -std=c++17 -fobjc-arc -dynamiclib -O2 \
  -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
  -framework Foundation "$root/tmidi_plugin.mm" -o "$bundle/Contents/MacOS/OurinTMIDI"
cp "$root/tmidi_windows_bridge.py" "$bundle/Contents/Resources/"
cp "$root/../../docs/compatibility-corpus/tmidi-bridge.md" "$bundle/Contents/Resources/TMIDI_BRIDGE.md"
python3 - "$bundle" <<'PY'
import pathlib,plistlib,sys
p=pathlib.Path(sys.argv[1])/'Contents'
metadata={'CFBundleExecutable':'OurinTMIDI','CFBundleIdentifier':'com.furinlab.ourin.tmidi-bridge',
 'CFBundleName':'TMIDI Messages (Ourin bridge)','CFBundleVersion':'1','CFBundlePackageType':'BNDL',
 'OurinModuleABI':'ourin'}
(p/'Info.plist').write_bytes(plistlib.dumps(metadata))
(p/'Resources'/'descript.txt').write_text('charset,UTF-8\nid,B5F4E3D2-1A6C-4B8E-9F0D-7C8A2E3B1D5F\nname,TMIDI Messages (Ourin bridge)\nfilename,tmidi_msg.dll\nsecondchangeinterval,1\nversion,1.0\n',encoding='utf-8')
PY
codesign --force --sign - "$bundle"
