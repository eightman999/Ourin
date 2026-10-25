# 残件の優先順位と委譲記録 / Priorities and delegation

確認日: 2026-10-25。作業先は `codex/ourin-pr-integration`。ローカル変更であり、GitHubのmerge/close、commit/push、正式リリースは未実施。

## 優先順 / Priority order

| 順位 | 対象 | 実行先 | 現状と完了条件 |
|---|---|---|---|
| P0-1 | #96 #97 #99、#98の準備 | Devin CLI / SWE-2 High | CI・最低OS・版数検査を実装。統合側でレビュー修正、metadata正常・変異17ケースPASS。GitHub CI実行、最低OS実機、正式署名・公証、branch protectionは残る。 |
| P0-2 | #100 #103 | OpenCode / HAI DeepSeek v4.1 Flash | 初回は25分timeout。取得済み証拠を絞ったHAI再実行で信頼モデル・ライセンス監査2文書を作成。権限・認証設定の変更は範囲外。監査指摘の解消と実配布物照合を完了条件にする。 |
| P1-1 | #101、華和梨・KAGARI | Cursor CLI / Composer 2.5 | 固定上流の実エンジン・ABI・buildを実装。統合側でUniversal 2同梱とXPCテストを追加。華和梨LOBOの実エンジン検証は成功。KAGARI最小辞書PASS、もすはsaori_universal.native不足を記録。 |
| P1-2 | #191等の実ゴースト互換性 | Devin CLI / SWE-2 High → 統合側引継ぎ | 調査中に確認必須toolが拒否され、実編集前に停止。終了コード0を成功扱いせず引継ぎ。統合側でFOPEN/FREAD・foreach・変数永続化・GETVARLISTを修正。実helper9件PASS、Taromati2定期イベント停止を解消。 |
| P1-3 | #109 #118 | OpenCode / z.ai GLM 5.3 Flash | z.aiの変更を回収（25分timeout）。統合側でFINE単一宛先配送・初期値のwire検証を補強し、scriptbox open/close修正を検証。最終全体1,541実行/失敗0で統合回帰PASS。実入力窓の手動確認とSSP比較は残る。 |
| P1-4 | #95 #104 | OpenCode / DeepSeek Free → 統合側引継ぎ | 認証期限切れ。rdshのFree endpointもFreeTierErrorで拒否、保存済みDSHキーを使う実OpenCodeでも期限切れ。課金モデルへの置換・認証変更は行わず、文書整備は統合側で完了（9ファイル、50リンク検査PASS）。 |
| P1-5 | #102 | 統合側 | クリーンMacでinstall→NAR→保存→再起動。チェックリスト整備済みでも実機E2E完了とはしない。 |
| P2 | #161、描画・音声・OSイベント | 後続キュー | 実シェル、実機・目視での残差確認。自動テスト件数だけで完了にしない。 |
| P3 | #121、自動クラウド同期、翻訳残件 | 後続キュー | 手動.ssg入出力と自動同期を区別。仕様とデータ保護方針を先に決める。 |
| 追跡 | #105 #141 | 統合側 | 子issueの証拠を集約。上記gateが残る間はrelease完了にしない。 |
| 保留 | #114 #122 #124 | 割当対象外 | 既存の対象外・保留判断を維持。 |

既に取り込んだClaude PR 33件の重複実装は割り当てず、[全issue表](TODO_ISSUE_STATUS.md)と[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を基準にした。

## サイト文言 / Site copy

- agy / Gemini 3.8 Flash High: 5ページの校閲結果を取得。英語装飾・過剰な比喩を整理し、公開版と開発版、紹介デモと実アプリを区別した。
- Sarashina: rdshの14プロファイルに接続先・キーなし。ブラウザもログイン前。ユーザーが現在操作できないため認証待ちとして保留。突合済みとは扱わない。
- デザイン: 白い紙色・墨色・淡い桜色、細い罫線と明朝見出し。紹介／使い方／資料／対応状況／ダウンロードの5ページ。

## Evidence / English summary

Provider labels above refer to actual CLI/model attempts, not substitute Codex agents. DeepSeek Free could not authenticate; the direct rdsh route was rejected by the provider's Free-tier restriction. Devin's YAYA run stopped at a confirmation-required tool despite exit code zero; implementation was reassigned explicitly. Gemini reviewed the site copy. Sarashina has not reviewed it because authentication is unavailable. Local integration, automated engine probes, GUI validation, remote CI and public release are separate acceptance layers.

Task-local execution logs: `/tmp/ourin-delegation-20261025/`. No credential values or third-party ghost archives are included in this repository.
