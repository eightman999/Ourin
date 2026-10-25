# Additional SHIORI compatibility engines

Updated: 2026-10-25. These additions target the development version and are not included in the published v0.0.1.21 binary.

Ourin bundles native macOS compatibility implementations of Akari, ese-shiori, NiseShiori, Shino, Hisui, Yuhna, and Misaka. These are separately attributed MIT-licensed dependencies from [opera7133/utatane-modules](https://github.com/opera7133/utatane-modules), not the original Windows DLLs. Complete original-engine or ghost compatibility is not claimed. Yuhna support is experimental.

| Engine | `descript.txt` | Bundled library | Typical dictionary input | New state file |
| --- | --- | --- | --- | --- |
| Akari | `shiori,akari.dll` | `libakari.dylib` | `.txt` / `.azr` | `akari-vars.json` |
| ese-shiori | `shiori,ese-shiori.dll` | `libese-shiori.dylib` | `eseai.ini` / `eseai_*.txt` | `ese-shiori-state.json` |
| NiseShiori | `shiori,niseshiori.dll` | `libniseshiori.dylib` | `ai*.txt` / `.dtx` | `nise-shiori-state.json` |
| Shino | `shiori,shino.dll` | `libshino.dylib` | `ai*.txt` | `shino-state.json` |
| Hisui | `shiori,hisui.dll` | `libhisui.dylib` | `hisui_base/*.tlk` and related files | `hisui-state.json` |
| Yuhna (experimental) | `shiori,yuhna.dll` | `libyuhna.dylib` | `dic.ydf` (YDF/1.07) | `yuhna-state.json` |
| Misaka | `shiori,misaka.dll` | `libmisaka.dylib` | `misaka.ini` / dictionaries | `misaka_vars.json` |

Ordinary SHIORI selection reaches the native runtime. For nested names such as `shiori\akari.dll`, `loadu` receives the original DLL's dictionary directory, not the app's Frameworks directory. Ghost-local macOS modules take precedence. `nise-shiori.dll` is also recognized. Ambiguous names such as `shiori.dll` or `ai*.txt` alone do not select one of these seven engines.

State defaults to the dictionary directory. An explicitly supplied upstream-compatible `UTATANE_GHOST_STATE_DIR` absolute path overrides it. Ourin does not mutate this process-wide environment variable per ghost. Comprehensive migration from original Windows save formats is unverified.

## Source and licensing

- Pinned revision: `d0cc4cfa3d06aade166363d3864b56e750852328`.
- SHA-256 of `git archive REV native LICENSE`: `613ca0cf0b02d68062cc66f3d743620ebdacb8c0e7c0cbcc6dbbec0c702c4054`.
- [Pinned MIT license](https://github.com/opera7133/utatane-modules/blob/d0cc4cfa3d06aade166363d3864b56e750852328/LICENSE): Copyright (c) 2026 opera7133.
- Ourin patch: change `native/Package.swift`'s minimum macOS version from 14 to 13.
- Original Windows implementations have separate licenses. Ourin's Apache-2.0 license is unchanged.

`engines/additional/build.sh` verifies the pinned source archive, applies the deployment-target patch, and builds arm64 / x86_64 libraries with SwiftPM. It does not consume the catalog's macOS 14 prebuilt artifacts. All seven libraries declare `OurinShioriABI=ukagaka-int32`, using 32-bit length arguments and standard malloc/free ownership for `loadu/load/request/unload`.

`engines/package.sh` embeds signed libraries in Frameworks, ABI declarations in Resources/EngineMetadata, and the full MIT license, attribution NOTICE, and pin manifest in Resources/EngineLicenses. The development output directory also contains binary `SHA256SUMS`.

## Verification and limitations (2026-10-25)

`engines/additional/verify.py` copies Ourin-authored minimal dictionaries to temporary directories and exercises actual compiled libraries. Akari, ese-shiori, NiseShiori, Shino, Hisui, and Yuhna passed the following on both arm64 and Rosetta x86_64:

- `loadu` with a Japanese directory name; OnBoot, OnAITalk, OnClose, and a 204 response for an undefined NOTIFY.
- Assigning 37 using each engine's dictionary syntax, saving state, and unloading.
- Reloading in a separate process; OnRecall returns 37 before OnBoot or any assignment event can reset it.
- Rejecting a duplicate singleton load without corrupting the first session; leaving fixture dictionaries unchanged.

`vtool` confirmed `minos 13.0` for all 14 architecture slices of the seven libraries. Execution used macOS 26.6.2 and Swift 6.3.3. This is not a physical macOS 13 or Intel Mac verification.

App-path regression coverage lives in `AdditionalShioriEngineTests` (in-process / real XPC / production factory / save-reload / duplicate-load state protection) and `MisakaEngineTests`; consult the overall verification record for their results. Real-ghost GUI behavior, SAORI, complete language compatibility, Windows-engine response comparisons, and save-format migration remain unverified for these new engines.

The upstream standard ABI uses a process-wide singleton per engine. Loading the same library twice in one process rejects the second session. Ourin creates an XPC session per connection, but separate connections do not guarantee separate PIDs. Simultaneous ghosts using the same engine are therefore not claimed as supported. These single-engine checks also do not certify every combination of different engines.

Reproduction:

```sh
bash engines/additional/build.sh
python3 engines/additional/verify.py --output /tmp/ourin-additional-results.json
arch -x86_64 /usr/bin/python3 engines/additional/verify.py --output /tmp/ourin-additional-x86-results.json
```

The six affected suites passed 59 aggregate tests / 99 executions with no failures. See the [development verification record](SHIORI_EXPANSION_VERIFICATION_2026-10-25.md) for the complete run and limitations.
