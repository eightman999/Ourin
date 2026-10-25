#!/usr/bin/env python3
"""Build self-authored Akari regressions from pinned source and all Ourin patches.
Optional --fixtures ROOT tests unmodified {ukaten,ukadonyu,sudohaikuyu}/payload
with synthetic HTTP data, isolated save state, and no external HTTP requests.
"""
import argparse, hashlib, json, os, pathlib, shutil, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--fixtures', type=pathlib.Path)
args = parser.parse_args()
pin = json.loads((root/'engines/PINNED_UPSTREAM.json').read_text())['utatane_modules']
cache = pathlib.Path(os.environ.get('OURIN_ENGINE_SOURCE_CACHE', root/'build/engine-sources'))
archive = subprocess.check_output(['git','-C',str(cache/'utatane-modules'),'archive',pin['revision'],'native','LICENSE'])
assert hashlib.sha256(archive).hexdigest() == pin['archive_sha256']
def fixture_hashes():
    if not args.fixtures:
        return {}
    return {str(p.relative_to(args.fixtures)): hashlib.sha256(p.read_bytes()).hexdigest()
            for name in ['ukaten', 'ukadonyu', 'sudohaikuyu']
            for p in sorted((args.fixtures/name/'payload').rglob('*')) if p.is_file()}
before = fixture_hashes()
with tempfile.TemporaryDirectory(prefix='ourin-akari-regression-') as temp:
    base = pathlib.Path(temp)
    subprocess.run(['tar','-xf','-','-C',temp],input=archive,check=True)
    for patch in ['macos13.patch','akari-plugin.patch','akari-values.patch']:
        subprocess.run(['patch','-p1','-d',temp],input=(root/'engines/additional'/patch).read_bytes(),check=True)
    package = base/'native'
    # A focused package avoids building unrelated engines or changing shared caches.
    (package/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "OurinAkariRegression", platforms: [.macOS(.v13)], targets: [
.target(name: "ModuleProtocol"),
.target(name: "LegacyTextCodec", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("iconv")]),
.target(name: "LegacyText", dependencies: ["LegacyTextCodec"]),
.target(name: "SaoriClient", dependencies: ["LegacyText"]),
.target(name: "AkariCore", dependencies: ["ModuleProtocol", "SaoriClient"]),
.testTarget(name: "OurinAkariTests", dependencies: ["AkariCore", "ModuleProtocol"])
])
''')
    tests = package/'Tests/OurinAkariTests'; tests.mkdir()
    shutil.copy2(root/'engines/additional/AkariValueRegressionTests.swift',tests)
    env = {key: os.environ[key] for key in ['PATH','HOME','TMPDIR','USER','LOGNAME','LANG','DEVELOPER_DIR'] if key in os.environ}
    if args.fixtures:
        env['OURIN_AKARI_PLUGIN_FIXTURES'] = str(args.fixtures.resolve())
    subprocess.run(['xcrun','swift','test','--package-path',str(package),'--filter','ourinAkari'], env=env, check=True)

assert fixture_hashes() == before, 'Original plugin fixtures changed during regression'
if before:
    print(f'Original plugin fixture files unchanged: {len(before)} SHA-256 checks')
