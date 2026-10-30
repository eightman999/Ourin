# Installing KAWARI / KAGARI engines

Updated: 2026-10-30. Development documentation.

## Current installation

KAWARI is packaged as `kawari.plugin`, including its dependencies, and imported through the SHIORI engine tab in Ourin's plugin manager. KAGARI retains its existing built-in path. The current `engines/package.sh` embeds KAGARI only.

Use `python3 engines/package-plugins.py` to generate additional packages. See `engines/kawari/README.md` for the pinned KAWARI build, [engine plugins (Japanese)](SHIORI_ENGINE_PLUGINS_ja-jp.md) for installation and conditions, and the [current verification record (Japanese)](SHIORI_PLUGIN_VERIFICATION_2026-10-29.md).

**The following sections preserve the initial packaging record dated 2026-10-25.** Their build commands, bundled artifacts and pending GUI checks describe that earlier stage.

## Pinned upstreams

`engines/PINNED_UPSTREAM.json` records the upstream repositories and exact revisions. Build outputs retain their upstream license notices.

| Engine | Upstream | macOS artifact | OurinShioriABI |
|---|---|---|---|
| KAWARI | [ukatech/kawari](https://github.com/ukatech/kawari) | libkawari_shiori.dylib | ukagaka-long |
| KAGARI | [Tatakinov/kagari_shiori](https://github.com/Tatakinov/kagari_shiori) | libkagari.dylib | kagari |

KAGARI uses its POSIX instance-ID ABI: kagari_load, kagari_request(id, …), kagari_unload. This differs from its Windows ABI. KAWARI uses the POSIX long-width interface, preferring loadu.

## Build

Run `bash engines/package.sh` to build both engines for arm64 and x86_64. Individual scripts are `engines/kawari/build.sh` and `engines/kagari/build.sh`; the latter builds the host architecture unless `OURIN_KAGARI_UNIVERSAL=1` is set.

KAGARI downloads Lua 5.4.4 and sol2 3.2.2 into a local build cache using URLs and SHA-256 values from DEPENDENCIES.json. Local patches enable Apple's Unix path, propagate load failure, and fix sol2's optional reference implementation for Apple Clang.

For isolated verification, `OURIN_KAWARI_ENGINE` and `OURIN_KAGARI_ENGINE` may override the engine paths. App-bundle tests do not require these variables.

## Runtime resolution

Ghost-supplied macOS modules retain priority. Otherwise KAWARI is selected for kawari.dll/kosui.dll, KAGARI for kagari.dll, and KAWARI for shiori.dll when its directory contains kawarirc.ini or kawarirc.kis. Windows path separators are normalized. ScriptBridge's auxiliary KAWARI parser is not a substitute for the upstream engine.

## Xcode packaging

The app's Build and embed native SHIORI engines phase invokes package.sh. It builds when inputs change, verifies both architectures, and copies/signs three dylibs in Contents/Frameworks. ABI declarations go in Resources/EngineMetadata, and full license notices in EngineLicenses. Plain plist sidecars must not be placed in Frameworks because app signing treats its contents as nested code.

KawariKagariEngineTests exercises real bundled engines in process and through XPC, KAGARI unload/reload and load failure, and the instance-ID fixture. The initial related four-suite check passed 42 executions / 35 unique tests, with no failures or skips.

## Real-ghost evidence and limits

- LOBO passed KAWARI boot, conversation, close, save and separate-process reload. The actual Ourin app also resolved shiori.dll to the bundled engine through XPC and received OnBoot text. Visual interaction was unavailable while the Mac was locked.
- Mosu's genuine LuaSocket, luautf8, luachild and lua-iconv dependencies were built for macOS. Its load still fails because saori_universal.native has no available macOS implementation in the tested package. Real-ghost save/reload remains incomplete. No Lua stubs or Windows/Linux binary substitutions were used.
- See [real-ghost results](REAL_GHOST_VERIFICATION_2026-10-25.md) and [Mosu evidence](delegation/kagari-mosu-report.md). Clean-Mac, minimum-OS, Intel hardware and GUI checks are separate gates.
