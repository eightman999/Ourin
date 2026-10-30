# なし栞・AYA5互換・公式YAYA最新版の追加

2026-10-30（JST）。0.2.0公開前の機能追加段階における実装と検証記録。最終配布物の検証は[0.2.0リリースノート](RELEASE_NOTES_0.2.0_ja-jp.md)を参照。commit/push・追加パッケージの外部公開・利用者の実ghostの編集は行っていない。

## 追加したパッケージ

| パッケージ | 入力・実装 | 範囲 |
|---|---|---|
| `yaya.plugin` | [公式stable Tc607-2](https://github.com/YAYA-shiori/yaya-shiori/releases/tag/Tc607-2)、2026-10-19公開、revision `21b6c8317bd68561286c2109673f178f1d12173b` | 公式POSIX実装と固定5依存。Ourin独自VMと区別。multi-instanceのNative/XPC接続 |
| `aya.plugin` | 同じ公式YAYAを使うAYA5互換構成 | `aya.txt` / `aya5.txt`とAYA DLL名を認識。原本AYA5やAYA1〜4を移植したものではない |
| `nashi.plugin` | [なし栞公式main](https://github.com/yanashi-interface/nashi-shiori-studio)、revision `970146932de3dc6d9212be5a7ba80a9138f13638`、1.0.4-alpha系 | 許諾のある公開sourceの実interpreterをmacOSへ接続。SHIOLINKの1ghost1子process、`ghost.json`と保存。上流version応答1.0.0は保持 |

新3種はいずれもUniversal2・macOS13以降。必要な実装を同梱し、実行時のHomebrew・言語runtimeインストールは不要。既存19を含め**22パッケージ（実行用17・開発用5）**を生成した。

なし栞v1.0.3 archiveにはLICENSEがなく、後続mainのCHANGELOGでライセンス追加を確認したため、許諾を明示したmainを使用する。作者が利用を避けるよう記載したbetaを推奨版とは扱わない。改変箇所と元作者・project・ライセンスを成果物へ保持する。

## 接続の変更

- 導入済みの公式Nativeエンジンを、従来の`.yaya`種別による内蔵VM選択より先に解決する。ゴーストローカルのmacOS moduleは優先する。
- 曖昧な一致・失効した明示割当・不正なOurin用transport設定を、旧VMへの成功扱いで隠さない。
- `OurinShioriABI=yaya`で公式`multi_loadu` / `multi_request` / `multi_unload`を接続。C longのID・長さを保持し、ID=0を拒否する。
- Nativeプラグインのcharsetを、ゴーストのencoding/forceEncodingが未指定の場合だけ適用。設定ファイルを書き換えず、AYA5のCP932文字を要求と応答で往復する。
- 最新Xcodeのlipoでも、埋め込むKAGARIのarm64/x86_64両sliceを検査できるよう`-archs`の出力を確認する。

## 確認結果

| 層 | 結果 |
|---|---|
| アプリ関連6suite | **46 test PASS、skip 0**。実行用17の実.plugin導入・Factory・GET/NOTIFY・終了・再ロード、元fixture保持 |
| 公式YAYA上流smoke | 未改変の`tests/posix_smoke.c`を公式Tc607-2へ接続。**arm64 110＋Rosetta x86_64 110＝220 PASS、NG 0** |
| YAYA / AYAの本番Native別probe | 両variant・両CPUの4ケースPASS。日本語/emoji、CP932拡張、複数VM独立、片方終了後の他方継続、保存・別process再ロード |
| なし栞上流behavior | 元`behavior.js`と元fixtureで**16場面・81項目PASS**。同期/非同期SAORIと待機中終了を含む |
| なし栞の別process probe | arm64/Rosettaで並行2VM、途中要求EOF、Unicode/CP932、NOTIFY、保存・再ロード、入力JSON不変を確認 |
| Native ABI fixture | 32bitを超えるID、2辞書独立、片方unload後の継続、ID=0の拒否をdirect/XPCで確認 |
| 通常FactoryのAYA5 | encoding未指定のまま`engine\\AYA5.DLL`から接続し、「表ソ・半角ｶﾅ・①髙」を往復。元`aya5.txt`不変 |

Xcodeは27.1、Debug、`Ourin` scheme、arm64、`MACOSX_DEPLOYMENT_TARGET=13.0`、`CODE_SIGNING_ALLOWED=NO`、直列実行。新SDKでは旧project既定の11.0を受け付けないため、検証コマンドだけ13.0を指定した。projectの公開版targetは変更していない。使用許諾への同意はユーザー本人が実施し、その後のtest buildとテストは成功した。

初期のdeployment target・lipo引数互換・C fixtureの重複symbolによる実行前失敗は、成功件数に含めない。fixtureは専用defineを付けた実dylib生成時にだけexportし、test bundle本体との重複を解消した。

## 実アプリの確認

固有Bundle IDの検証コピーと一時プロファイルで実施。General画面のデータフォルダを確認した後、GUIから3つの`.plugin`を展開せずに導入し、正式な表示名と導入完了を確認した。

YAYA・AYA5互換・なし栞の各検証用ghostを起動し、実キャラクターのダブルクリックを操作した。3種とも期待したOnBoot応答とクリック応答が桜スクリプト再生tokenへ到達。YAYA/AYAは実`GETSETTING(0)`からTc607-2を取得した。キャラクターの描画は取得したが、バルーン文字画像は独立に取得していない。

検証用入力ファイルのSHA-256はすべて一致。3回ともアプリをUIから正常終了した。アプリ再起動後のCUAハンドルが古いPIDを参照する際はツールの接続を初期化し、正しい環境で起動済みのプロセスへ接続した。

## 証跡と残る範囲

- 統合試験: `/tmp/ourin-nashi-aya-yaya-20261030/tests-integrated.log`
- GUIとfixture照合: 同フォルダの`gui-summary.json`、`app-review.log`、`app-aya.log`、`app-nashi.log`
- YAYA: `/tmp/ourin-yaya-official-verification-20261030/upstream-summary.json`とCPU別probeログ
- なし栞: `/tmp/ourin-nashi-probe.json`、`/tmp/ourin-nashi-probe-rosetta.json`、`/tmp/ourin-nashi-upstream-behavior.log`

AYA1〜4、原本AYA5との完全な挙動一致、Windows専用API・任意Windows SAORI、全配布ghost・GUI、Intel実機・最低OS実機、正式配布の署名/公証は未確認。なし栞の編集GUI（なしスタジオ）は含めない。導入と役割の説明は[SHIORIエンジンプラグイン](SHIORI_ENGINE_PLUGINS_ja-jp.md)を参照。
