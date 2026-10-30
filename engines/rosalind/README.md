# Rosalind の macOS SHIOLINK ビルド

[上流Rosalind](https://github.com/as-is-prog/rosalind)に既にあるmodern .NET C#実装を、固定revisionからビルドします。Windows DLLを実行せず、実Rosalind／Roslynが `Ghost.csx` をコンパイル・実行します。

```sh
python3 engines/rosalind/build.py
```

必要環境はmacOSと **.NET SDK 10.0.401**（既定 `/opt/homebrew/bin/dotnet`、`--dotnet` で変更可能）。SDKは自動インストールしません。上流はnet6.0／netstandard2.0ですが、今回のビルドでは利用可能な固定SDKに合わせて両projectをnet10.0へ変更します。成果物はframework-dependentで、実行時にも.NET 10 runtimeが必要です。異なるSDKへ黙って切り替えません。

出力は `build/engines/rosalind/`（`--output` で変更可）。取得済み上流アーカイブは `--archive` で指定可能で、SHA256を必ず検証します。上流revision/hashは `UPSTREAM.json`、NuGet依存全体の版とcontentHashは `locks/` に固定。restoreはlocked modeとnuget.orgだけの専用設定、一時NuGet cacheを使用し、ユーザーのNuGetソース・認証設定を読みません。上流MIT本文、依存一覧、各NuGet packageのlicense/notice/nuspecも成果物へ保存します。

## 接続例

`ghost/master/SHIOLINK.ourin.ini`:

```ini
[SHIOLINK]
executable=/opt/homebrew/bin/dotnet
arguments=["/absolute/path/to/build/engines/rosalind/Rosalind.NET.CSharp.dll"]
charmode=UTF-8
```

`descript.txt` には `shiori,SHIOLINK.dll` を指定します。`Ghost.csx` と必要なC# scriptはSHIORIのディレクトリに配置します。検証用自作辞書 `example/Ghost.csx` の `@ROSALIND_PRODUCTS@` は成果物の絶対パスに置換します。これは実RosalindのGhost／SaveDataManagerを使う最小例であり、第三者配布ゴーストの改変版ではありません。

## 移植差分

- Windowsの固定XML文書出力先を除去。Costura.Fodyによる単一EXE化を使わず通常publish。
- POSIXでもSHIOLINKのCRLFを正しく読み、LFも受け付ける。EOF／不完全な要求でbusy loopせず、既存Rosalindのunload保存を実行して終了。
- sync echoとresponseのCRLF、flushを明示し、`Console.WriteLine` による余分なLFを挟まない。
- 実イベントdispatch、C# scripting、Rosalindの保存処理は上流を利用する。移植差分全体は `patches/001-posix-shiolink.patch`。
- 上流のNOTIFYは本文なしの200を返す。この状態コードは変更せず、Ourin側で受け取れることを確認する。
- 上流の `CompileErrorGhost` はC#コンパイルエラーを200応答のトークに変換する。テストはstatusだけでなく期待する日本語本文・保存値を照合し、これを正常会話と数えない。

`RosalindEngineTests` は本番Factory／ShiolinkAdapter経由の起動、日本語・絵文字応答、GET/NOTIFY、終了・子回収、保存・別process再loadと、要求途中EOFを検証します。未ビルド環境では明示skip。実行ファイルの所在は `OURIN_ROSALIND_PRODUCTS`／`OURIN_ROSALIND_DOTNET` で変更できます。

自動同梱・本番配布、全C#辞書、.NET Framework依存の第三者ゴースト、任意の追加DLL、Windows P/Invokeを必要とする辞書は今回の検証範囲ではありません。

## 実測記録

2026-10-26、固定アーカイブから隔離NuGet restore／publish成功。独立Swift probeに本番の `ShiolinkAdapter`、`ShioriWireCodec`、`EncodingAdapter` をコンパイルして接続し、実Rosalind/RoslynのC# scriptで2 lifecycle、日本語＋絵文字の応答、GET/NOTIFY、`savedata.json`のBoots=1→2、子process回収を確認。要求途中でstdinを閉じた実processは終了コード0で保存して終了。通常Factoryを含むXcode試験は親の `RosalindEngineTests` 実行で確認する。

## 自己完結エンジンプラグイン

`python3 engines/package-dotnet-engines.py --destination /absolute/staging` は、Rosalindを **.NET runtime 10.0.12** 込みの別プラグイン用stageへ出力します。実行機にはdotnet/SDKやHomebrewを要求しません。Ourinのプラグインpackagerは `dotnet-manifest.json` の相対executableを使います。このstage処理自体はインストール・外部公開を行いません。

単体の自己完結publishは `python3 engines/rosalind/build.py --self-contained --runtime osx-arm64 --output /absolute/products`。Intelは `--runtime osx-x64`。RID別の固定NuGet lockと明示runtime版を使い、実Rosalind/Roslynを保ちます。stage既定はビルド機architectureで、両architectureには `--runtime` を繰り返します。各stageには上流MIT、NuGet依存と.NET runtimeのライセンス/third-party noticesを含めます。
