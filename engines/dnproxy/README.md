# D.N.Proxy managed modules on macOS

This optional SHIOLINK host uses the unchanged upstream `Ukagaka.NET.Interfaces` source and the actual upstream `D.N.Logger` file logger. It can compile a ghost's existing C# or Visual Basic sources from `dnproxy.ini` at load time using the real Roslyn compilers, or load a precompiled pure-managed module. It does not provide the Windows `dnproxy.dll` exports.

## Build

```sh
python3 engines/dnproxy/build.py
```

.NET SDK **10.0.401** is required. `--dotnet`, `--output`, `--archive`, and `--crawler-archive` select tools, output and verified offline archives. `UPSTREAM.json` pins both repositories, archive SHA-256, SDK and compiler versions. Checked-in locks pin the complete NuGet graph/content hashes; restore uses an isolated cache and explicit nuget.org source. Microsoft.CodeAnalysis.CSharp and VisualBasic **4.14.0** provide the actual compilers. Package licenses, notices, nuspecs and locks accompany the products in `build/engines/dnproxy`. A .NET 10 runtime is required; the SDK is not needed when loading a dictionary. Products are not automatically embedded in Ourin.

## Use an existing dnproxy.ini

Put `SHIOLINK.ourin.ini` beside the existing module path; retain the ghost's original descriptor, `dnproxy.ini` and source files:

```ini
[SHIOLINK]
module=dnproxy.dll
executable=/opt/homebrew/bin/dotnet
arguments=["/absolute/products/DnProxyHost.dll"]
charmode=UTF-8
```

With no module arguments, the host reads `dnproxy.ini` from the load directory. `arguments=["/absolute/products/DnProxyHost.dll","--config","custom.ini"]` selects another configuration relative to that directory.

The parser follows upstream `dnutil/Compiler.cs`: case-insensitive colon keys, `//` comments, continuation lines, comma lists, recursive directories and `directory|glob`. Relative paths and Windows path separators resolve against the configuration directory. Missing inputs and unknown settings fail explicitly. It supports `Language` CSharp/C#/CS and VisualBasic/VB/VB.NET; `SourceFiles`, `MainClass`, `OutputAssembly`, `GenerateExecutable: 0`, `GenerateInMemory`, `IncludeDebugInformation`, `CompilerOptions`, `WarningLevel`, `TreatWarningsAsErrors`, `ReferencedAssemblies`, and `EmbeddedResources`.

Roslyn parses language-specific compiler flags, including `/optimize`, `/define`, `/unsafe`, `/checked`, `/langversion`, `/codepage`, VB `/optionstrict`, and `/optioninfer`. Source/reference/resource lists belong in their named ini keys; analyzer options and extra source/resource inputs through CompilerOptions are rejected. Legacy GAC framework names resolve to .NET 10 platform assemblies. `Ukagaka.NET.Interfaces.dll` resolves to the real upstream interface assembly, and `dnutil.dll` to the actual Logger port. Other managed references must exist; no dummy namespaces or missing-reference substitutions are generated. VB portable libraries use the same `_MyType="Empty"` default as the .NET SDK, without desktop My.Application/Devices APIs.

Compilation reads the original sources without rewriting them, emits to a private OS temporary directory, and cleans that directory when the process unloads or fails. It never writes `user.dll`, a compiler cache or generated code into the ghost. `OutputAssembly` selects the temporary assembly's name; both GenerateInMemory modes retain this process-local lifetime. `MainClass` defaults to the upstream Settings default `Unknown.User`. Custom `dnproxy.dll.config` application settings are not loaded. Executable output, Win32 resources, linked resources and desktop VB MyType are rejected. This is a deliberate portable-library contract; it does not recreate CodeDom/AppDomain behavior.

## Managed execution contract

The module must implement the actual upstream `IShiori30` interface and expose `public string request(string)`. The host transfers the UTF-8 load-path pointer and byte count through the real `load(IntPtr, int)` interface. The module owns/frees that pointer. Requests and responses use their declared SHIORI Charset, including CP932; SHIOLINK control lines and the load path use UTF-8 with bounded CRLF framing and EOF cleanup.

The string overload avoids Windows ANSI pointer allocation/length ambiguity on Unix. A module exposing only the native pointer request overload is rejected. Native PE exports, Remoting/AppDomain isolation, WinForms and Win32 P/Invoke are outside the supported contract. The official WinForms sample is excluded.

For precompiled modules the prior arguments remain valid:

```ini
arguments=["/absolute/products/DnProxyHost.dll","/absolute/products/CrawlerGhost.dll","Ukagaka.NET.Shiori"]
```

The `dnutil` assembly exposes the upstream **Logger API only**: file logging is retained, the unused WinForms import is removed, Windows receiver lookup is guarded, and assigning a nonzero Win32 receiver on macOS throws. The legacy D.N.Compiler/Generator/Manager/Settings API is not recreated inside dictionary code; ini compilation is performed by the host.

## Real dictionaries and validation

The build copies the pinned `nikolat/crawler_uploader` C# sources and its exact `dnproxy.ini` to `upstream-crawler`, preserving their bytes. `CRAWLER_SOURCES.json` and `CRAWLER_INI.sha256` record hashes. Its original config selects the real sources recursively, MainClass and system/interface/dnutil references. The host compiles this unmodified dictionary at load time, then exercises its actual CP932 metadata, random OnBoot scripts, OnClose, NOTIFY and two process lifecycles through production `ShiolinkAdapter`. Tests mark those source/config files read-only, compare them afterwards and check that compiler artifacts were not placed in the ghost. This dictionary has no persistence implementation; that remains its actual behavior.

Separate C# and Visual Basic examples exercise both real compilers, the upstream ABI and Logger, UTF-8 Japanese/emoji, save on unload and reload across two processes, nested source selection, continuation references and debugging/optimization settings. Invalid C# source and unsupported executable configuration fail loading and reap the child. These are explicit test dictionaries; they do not replace crawler logic. Optional `DnProxyEngineTests` also retain the precompiled-module checks. Build products enable them, or set `OURIN_DNPROXY_PRODUCTS` and `OURIN_DNPROXY_DOTNET`.

D.N.Proxy's pinned upstream is CC0. Crawler dictionary/text is NYSDL 0.9982; its readme accompanies products. No shell/image assets are copied. This validation does not prove every distributed D.N.Proxy ghost, arbitrary referenced APIs, all compiler options, resources or Windows UI behavior.

## Standalone engine plug-in products

`python3 engines/package-dotnet-engines.py --destination /absolute/staging` stages D.N.Proxy, Kanahebi and Rosalind with their own pinned **.NET runtime 10.0.12**. Ourin can install the generated engine plug-in separately; execution does not require an SDK, a global `dotnet`, or a ghost-side SHIOLINK configuration. This staging command does not publish or install anything by itself. It writes `dotnet-manifest.json` for the plug-in packager.

For this engine alone, run `python3 engines/dnproxy/build.py --self-contained --runtime osx-arm64 --output /absolute/products`. `--runtime osx-x64` builds an Intel variant. These publishes use separate checked-in RID lockfiles and an exact runtime version; they keep the real Roslyn compilers, upstream interface and Logger. The stage command defaults to the build host's architecture and can repeat `--runtime` to stage both. Dependency and .NET runtime license/third-party notices accompany each staged engine. No Windows-native API compatibility is implied.
