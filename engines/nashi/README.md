# なし栞 1.0.4-alpha系 — Ourin用macOS移植

このソフトウェアは「なし栞 + なしスタジオ」をもとにしています。
https://github.com/yanashi-interface/nashi-shiori-studio
作者: 月見里　彩葉（元表記 miyagawa-yukinterface、現アカウント yanashi-interface）

**OurinによるmacOS移植版です。公式のWindows DLLそのものではありません。**

```sh
python3 engines/nashi/build.py
python3 engines/nashi/package.py --destination build/engines/nashi-plugins
python3 engines/nashi/verify.py build/engines/nashi/nashi-shiolink
```

固定revision・SHA256は`UPSTREAM.json`に記録した公式main（VERSIONは1.0.4-alpha）を使用します。作者が通常利用に推奨する安定版v1.0.3のarchiveにはLICENSEがなく、mainの未リリース変更で初めて許諾が明記されました。許諾されたsourceから移植するためmainを採用しています。公開pre-release v1.0.4-betaは作者が「don't use」と表示しており、採用しません。mainのJSON・Program・interpreter・SHIORI protocolの4ソースは安定版とバイト単位で同じです。上流の`GET version`は定数`1.0.0`を返すため、そのまま保持し、source/package版と区別します。

上流の`json.cpp`、`program.cpp`、`interp.cpp`、`shiori.cpp`、`util.cpp`、`saori.cpp`を未変更でコンパイルします。Windows DLL entryとWindows CRTを使わず、macOSのファイル・時刻・iconv・mutex/pthread・dlopenへ接続する境界とOurin ABIを追加します。辞書blockの独自再実装や、元ghost.jsonの書換えは行いません。CP932 source/wire変換も実上流経路を通します。macOSのmodule load先はUTF-8です。

プラグインの出力はmacOS 13以降のUniversal2 **`nashi-shiolink`**。`nashi.dll`、`ghost.json`または`nashi.json`から選択し、通常のSHIOLINK process経路で動かします。1 ghostに1つの実Shiori/子processを割り当て、辞書・変数を分離します。外部言語runtimeやHomebrewはエンドユーザーに不要です。`--arch arm64/x86_64`で片方だけのビルドもできます。buildは既存Command Line ToolsのcompilerとSDKを明示し、同意操作やシステム設定は変更しません。

`libnashi.dylib`（Ourin ABI）も単体回帰用に生成しますが、module内global VMを共有するため、通常のプラグインには使いません。Native/XPCサービス内でも同じimageを複数接続が共有し得るためです。プラグインが使うSHIOLINK executableは上流coreを静的リンクし、この問題を避けます。

辞書は上流の`nashi/1` JSON形式、保存は元の`nashi_save.json`です。変数・会話・条件・関数・選択肢・タイマー・SAORI等のblockは上流interpreterが処理します。既存のWindows PE SAORIはmacOSで実行しません。ghost内のmacOS `.dylib/.so` SAORIはmalloc/freeとC long長の標準ABIで接続します。異なるallocator/ABIのSAORI、なしスタジオの編集GUI、全第三者ghost、Intel/古いmacOSの実機は未確認です。非同期SAORIがunloadを越える場合のコード寿命を守るため、ロードしたSAORIのcode imageはprocess終了まで保持します。元のunload callbackと保存は実行し、子process終了時にimageも解放されます。

元の**なしライセンス1.1**は利用・改変・組み込み・再配布を許諾しています。移植版には元LICENSE、帰属、変更通知を同梱します。プラグインの外部公開は今回実行しません。

## 検証

- 実子process2個で異なる辞書を同時load。一方の終了後も他方の変数・要求応答を保持。両方の保存・再loadを確認。
- Unicode/emoji、日本語path、CP932要求、NOTIFYによる変数更新、途中要求EOF後の保存。元ghost.jsonは不変。
- `--arch x86_64`でRosetta上の実Intel processにも同じ並行VM/保存/Unicode/CP932試験を実行してPASS。Intel実機の確認とは区別します。
- 上流の未改変`behavior.js`と元fixtureで**16場面・81項目PASS**。macOSのテストhostへ接続し、実SAORIの同期/非同期、遅いSAORI処理中のunloadも含む。
- 上流`check-blocks.js`でblock47種・情報19種・演算11種の定義/実装/説明/テスト対応を確認。時計等の毎回変わる情報は上流の一致試験にも含まれず、この静的確認を全blockの実動作証明と呼びません。

Ourin側のfactory/adapter回帰は`NashiEngineTests`。fixtureは`engines/nashi/fixture.json`で、第三者配布ghostと区別します。
