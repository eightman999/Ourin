# cshiori の macOS SHIOLINK ビルド

[上流 cshiori](https://github.com/Narazaka/cshiori) はCでSHIORIを作るためのフレームワークです。OurinへのWindows DLLの組込みではなく、上流の `shiolink.c` と `shiori_events.c` をmacOS実行ファイルにビルドし、既存のSHIOLINK接続で使います。

```sh
python3 engines/cshiori/build.py
```

出力は `build/engines/cshiori/shiori`。別の出力先には `--output /absolute/path`、取得済みの上流tar.gzには `--archive /absolute/path.tar.gz` を指定できます。いずれも `UPSTREAM.json` の固定revisionとSHA256を検証します。上流のZlibライセンス本文とビルド記録を出力先へ保存します。

移植時には、macOSのstdio関数と衝突する上流独自の `getline` を `cshiori_getline` へ改名します。また、上流サンプルが返す文字列リテラルをフレームワークの解放処理が `free` してクラッシュするため、SHIOLINKエントリポイントで応答ヘッダを所有権のあるコピーに変換します。イベント本文やフレームワークの解放規約は変更しません。上流の `shiori_events.c` はCP932のバイト列のまま保持します。Clangはこのソース文字コードと上流のformat指定に警告を出します。これらは現状の上流コード由来で、日本語応答は実プロセス試験で確認します。

ゴーストの `ghost/master/descript.txt` には `shiori,SHIOLINK.dll` を指定し、同じディレクトリへ次の `SHIOLINK.ourin.ini` を置きます。

```ini
[SHIOLINK]
executable=/absolute/path/to/build/engines/cshiori/shiori
arguments=[]
charmode=Shift_JIS
```

上流サンプルは `version`、`name`、`craftmanw`、`OnBoot`、`OnClose` などに応答します。独自ゴーストを作る際は、サンプルを基に自分のイベント実装をビルドしてください。Ourinへの自動同梱や、既存Windows DLLの直接実行は行いません。

実エンジン試験は `CshioriEngineTests` です。先に上のビルドを実行し、OurinのXcodeテストで対象suiteを選択します。実行ファイルの所在を変更した場合は `OURIN_CSHIORI_EXECUTABLE` を指定できます。試験は本番のfactoryと `ShiolinkAdapter` を通し、Shift_JISの日本語応答、GET/NOTIFY、終了後の子プロセス回収、再ロードを確認します。
