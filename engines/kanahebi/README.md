# Optional local Kanahebi / IronPython host

This macOS SHIOLINK host executes the actual pinned Kanahebi `ModuleMain.cs` with IronPython **3.4.2** on .NET 10. `ModuleMain.cs` is copied byte for byte. It creates the Python engine, executes `main.py`, invokes the script's `request` function and releases its references on unload. No built-in talk responses replace Python execution.

The upstream project references IronPython 3.4.1. That runtime fails on .NET 10 during Python class/stdlib initialization (`NewTypeMaker.ImplementCTDOverride`, missing method signature). This port uses the official [3.4.2 release](https://github.com/IronLanguages/ironpython3/releases/tag/v3.4.2), which fixes the .NET 9 compatibility issue; real file save/reload is verified on .NET 10. The dictionary and ModuleMain remain unchanged.

## Local build

```sh
python3 engines/kanahebi/build.py
```

.NET SDK **10.0.401** is required. `--dotnet`, `--output`, and `--archive` select the tool, products directory and a verified offline upstream archive. Restore uses an isolated cache, explicit nuget.org source, and checked-in `--locked-mode` dependencies. The pinned upstream archive and original sample have SHA-256 records in `UPSTREAM.json`; all NuGet dependency versions/content hashes are in `locks/packages.lock.json`. Products require a .NET 10 runtime and are written to `build/engines/kanahebi`.

The upstream repository has **no project LICENSE**. This is a local build and is not automatically embedded or published. The separate local plug-in staging command below preserves this licensing boundary. No redistribution permission for Kanahebi is established here. Its readme only acknowledges IronPython's separate license. Dependency notices and nuspecs are retained in product `NuGetNotices`: IronPython and DynamicLanguageRuntime Apache-2.0, Mono.Unix MIT, IronPython.StdLib Python license notices, and System.CodeDom MIT/third-party notices. Mono.Unix's missing package license text is included from the exact source commit in its nuspec, with URL/hash recorded separately.

The old shipped .NET Framework binaries, Windows ukastream DLL and WPF integration are not used. NuGet supplies the managed engine and platform dependencies. The same-version IronPython.StdLib package supplies the actual `Lib` directory, selected through `IRONPYTHONPATH` before the unchanged engine initializes. This is needed even for UTF-8 `open()` when reloading saved state. Arbitrary external imports and Windows-specific scripts remain outside the verified scope.

## Use with the original module name

Place `SHIOLINK.ourin.ini` beside the configured `Kanahebi.dll` path:

```ini
[SHIOLINK]
module=Kanahebi.dll
executable=/opt/homebrew/bin/dotnet
arguments=["/absolute/products/KanahebiHost.dll"]
charmode=UTF-8
```

The descriptor can retain its original module name. The load path uses UTF-8, while SHIORI requests and responses use their declared Charset. The original sample declares Shift_JIS and returns **SHIORI/2.2** `Sentence`; Ourin's production `ShiolinkAdapter` uses its existing SHIORI 2.x compatibility conversion for event requests and response normalization. The sample is not rewritten to SHIORI 3.0.

## Port scope

Only the old BRIDGE/1.0 entrypoint in `UkastreamInterface.cs` is removed, together with an unavailable unused `System.Net.Configuration` import. Its actual `ModuleMode` enum and helpers remain. The new host sets SHIORI mode and calls `ModuleMain` directly, so load and script errors fail visibly instead of being swallowed by the legacy bridge's catch blocks. SAORI mode is not provided.

The host adds CRLF SHIOLINK framing, explicit encoding, 1 MiB frame limits and EOF cleanup. It changes cwd to the module directory for relative dictionary files. IronPython opens OS stdout directly; `Console.SetOut` alone does not isolate Python `print()`. The macOS host duplicates the original stdout for protocol writes, then redirects fd 1 to stderr with `dup`/`dup2`, preserving the unmodified Python lifecycle while preventing prints from corrupting SHIORI frames.

`ModuleMain.Unload` does not call a Python unload callback. No such hook is invented by this port. The separate `example/main.py` saves its boot counter during `OnBoot`, which demonstrates real Python file IO and persistence across process unload/reload. This does not imply the original sample implements persistence.

## Verification

The original `Sample/main.py` is copied byte for byte as `upstream-sample-main.py`. Its CP932 Japanese OnBoot/OnMouseDoubleClick responses, NOTIFY normalization, unknown events, two process lifecycles and child reaping are exercised through the production adapter. The separate Python 3 test dictionary covers actual `print()`, Japanese/emoji echo, persisted boot counts and OnClose. Invalid Python syntax fails loading; partial-request EOF exits without a busy loop.

Four optional `KanahebiEngineTests` cover those paths. Build products enable them, or set `OURIN_KANAHEBI_PRODUCTS` and `OURIN_KANAHEBI_DOTNET`. Every distributed Kanahebi dictionary, external Python imports, SAORI and Windows APIs remain unverified.

## ローカル生成エンジンプラグイン

`python3 engines/package-dotnet-engines.py --destination /absolute/staging` は、Kanahebiを **.NET runtime 10.0.12** とIronPython/StdLib込みで別プラグイン用にstageします。外部のdotnet/SDKを実行時に要求しません。stage自体はOurinへのインストール・外部公開を行いません。従来の任意外部host経路も使用できます。

単体は `python3 engines/kanahebi/build.py --self-contained --runtime osx-arm64 --output /absolute/products`。Intelは `--runtime osx-x64`。RID別の固定NuGet lockと明示runtime版を使用します。stageの既定はビルド機architectureで、両方を作るには `--runtime` を繰り返します。`.NET`・NuGetのライセンス本文/noticeをstageへ同梱します。**Kanahebi本体の再配布許諾未確認という境界は変わりません**。生成物はローカル利用の範囲で扱い、公開可能なプラグインと混同しないでください。
