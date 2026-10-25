# Ourin — エージェント指示

Ourin（桜鈴）はmacOS向け伺かベースウェア。SHIORI／SSTP／Pluginおよび既存ゴーストとの互換性を維持する。

## 保護する制約

- `AppDelegate` は `Ourin/OurinApp.swift` 内にあり、独立した `AppDelegate.swift` はない。主要systemの初期化は `applicationDidFinishLaunching` に集約される。
- 外部TCP／HTTP／XPCのSSTPは `SSTPParser` → `SSTP/SSTPDispatcher` の単一stackへ接続する。旧 `SstpRouter` を別経路として復活させない。
- FMOはPOSIX shared memoryとnamed semaphoreによるprocess間通信／単一instance制御。共有メモリやlockの契約をSwift側だけの都合で変更しない。
- `yaya_core/` はC++製YAYA parser／VMで、Swiftとはhelper processのJSON line IPCで通信する。互換性問題は仕様・再現入力・実装を照合し、ゴーストデータを改変して症状を隠さない。
- ユーザーのghost/NARデータは実データとして扱う。保存先は `~/Library/Containers/furin-lab.Ourin/Data/Library/Application Support/Ourin/ghost/`。破壊的操作・外部公開・課金・認証／権限変更は対象と範囲の明示承認が必要。commit／pushは依頼された場合だけ行う。

## 変更範囲に応じた検証

- Xcode入口: `xcodebuild -project Ourin.xcodeproj -scheme Ourin build`、`xcodebuild -project Ourin.xcodeproj -scheme Ourin test`。必要なら `-only-testing:OurinTests/TestClassName/testMethodName` で対象を選ぶ。
- C++ parser／VM変更時: `cd yaya_core && ./build.sh`。`yaya_core/CMakeLists.txt` の依存（nlohmann_json／iconv）も確認する。
- GUI・IPC・ghost動作に関わる変更は実app／processで対象操作を再現する。生成されたappの実在する出力先を確認して起動する。
- 依頼範囲のローカル編集・build・affected test・再現fixture作成と、変更起因の失敗修正は続行する。完了時に結果・実行検証・残る未確認を簡潔に報告する。

## 必要なときだけ読む

| 作業領域 | 参照先 |
|---|---|
| SHIORI protocol | [SHIORI 3.0仕様](https://ssp.shillest.net/ukadoc/manual/spec_shiori3.html) と `docs/` の該当仕様 |
| Sakura Script・property | [桜スクリプト](https://ssp.shillest.net/ukadoc/manual/list_sakura_script.html)、[property仕様](https://ssp.shillest.net/ukadoc/manual/list_propertysystem.html) |
| YAYA構文 | [YAYA言語](http://usada.sakura.vg/contents/shiori.html)、`yaya_core/src/` の該当実装 |
| FMO／Plugin／NAR／Eventの詳細・旧ログprefix | [旧技術ガイド](.agent-context/legacy/AGENTS-before-2026-09-05.md) の該当節と現在の実装 |

旧 [AGENTS](.agent-context/legacy/AGENTS-before-2026-09-05.md) と [CLAUDE](.agent-context/legacy/CLAUDE-before-2026-09-05.md) は履歴として原文保全。モデル役割・固定effort・全資料先読み・多重レビューは現行指示ではない。通常作業で全文を読む必要はない。
