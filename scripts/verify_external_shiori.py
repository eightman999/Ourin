#!/usr/bin/env python3
"""Compile the actual adapters and smoke-test a temporary copy of an external engine.
No downloads or package installation; provide a trusted, prepared source directory.
"""
import argparse
import pathlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('engine', choices=['rishu', 'miyo'])
parser.add_argument('source', type=pathlib.Path, help='Rishu distribution or prepared SHIOLINK master directory')
args = parser.parse_args()
repo = pathlib.Path(__file__).resolve().parents[1]
source = args.source.resolve(strict=True)
with tempfile.TemporaryDirectory(prefix='Ourin-external-shiori-') as temporary:
    root = pathlib.Path(temporary)
    ghost = root / 'master'
    shutil.copytree(source, ghost)
    (root / 'Stubs.swift').write_text('import Foundation\nstruct DicEntry {}\nclass ResourceManager {}\n')
    main = r'''
import Foundation
import Darwin
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let isRishu = CommandLine.arguments[2] == "rishu"
let runtime: any GhostShioriRuntime = isRishu ? RishuProxyAdapter() : ShiolinkAdapter()
precondition(runtime.load(context: .init(ghostURL: root, ghostRoot: root, moduleName: isRishu ? "rishu_proxy.dll" : "SHIOLINK.dll")), "LOAD failed")
let pid = isRishu ? (runtime as! RishuProxyAdapter).lastProcessIdentifier! : (runtime as! ShiolinkAdapter).lastProcessIdentifier!
if isRishu {
    for verb in ["GET", "NOTIFY"] {
        let response = runtime.request(method: verb, id: "OnBoot", refs: ["桜鈴"], timeout: 3)!
        precondition(response.status == 200 && response.headers?["Reference0"] == "桜鈴", "Official echo sample response mismatch")
        print("PASS Rishu original sample \(verb): Shift_JIS and Content-Length framing")
    }
} else {
    for event in ["OnBoot", "OnClose"] {
        let response = runtime.request(method: "GET", id: event, timeout: 3)!
        precondition(response.status == 200 && response.value?.isEmpty == false, "No SakuraScript Value")
        print("PASS Miyo \(event): \(response.value!)")
    }
}
runtime.unload()
precondition(kill(pid, 0) == -1 && errno == ESRCH, "Child remains after unload")
print("PASS LOAD / request / UNLOAD / process reaping")
'''
    (root / 'main.swift').write_text(main)
    files = ['Ourin/SSTP/EncodingAdapter.swift', 'Ourin/USL/ShioriRuntime.swift',
             'Ourin/USL/ShiolinkAdapter.swift', 'Ourin/USL/RishuProxyAdapter.swift']
    binary = root / 'verify'
    subprocess.run(['xcrun', 'swiftc', str(root / 'Stubs.swift'),
                    *[str(repo / path) for path in files], str(root / 'main.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(ghost), args.engine], check=True, timeout=30)
