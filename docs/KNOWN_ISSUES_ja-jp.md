# 既知の問題と検証範囲

更新日: 2026-10-25。対象は開発中の統合版で、公開済みリリースへの反映を保証する一覧ではありません。[English](KNOWN_ISSUES_en-us.md)

不具合・利用上の制限はこの文書、ランタイムごとの実装・試験範囲は[互換性マトリクス](SHIORI_RUNTIME_COMPATIBILITY_MATRIX_ja-jp.md)、Issueごとの進捗は[TODO照合表](TODO_ISSUE_STATUS.md)を参照します。「実装済み」「ローカル統合済み」「実ゴーストで確認済み」「公開版で解消済み」を分けて記録します。最新の実測は[実ゴースト検証記録](REAL_GHOST_VERIFICATION_2026-10-25.md)と[華和梨・KAGARI](KAWARI_KAGARI_ENGINES_ja-jp.md)を参照してください。

## 制限・未確認項目

| 項目 | 現在の範囲と影響 | 追跡・対応 |
|---|---|---|
| 追加栞7種の同時起動・互換範囲 | 灯・ese-shiori・偽栞・忍・翡翠・結奈・美坂の独立互換実装を同梱。同一ライブラリの同じprocessへの2回目のloadは失敗します。XPCは接続ごとの別PIDを保証しないため、同じ栞の複数ゴースト同時起動は対応済みではありません。全配布ゴースト・Windows保存形式との互換も未確認です。 | [追加栞ガイド](ADDITIONAL_SHIORI_ja-jp.md)。1つずつ終了・起動して利用。 |
| Windows専用モジュール | Windows DLLをmacOSでそのまま実行する機能ではありません。栞・SAORIの対応はmacOS用モジュール、内蔵の互換実装、各ランタイムの対応範囲に依存します。拡張子だけの変更では動作しません。 | [#101](https://github.com/eightman999/Ourin/issues/101)、[Native ABI](NATIVE_SHIORI_ABI_ja-jp.md)。使用ゴーストの公開名・版・SHIORIを添えて報告。 |
| 華和梨・KAGARIの網羅 | エンジンのビルドや最小辞書の成功は、全ゴースト・SAORI・Lua拡張の互換性を保証しません。KAGARIの実ゴーストは必要なネイティブLua拡張ごとの確認も必要です。 | [#101](https://github.com/eightman999/Ourin/issues/101)。エンジン資料と実測記録の対象・検証層を確認。 |
| YAYAの保存形式・検証範囲 | 10月25日修正版ではTaromati2の定期イベント停止を解消し、Emily4 / Taromati2のOurin形式での保存・別process再loadを確認しました。Taromati2のOnDestroy400は辞書が未定義イベントへ返す期待応答です。上流テキスト/暗号化保存のimport/export、GUI・実SAORI連携は未確認または未対応です。 | [PR #191](https://github.com/eightman999/Ourin/pull/191)関連。[実ゴースト検証記録](REAL_GHOST_VERIFICATION_2026-10-25.md)を参照。上流バイナリとの同一入力比較は未実施。既存の未知形式のセーブは上書きしません。 |
| SHIOLINK・SHIORI 2.x・Nativeの実ゴースト網羅 | 実fixtureや別プロセス試験の成功と、配布ゴーストの全操作確認は別です。未試験のゴーストや外部実行ファイルとの組合せが残ります。 | [#101](https://github.com/eightman999/Ourin/issues/101)、[SHIOLINK](SHIOLINK_ja-jp.md)。未検証を非対応・対応済みのどちらにも読み替えません。 |
| 強制終了時の保存 | timeoutやクラッシュからの復旧で、強制終了直前の未保存VM状態・SAORIの副作用までは復元できません。 | 再ロードは最後に永続化された状態が基準です。通常終了で再現する保存不具合は[報告ガイド](BUG_REPORT_GUIDE_ja-jp.md)へ。 |
| 診断Exportの範囲 | 設定画面のExportは`jp.ourin.devtools`の直近24時間のログです。全SHIORI/helperログ、OS/CPU/版数の一括収集や自動匿名化ではありません。Debugメニューの「診断情報をエクスポート」は現状、日時文だけです。 | [#104](https://github.com/eightman999/Ourin/issues/104)。[ログ取得手順](BUG_REPORT_GUIDE_ja-jp.md)で選択ログまたはファイルログを用意。空ログだけでは不具合なしと判断しません。 |
| リリース環境の検証 | 開発対象はmacOS 13.0以上に統一しましたが、最低OS・クリーンMac・Intel実機の全リリース試験は完了扱いにしていません。過去の配布版の要件を変更する記載ではありません。 | [#97](https://github.com/eightman999/Ourin/issues/97)、[#102](https://github.com/eightman999/Ourin/issues/102)、[リリースゲート](RELEASE_GATES_2026-10-25.md)。 |
| 保留・対象外の連携 | FineFMOのWindows共有メモリ契約、IP Messenger/MsgSender連携は保留です。通常のPOSIX FMOとは別です。`mcp.exe`は伺か互換の対象外として整理しています。 | [#124](https://github.com/eightman999/Ourin/issues/124)、[#122](https://github.com/eightman999/Ourin/issues/122)、[#114](https://github.com/eightman999/Ourin/issues/114)。 |

## 修正済み項目の扱い

古いIssueタイトルが「未実装」のままでも、現在の実装状況と一致するとは限りません。取り込んだPRと検証は[PR引継ぎ記録](PR_TAKEOVER_2026-10-25.md)で確認できます。ローカル統合だけでGitHub Issueの完了や配布版への反映を宣言しません。

修正時は該当行にIssue/PR、検証日、検証したcommitまたは版、再現手順の結果を記録します。公開後に解消版を追加して「修正済み」へ移し、まだ利用者が遭遇する旧版の情報を消さないようにします。リリースノートにはこの文書へのリンクと、そのリリース固有の制限を載せます。

## 報告する

一覧にない症状や、修正版でも再現する症状は[バグ報告ガイド](BUG_REPORT_GUIDE_ja-jp.md)から報告してください。ログやゴーストデータがなくても、環境・再現手順・期待値・実際の結果だけで報告を始められます。

翻訳: [英語版](KNOWN_ISSUES_en-us.md)と本文・表・リンク対象を照合（2026-10-25）。将来の修正時は両言語を同期します。
