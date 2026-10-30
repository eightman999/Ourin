# krht の macOS Tcl / SHIOLINK ローカルビルド

[kinokon/krht](https://github.com/kinokon/krht) の固定C++実装を、実Tcl interpreterを使うmacOS子プロセスへ移植します。

```sh
python3 engines/krht/build.py
# 明示する場合（arm64 Macの従来の標準出力先）
python3 engines/krht/build.py --arch arm64
# Intel用を別の出力先へ作成
python3 engines/krht/build.py --arch x86_64 --output build/engines/krht-x86_64
```

krhtとTcl 9.1.0の両アーカイブをrevision/SHA256へ固定します。標準ではTclをソースから静的buildし、必要な実Tcl library/encoding scriptを隣接する `lib/tcl9.1` へ置きます。Homebrew Tclへの依存とmacOS 26専用のリンク条件を除去しました。systemへのインストールや設定変更は行いません。

出力は `build/engines/krht/krht-shiolink` と `lib/tcl9.1`。この2つをまとめて移動できます。hostは実行ファイル位置からTCL_LIBRARYを決定するため、build時の一時pathや利用者のTCL_LIBRARYに依存しません。arm64、およびarm64 Macの既存Rosettaによるx86_64実行で、ビルドと移動先の動作を確認しました。`--arch`省略時は実行中のPythonと同じarchitectureを選ぶため、arm64環境の従来defaultは維持します。Mach-O minimum OSは11.0、SDKは検証環境の26.5、リンク先はOS標準framework/libのみです。Intel実機と古いmacOS実機の動作は未検証です。minimum OS指定や現行SDKでの成功を、その実機検証として扱いません。

取得済みarchiveは `--archive`（krht）、`--tcl-archive`（Tcl）、出力先は `--output` で指定できます。従来の既存Tcl動的リンクを必要とする場合は `--existing-tcl --tcl-prefix /path` を指定します。この従来方式だけはTcl 9.1.0かつmacOS26の条件が残ります。選択architectureと既存Tcl dylibのsliceが一致しない場合は明示的に失敗します。archive、library hash、link方式・deployment target、target/builder architecture、SDK path、compilerは `BUILD.json` に記録します。

元の `shiori,krht.dll` を維持して、DLLと同じ場所へ設定します。

```ini
[SHIOLINK]
module=krht.dll
executable=/absolute/path/to/build/engines/krht/krht-shiolink
arguments=[]
charmode=UTF-8
```

上流のロード契約は `index.tcl` をsourceした後、`_request(ディレクトリ)` を呼び、その戻り値が文字列 `true` なら成功とするものです。`_load` を呼ぶ実装ではありません。この契約を推測変更せず維持し、通常の要求も `_request(電文)`、終了は `_unload` を呼びます。実行は同じ子プロセスの同じthreadに限定し、Tcl interpreterのthread制約を保ちます。

固定上流にはTcl辞書や `index.tcl` の実例がありません。`example/index.tcl` は当方で作成した検証辞書です。日本語応答・絵文字Referenceの往復・Tcl上でのcounter更新・終了時の保存・再load時の復元を実interpreterで行います。第三者配布のkrhtゴーストの実辞書互換性を確認したものではありません。Windowsゴーストやその辞書を変更して不具合を隠す方式ではありません。

`KrhtEngineTests` は本番Factory / ShiolinkAdapterから実processを使い、上記の保存・再起動、NOTIFY、子process回収、不正Tcl source時のload失敗を確認します。先に上のビルドを実行してください。出力先を変えた場合は `OURIN_KRHT_EXECUTABLE` を指定します。追加のIntel用testsは `build/engines/krht-x86_64/krht-shiolink` を使い、変更時は `OURIN_KRHT_X86_64_EXECUTABLE` を指定します。Apple Siliconでは既存Rosettaで `/usr/bin/arch -x86_64 /usr/bin/true` が実行できる場合だけ有効になります。Rosettaやsystem libraryのインストールは行いません。

固定上流にLICENSEや再配布許諾を確認できませんでした。この導線はユーザーが取得して実行する任意のローカルビルドで、Ourinへの自動同梱や配布を追加しません。Tclのライセンス全文と上流の実在するReadMeは成果物へ保存します。移植差分は [PATCHES.md](PATCHES.md) に記録しています。

2026-10-28の追加試験では、runtime一式を日本語を含む別pathへ移し、本番Factoryから会話・終了を確認。不完全要求のEOF（終了コード6）でも実Tclの_unloadが実行されstate.txtが保存されることを確認しました。input行のメモリ上限も1 MiBへ制限しています。

2026-10-28のarchitecture追加試験では、Tcl 9.1.0の同じ固定sourceをarm64/x86_64へ明示して静的buildしました。各hostを日本語を含む別pathへruntime一式と移動し、本番ShiolinkAdapterから日本語・絵文字・NOTIFY・OnClose・counter保存再loadを2回ずつ確認し、子processも回収しました。自作検証辞書のOnArchitectureは実Tclのpatchlevel/tcl_platform(machine)を返し、`9.1.0/arm64` と `9.1.0/x86_64` を確認しています。x86_64は既存Rosettaでの実行です。両architectureとも不完全要求のEOFで実_unloadがstate.txtを書き、終了コード6になることを確認しました。Intel実機・macOS 11実機の検証結果ではありません。
