# 第三者ライセンス監査 2026-10-25（ドラフト）

- 監査日: 2026-10-25
- 状態: ドラフト。法的判断ではなく、完全性・セキュリティ保証でもない。
- 方法: 本実行では追加読取・コマンド実行なし。前回実行の観測と親セッション提示の追加証拠のみ。
- 作業ツリー: 統合 worktree。他ワーカーが稼働中のため、本監査は2文書の作成に限定。

## 1. 監査対象と判定
| コンポーネント | 版/固定 | ライセンス | 同梱形態 | 証拠 | 判定 |
|---|---|---|---|---|---|
| Ourin 独自コード | 0.0.1.21 (build 21、前回観測) | Apache-2.0 | アプリ本体 | README/LICENSE | 自己宣言を確認 |
| Ourin 独自ドキュメント | - | CC BY-SA 4.0 | docs | README | 自己宣言を確認。対象範囲は要確定 |
| KAWARI | `8098dfb8...` | BSD-2-Clause | Universal2 署名済み dylib | 親証拠、PINNED_UPSTREAM | 現行証拠あり |
| uka_regexp | KAWARI サブモジュール | Unlicense | KAWARI に同梱 | 親証拠、PINNED_UPSTREAM | 現行証拠あり |
| KAGARI | `ba87ccbd...` | MIT | Universal2 署名済み dylib | 親証拠、PINNED_UPSTREAM | 現行証拠あり |
| Lua | 5.4.4 | MIT | 署名済み dylib | 親証拠、PINNED_UPSTREAM | 版と通知の全文照合は未実施 |
| sol2 | 3.2.2 | MIT | KAGARI に同梱 | 親証拠、PINNED_UPSTREAM | 版と通知の全文照合は未実施 |
| python-holidays | 0.107 | MIT | 生成済み祝日データ | Licenses/Holidays_python-holidays.txt | MIT 全文を前回確認 |
| 内閣府 祝日データ | - | PDL 1.0（出典明記） | 加工済み祝日データ | Licenses/Holidays_JP.txt | 条件・加工内容を前回確認 |
| 既定ゴースト さくら/りんね/ベル | - | Ourin と同一（自己宣言） | DefaultGhost | README、旧 AppLicense/LICENSE | 現行通知は要再確認 |
| LOBO / mosu NAR | - | 非再配布 | `/tmp` テストコピーのみ | 親証拠 | 配布対象外 |

## 2. 現行証拠として確認できたこと
- KAWARI+uka_regexp、KAGARI+Lua+sol2 は Universal2 の署名済み dylib として `Contents/Frameworks` に同梱。
- ABI plist は `Resources/EngineMetadata`、完全なライセンス通知は `Resources/EngineLicenses` に配置。
- エンジンテストは XPC を含む 42 実行が成功（親セッション報告、本実行での再実行なし）。
- 実ゴーストアーカイブの再配布なし。LOBO/mosu は `/tmp` のテスト用のみ。
- 上記は「配置と実行報告」の証拠であり、ライセンス全文の内容一致や法的解釈の確認ではない。

## 3. 前回実行の観測（現在と一致する保証なし）
- `engines/PINNED_UPSTREAM.json` に KAWARI/KAGARI のリポジトリ、revision、ライセンスファイル、依存版、成果物名を確認。
- `engines/package.sh` は lipo で arm64/x86_64 を検証し、dylib 配置、条件付き codesign、`LICENSE*` と `PINNED_UPSTREAM.json` のコピーを実施。
- HEAD の `Ourin/Resources/Licenses/AppLicense.txt` と `LICENSE` は既定ゴーストを Sakura のみと記載。README は Sakura/Rinne/Bell の3体と記載。
- `docs/DEPENDENCIES_en-us.md` は `SECURITY.md` を参照するが、`SECURITY.md` は見つからなかった。
- リリーススクリプト/CI の grep ではライセンス同梱チェックを確認できなかった。ただし grep の否定結果は不在の証明ではない。
- 祝日ファイルは `Ourin/Resources/Holidays/holidays-XX.txt` と `Ourin/en.lproj/holidays-XX.txt`。日本分は内閣府表の加工と python-holidays 補完。
- これらは前回時点のスナップショット。親セッションの追加変更後の HEAD では未確認。

## 4. 失効・誤用防止
- 旧 DerivedData の成果物は現行リリース証拠ではない。監査対象から除外。
- 前回 HEAD の AppLicense/LICENSE の記載は、現行の親変更を反映していない可能性がある。
- テスト用 `/tmp` の NAR を配布物の証拠として扱わない。
- 本監査の「確認」は提示された証拠の存在確認を指し、法的有効性の確認ではない。

## 5. リスク
1. 通知の完全性: BSD-2-Clause の著作権表示・免責、Unlicense、Lua/sol2 の MIT 全文が、同梱物と版で一致するか未照合。
2. 版の一致: PINNED_UPSTREAM の Lua 5.4.4 / sol2 3.2.2 と、実際の dylib のビルド元が一致するか未確認。
3. 文書ドリフト: 既定ゴーストの名称・数・素材ライセンスがファイル間で不一致の可能性。
4. 脆弱性報告: `SECURITY.md` 不在候補。参照だけが残ると運用上の抜けになる。
5. リリース自動検証: `package.sh` は通知をコピーするが、最終 `.app` に通知が入ったことの自動検証は未確認。
6. AI 生成素材: 既定ゴーストの立ち絵が AI 生成である旨は自己宣言。権利・生成条件の評価は未完了。
7. ゴーストコード: `EXECUTE`/`EXECUTE_WAIT` や SAORI、外部 SSTP、NAR 展開の信頼境界は別途レビューが必要。
8. 法務境界: Apache-2.0 と CC BY-SA 4.0 の適用範囲、第三者ライセンスの優先関係は、ドラフト段階。

## 6. 未解決ゲート
- 法務レビュー: 全文・版・帰属表示・変更通知の照合。本ドラフトは清算ではない。
- リリース証拠: 署名済み `.app` の Frameworks / EngineMetadata / EngineLicenses を実物確認。
- セキュリティ: ゴーストコード実行、外部 SSTP、NAR 展開のレビュー。認証・権限・セキュリティ設定は変更しない。
- 文書: `SECURITY.md`、AppLicense、LICENSE、README の整合。
- 証跡: 42 テスト実行のログと対象範囲を保存。

## 7. 次のアクション
1. 現行 HEAD の通知文と README のゴースト記載を照合する。
2. リリース `.app` から dylib とライセンスを抽出し、SHA-256 と版を記録する。
3. `SECURITY.md` を追加するか、依存文書の参照を修正する。
4. `package.sh` 後の `.app` に通知が存在することを検証するチェックを追加するか判断する。
5. 法務とセキュリティのレビュー担当へ、本ドラフトと証拠一覧を引き渡す。

## English summary
Bounded draft audit as of 2026-10-25; not legal or security clearance. Parent-supplied current evidence covers signed Universal2 KAWARI/uka_regexp and KAGARI/Lua/sol2 dylibs, ABI plists, full notices, and 42 passing engine tests including XPC; no real ghost archives are redistributed. Prior-run observations (license-file drift, missing SECURITY.md, release-pipeline checks) are snapshot evidence and may be stale. Remaining gates are license-text/version verification, execution-boundary review, AI-art provenance, and signed-release artifact inspection. No security settings were changed.


## 統合側の現物照合（2026-10-25）

ローカルDebug appの5件のライセンス通知を固定版build出力とバイト単位で照合し一致。3本のdylibはarm64/x86_64を持ち、dylib各々とapp全体の `codesign --verify --deep --strict` が成功。証跡 `/tmp/ourin-engine-bundle-audit-20261025.json`。これはDeveloper ID公証済みの正式配布物を検証した結果ではない。LICENSE/AppLicenseがSakuraのみ、READMEが3体という記載差も現物で再確認した。

今回の表は全依存の最終監査ではない。既存のYAYA_Core/SATORI/Ghidra通知、nlohmann_json等の依存、既存素材を含めた最終archiveの照合は #103 に残す。ライセンス条件や権限を変更していない。
