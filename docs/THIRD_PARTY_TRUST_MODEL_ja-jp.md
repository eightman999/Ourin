# 第三者コンポーネント信頼モデル（監査ドラフト）

- 日付: 2026-10-25
- 位置づけ: 境界整理のドラフト。法的判断・セキュリティ認証ではない。
- 方法: 本実行では追加のファイル読取・コマンド実行を行っていない。前回実行の観測と、親セッションが提示した追加証拠のみを使用。
- 対象: 配布アプリに同梱される第三者コード・データ・素材、およびゴースト由来コードの実行境界。

## 1. ライセンス境界
- Ourin 独自ソースは Apache License 2.0、独自ドキュメントは CC BY-SA 4.0。
- 第三者コンポーネントは各アップストリームのライセンスを保持し、Ourin の Apache-2.0 は及ばない。
- 既定ゴースト（さくら・りんね・ベル）は Ourin 本体と同じライセンスと自己宣言。立ち絵は画像生成AI製と自己宣言。
- 画像生成AIのモデル・学習データ・出力物の権利評価は、提示証拠だけでは完了しない。

## 2. 同梱ネイティブエンジン
- 現行の親セッション証拠: KAWARI（BSD-2-Clause）と uka_regexp（Unlicense）を Universal2 の署名済み dylib として `Contents/Frameworks` に同梱。
- 同じく KAGARI（MIT）、Lua（MIT）、sol2（MIT）を署名済み dylib として同梱。
- ABI 情報は `Resources/EngineMetadata` の plist、完全なライセンス通知は `Resources/EngineLicenses` に配置。
- 固定情報（前回観測の `engines/PINNED_UPSTREAM.json`）: KAWARI revision `8098dfb8...`、uka_regexp はサブモジュール、KAGARI revision `ba87ccbd...`、Lua 5.4.4、sol2 3.2.2。
- `engines/package.sh` は arm64/x86_64 を lipo 検証し、dylib をコピー、条件付きで codesign、`LICENSE*` と `PINNED_UPSTREAM.json` を配置する。
- エンジンテストは XPC を含む 42 実行が成功したと親セッションから報告。本実行では再実行していない。

## 3. ゴースト・プラグイン実行の信頼境界
- ゴースト由来の SHIORI/SAORI/プラグインは、ベースウェアの権限で動作する信頼済みコードとして扱う必要がある。
- yaya_core の実装文書は、`FOPEN` 等のファイルI/Oを相対パス限定・`..` 拒否と記載し、`SAVEVAR`/`RESTOREVAR` をゴーストルート配下に固定すると記載。
- 同文書は `EXECUTE`/`EXECUTE_WAIT` を実装済みと記載。ゴーストスクリプトからの任意コマンド実行能力を意味し得るため、主要リスク。
- 同文書は `FENUM` が macOS コンテナ sandbox 配下の絶対パスも受け付けると記載。サンドボックス依存の境界であり、無制限のファイルアクセスを許す趣旨ではない。
- これらは文書の記載であり、現行バイナリの動作を本実行で確認したものではない。

## 4. 外部入力とゴーストアーカイブ
- 外部 SSTP サーバは起動時に `ExternalServerSecuritySettings.load()` の設定を `updateConfig` へ適用する（前回観測）。
- 外部由来スクリプトには `isExternal` フラグが渡り、一部操作を制限する設計。`allow-external` の解釈も存在する（前回観測）。
- 具体的な許可・拒否項目、認証、ネットワーク露出の妥当性は本監査の範囲外。設定変更は行わない。
- 実ゴーストアーカイブは再配布していない。LOBO と mosu の NAR は `/tmp` のテスト用コピーのみ。
- NAR の展開・インストール時のパス検証は、提示証拠では未確認。

## 5. 祝日データ
- `python-holidays` 0.107（MIT、Vacanza Team ほか）を `scripts/gen_holidays.py` で 2020〜2050 年分生成。
- 日本分は内閣府の表（公共データ利用規約 1.0、出典明記条件）を加工。文字コード・改行・先頭説明・休日区分を変更し、日付と名称は保持。
- 2028 年以降は python-holidays の日本語名で補完。
- 同梱の `Holidays_JP.txt` と `Holidays_python-holidays.txt` に出典・条件・MIT 全文を確認（前回観測）。
- ユーザー配置の `~/Documents/Ourin/calendar/holidays-JP.txt` が同梱表より優先される。

## 6. 証拠の区分
- 現行証拠: 親セッションが提示した Universal2 同梱、EngineMetadata、EngineLicenses、42 テスト実行、実アーカイブ非再配布。
- 前回実行のスナップショット: HEAD の `AppLicense.txt`、`LICENSE`、`README.md`、`PINNED_UPSTREAM.json`、`package.sh`、テスト/docs の grep。現在の HEAD と一致する保証はない。
- 失効した証拠: 旧 DerivedData の成果物。リリース証拠として扱わない。
- ドリフト候補: 前回 HEAD の `AppLicense.txt`/`LICENSE` は既定ゴーストを Sakura のみと記載。README は Sakura/Rinne/Bell の3体と記載。現在の通知文との一致は未確認。

## 7. 確認できたリスク（提示証拠の範囲）
1. ゴーストコードの任意コマンド実行・ファイルアクセス境界が文書依存で、実バイナリ検証は未実施。
2. 外部 SSTP の公開範囲・認証・危険操作の拒否リストが未検証。
3. 既定ゴーストの AI 生成画像に関する権利・生成条件の説明が自己宣言に留まる。
4. 同梱通知の完全性（BSD-2 の表示保持、Unlicense、Lua/sol2 の版一致）は配置の存在確認までで、全文照合は未実施。
5. 旧 AppLicense/LICENSE と README の記載ドリフト。現行成果物では要再確認。
6. 前回スナップショットで `docs/DEPENDENCIES_en-us.md` が `SECURITY.md` を参照する一方、`SECURITY.md` が見つからなかった。脆弱性報告導線の欠落候補。
7. リリーススクリプト/CI におけるライセンス同梱の自動検証は、前回 grep では確認できなかった。`package.sh` のコピー処理とは別に、最終 `.app` の監査が必要。

## 8. 未解決ゲート
- 法務: 第三者ライセンス全文と版の照合、AI 生成素材の権利確認、CC BY-SA 対象文書の範囲確定。
- セキュリティ: `EXECUTE`/`EXECUTE_WAIT`、SAORI、外部 SSTP、NAR 展開の実装レビュー。設定変更はしない。
- リリース: 署名済み `.app` の `Contents/Frameworks`、`Resources/EngineMetadata`、`Resources/EngineLicenses` を実物で確認。
- 文書: `SECURITY.md` の有無、AppLicense/LICENSE/README のゴースト記載統一。
- テスト: 42 実行のログ・対象範囲を保存し、監査証跡化。

## 9. 次のアクション（境界付き）
1. 現行 HEAD で通知文と README のゴースト記載を照合する。
2. 署名済みリリース `.app` から同梱 dylib とライセンス全文を抽出してハッシュ記録する。
3. `SECURITY.md` を整備するか、参照を削除する。
4. ゴースト信頼モデル（信頼済み/未信頼、EXECUTE の扱い）を1ページで明文化する。
5. 法務レビューへ本ドラフトと証拠一覧を渡す。本ドラフト自体を法的判断として扱わない。

## English summary
This is a bounded draft audit, not legal or security clearance. Current parent-supplied evidence confirms signed Universal2 KAWARI/uka_regexp and KAGARI/Lua/sol2 dylibs, ABI plists, full notices, and 42 passing engine tests including XPC; no real ghost archives are redistributed. Prior-run greps are snapshot evidence and may be stale. Open gates are license-text/version verification, ghost-code execution boundaries (EXECUTE, SAORI, external SSTP, NAR extraction), AI-art provenance, SECURITY.md, and release-artifact verification. No security settings were changed.


## 統合側の現物照合（2026-10-25）

ローカルDebug appの5件のライセンス通知を固定版build出力とバイト単位で照合し一致。3本のdylibはarm64/x86_64を持ち、dylib各々とapp全体の `codesign --verify --deep --strict` が成功。証跡 `/tmp/ourin-engine-bundle-audit-20261025.json`。これはDeveloper ID公証済みの正式配布物を検証した結果ではない。LICENSE/AppLicenseがSakuraのみ、READMEが3体という記載差も現物で再確認した。

今回の表は全依存の最終監査ではない。既存のYAYA_Core/SATORI/Ghidra通知、nlohmann_json等の依存、既存素材を含めた最終archiveの照合は #103 に残す。ライセンス条件や権限を変更していない。
