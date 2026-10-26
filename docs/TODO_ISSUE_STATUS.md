# TODO・GitHub issue照合 / TODO and GitHub Issue Reconciliation

**確認日 / Checked:** 2026-10-25 (JST)<br>
**対象 / Scope:** 実配布物検証PR #217までマージ済みの `master 7e2adb02c962643e61e800efff7c046e0115c909`。追加プラグイン/KAGARI修正は開発ブランチの検証結果として以下に分離。

Claude PR 33件、統合PR #214、CI修正PR #215はmasterへマージ済み。元のPR headもmasterの祖先として確認した。GitHub issueの状態と実装・検証の状態は区別し、下表を2026-10-25の全issue一覧と照合した。[PR引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。

All 33 original PRs and integration/CI PRs #214/#215 are merged into master. The table distinguishes GitHub issue state from implementation and validation. New engine additions are development work and are not part of the published v0.0.1.21 binary.

- 元ブランチで実装済み12件は[完了記録](AUDITS_COMPLETED.md)へ整理済み。
- 保留・対象外は #114 / #122 / #124。正式リリース判定・実ゴースト網羅は引き続き残件。
- 新規のCompatibility Doctor計画 #196–213 を追加。診断UI・署名付き追加モジュール配信の完成を意味しない。

優先順と実行モデル・認証待ちは[委譲記録](DELEGATION_2026-10-25.md)、実ゴーストの判定は[検証結果](REAL_GHOST_VERIFICATION_2026-10-25.md)を参照。

**最新ローカル検証:** 追加栞対応後のOurinTests 1,589実行 / 1,535集計テスト、失敗0（2026-10-25、arm64・直列）。関連6 suiteは59テスト/99実行PASS。実辞書の追加回帰15件（Emily4 11件＋標準ゴースト4件）もPASS。[栞拡張検証](SHIORI_EXPANSION_VERIFICATION_2026-10-25.md)を参照。master `88b8172` のCI全5ジョブも成功（[実行記録](https://github.com/eightman999/Ourin/actions/runs/40149056400)）。追加栞PR #216の最終head `a567943` も[remote CI全5項目成功](https://github.com/eightman999/Ourin/actions/runs/40164170664)、masterへマージ済み。GUIの網羅、クリーンMac・最低OS/Intel実機はこの結果と区別する。 / Latest development unit run: 1,589 executions / 1,535 aggregate tests, zero failures; PR #216 remote CI passed all five checks and is merged. Broader device/release gates remain separate.


## 追加の対応実装（開発ブランチ）

- 15件のネイティブ`.plugin`を生成。UGMのhash/JSON/配列引数/loopback HTTP対応を追加し、元辞書11件無改変で保存・再ロードまで確認。Bouyomiの限定TCP連携を追加し、標準port条件でのロード成功は13/15。元辞書のメニュー・音声設定保存再読込・実socket送信を確認（CeVIO/AIVOICEはローカルTTSを指定しない標準条件ではWindows起動依存で拒否）。[個別結果と配布元](compatibility-corpus/plugin-ports.md)を参照。元のWindows DLLは実行せず、辞書adapterまたはネイティブ連携実装を利用。
- CeVIO-Talker・SSP-AIVOICEの任意Irodori接続を追加。元辞書無改変の2/2でロード・メニュー・設定再読込・実MLX音声生成・再生・発話置換・unload停止を確認。実OurinのSSTP通常発話経路も両プラグインで再生完了。worker 13・音声サービス6・Xcode関連19集計テストが成功（失敗0）。製品固有の声・全GUI手操作・聴感同等性は未確認。[導入手順と範囲](compatibility-corpus/local-tts.md)・[検証メタデータ](compatibility-corpus/local-tts-results.json)。
- Aosoraの任意導入に対応。上流VMの未初期化を固定ソースのビルド時に修正し、実ゴースト2件で元辞書のまま起動・終了・再ロード成功。[検証と入手先](compatibility-corpus/aosora.md)。通常配布には非同梱、会話・ゲーム・GUI全体は未検証。
- 失敗していたKAGARIゴースト4件の起動・会話応答・終了・再ロードを確認。[再検証](compatibility-corpus/kagari-fixes.md)。ゲームAI/Windows SAORI/GUI全機能は残件。
- 複数の直置きbundleのID衝突と、load失敗後も要求を送るPluginHostの動作を修正。灯系は専用helperへ分離。関連18 suite・192テスト/226実行PASS、失敗0・SKIP 0。全体試行はAudioQueue出力タイムアウトで中断したため全体PASSとは区別する。
- Windows音声API、SNS/外部サービス、AXによる実画面タイトル取得など、未検証または未対応の依存は成功数に含めない。

## Issue全件の照合 / Issue reconciliation

| Issue | GitHub | 現ブランチの判定 / Branch status | 根拠・残件 / Evidence and remaining work |
|---|---|---|---|
| [#95](https://github.com/eightman999/Ourin/issues/95) [Process] OurinをIssue駆動開発へ移行する | open | ローカル整備済み / Locally prepared | CONTRIBUTING・Issue/PR templates追加。運用の定着は別 / templates and workflow prepared, adoption remains. |
| [#96](https://github.com/eightman999/Ourin/issues/96) [P0][Release] master/PR に必須の macOS CI リリースゲートを導入する | open | CI成功・保護設定未確認 / CI passed | Release/helper/metadata gateを追加。masterのCI全5ジョブ成功。branch protection未確認。RELEASE_GATES_2026-10-25.md。 |
| [#97](https://github.com/eightman999/Ourin/issues/97) [P0][Bug] macOS minimum deployment target の不整合を解消する | open | ローカル整合済み / Aligned locally | app/XPC/testsをREADMEのmacOS13へ統一。metadata検査PASS。最低OS実機は未確認。公開v0.0.1.21の要件とは別。 |
| [#98](https://github.com/eightman999/Ourin/issues/98) [P0][Release] Developer ID署名・notarization・配布パッケージを確立する | open | 一部 / Partial | [v0.0.1.21](https://github.com/eightman999/Ourin/releases/tag/v0.0.1.21) に署名・公証済み配布の記載。`scripts/release.sh` はmasterで追跡済み。1.0.0向け再現可能な署名/公証・クリーンMac検証が残る / release reports signed/notarized delivery; reproducible 1.0.0 flow and clean-Mac verification remain. |
| [#99](https://github.com/eightman999/Ourin/issues/99) [P0][Release] v1.0.0向けバージョン・リリースメタデータを整理する | open | 開発版整合済み / Development aligned | 0.0.1.21/build21を同期し、release時は3整数bundle版数を要求。正常/変異17ケースPASS。正式1.0.0への変更は未実施。 |
| [#100](https://github.com/eightman999/Ourin/issues/100) [P0][Security] 第三者ゴースト/SHIORI/SAORI実行の信頼モデルと権限制御を定義する | open | 監査文書作成・残gateあり / Audit draft | HAIがTHIRD_PARTY_TRUST_MODEL_ja-jp.mdを作成。native/XPCは権限制限そのものではない。危険操作・実配布物の境界検証は残る。 |
| [#101](https://github.com/eightman999/Ourin/issues/101) [P1][Compatibility] 実ゴースト互換性マトリクスを拡充する | open | 検証拡充 / Expanded | KAWARI/KAGARI Universal2同梱・実エンジンXPC成功。LOBO/Emily4/Taromati2を複製上で検証。もすnative依存・GUI/実SAORI・広い網羅は残る。 |
| [#102](https://github.com/eightman999/Ourin/issues/102) [P1][QA] クリーンMacでインストール〜NAR〜再起動までのE2Eリリース試験を整備する | open | チェックリスト整備・実機待ち / Device pending | RELEASE_GATESに手順追加。クリーンMac install→NAR→保存→再起動と最低OS実機は未確認。 |
| [#103](https://github.com/eightman999/Ourin/issues/103) [P0][Legal] v1.0.0配布物の第三者ライセンス・再配布条件を最終監査する | open | 部分監査 / Partial audit | HAI監査文書と新エンジン5通知の現物一致確認。正式archive全依存監査、既定ghost通知の名称差、素材権利記録は残る。 |
| [#104](https://github.com/eightman999/Ourin/issues/104) [P1][Release] Known Issues・バグ報告導線・診断情報を整備する | open | 文書整備済み・一部残件 / Docs prepared | Known Issues/報告手順の日英文書・bug template追加。toolbarログExportとDebug診断stubの差、自動匿名化などは残る。 |
| [#105](https://github.com/eightman999/Ourin/issues/105) [Meta][Release] Ourin v1.0.0-beta.1 / v1.0.0 リリーストラッカー | open | 追跡 / Tracker | v1.0.0-beta.1→v1.0.0、日程未定。PR #125取込済み、P0/P1 gate残存 / PR #125 merged; release gates remain. |
| [#106](https://github.com/eightman999/Ourin/issues/106) [compat/SSTP] Sender と User-Agent の両方無しリクエストの 400 拒否が未実装 | open | 実装済み / Implemented | `Ourin/SSTP/SSTPDispatcher.swift` (`refuseIfMissingSenderAndUserAgent`); `OurinTests/SSTPCompatRegressionTests.swift` |
| [#107](https://github.com/eightman999/Ourin/issues/107) [compat/SSTP] SHIORI 非標準ステータスを 204 に丸める変換が未実装 | open | 実装済み / Implemented | `Ourin/SSTP/SSTPDispatcher.swift`; `OurinTests/SSTPCompatRegressionTests.swift` |
| [#108](https://github.com/eightman999/Ourin/issues/108) [compat/SSTP] X-Force-Activate-Me ヘッダによるウィンドウアクティブ化が未実装 | open | 実装済み / Implemented | `Ourin/SSTP/SSTPDispatcher.swift`; `OurinTests/SSTPCompatRegressionTests.swift` (実窓確認は別 / real-window check separate) |
| [#109](https://github.com/eightman999/Ourin/issues/109) [compat/SSTP] FINE メソッド（MessageSend/SetScript/SetScriptPartial）が未実装 | open | master修正・差分残 / Fixed on master | z.ai＋統合修正でFINE行subcommand/Reference3本文、単一宛先配送・wire回帰を追加。SSP優先ghost fallbackと曖昧Reference仕様は未確定。 |
| [#110](https://github.com/eightman999/Ourin/issues/110) [compat/SSTP] X-SSTP-Return- への PassThru フォールバックが未実装 | open | 実装済み / Implemented | `Ourin/SSTP/SSTPDispatcher.swift`; `OurinTests/SSTPCompatRegressionTests.swift` |
| [#112](https://github.com/eightman999/Ourin/issues/112) [compat/SHIORI] SecurityOrigin 無し時の 'null' 送出が未実装 | open | 実装済み / Implemented | `Ourin/SSTP/SSTPDispatcher.swift`; `OurinTests/ShioriRuntimeTests.swift` |
| [#114](https://github.com/eightman999/Ourin/issues/114) [compat] mcp.exe は MCP サーバであり ukagaka 互換対象外（記録） | open | 対象外 / Out of scope | mcp.exe はMCP serverとして記録。伺か互換実装のTODOから除外 / excluded from compatibility implementation. |
| [#115](https://github.com/eightman999/Ourin/issues/115) [compat/Property] selfname が sakuraname の別名として未解決 | open | 実装済み / Implemented | `Ourin/Property/GhostPropertyProvider.swift`; `OurinTests/PropertySystemTests.swift` |
| [#116](https://github.com/eightman999/Ourin/issues/116) [compat/SERIKO] interval 略称と never 複合の挙動が SSP と異なる | open | 実装済み / Implemented | `Ourin/Animation/SerikoParser.swift`, `SerikoExecutor.swift`; `OurinTests/SerikoParserTests.swift`, `SerikoExecutorTests.swift` |
| [#117](https://github.com/eightman999/Ourin/issues/117) [compat/SERIKO] method ccyr / noop が未実装 | open | 実装済み / Implemented | `Ourin/Animation/SerikoParser.swift`; `OurinTests/SerikoParserTests.swift` |
| [#118](https://github.com/eightman999/Ourin/issues/118) [compat/Input] scriptbox 入力種別が未実装 | open | master修正済み / Fixed on master | z.aiがscriptbox/textareaboxのopen/close誤配線を修正。入力窓生成とclose回帰テスト。Macロック中で手動画面操作未確認。 |
| [#119](https://github.com/eightman999/Ourin/issues/119) [compat/Calendar] PlayTodaysEvent（#todays event header）が未実装 | open | 実装済み / Implemented | `Ourin/Calendar/CalendarSchedule.swift`, `CalendarWindow.swift`; `OurinTests/CalendarScheduleTests.swift` |
| [#120](https://github.com/eightman999/Ourin/issues/120) [compat/Cookie] SSTP Cookie のディスク永続化が未実装（メモリのみ） | open | 実装済み / Implemented | `Ourin/SSTP/SstpSessionStore.swift`; `OurinTests/SSTPDispatcherTests.swift` (Sender単位の最低要件 / minimum Sender-scoped requirement) |
| [#121](https://github.com/eightman999/Ourin/issues/121) [compat/SaveShare] OneDrive/Dropbox クラウドセーブ（.ssg）が未実装 | open | 一部 / Partial | `Ourin/SaveShare/SaveShareManager.swift` とテストで手動.ssg入出力済み。cloud検出/load-unload同期が残る / manual import/export done; automatic cloud sync pending. |
| [#122](https://github.com/eightman999/Ourin/issues/122) [compat] IP Messenger / MsgSender 連携が未実装 | open | 保留 / Deferred | `1c30313`でIP Messenger対象外記録。必要時にMsgSenderも含め方針再検討 / revisit interoperability if required. |
| [#123](https://github.com/eightman999/Ourin/issues/123) [compat/Sound] http(s)/ストリーミング URL 再生が未対応（ローカルのみ） | open | 実装済み / Implemented | `Ourin/Ghost/GhostManager+Display.swift`; `OurinTests/SoundPlayerTests.swift` (実再生は別 / actual playback separate) |
| [#124](https://github.com/eightman999/Ourin/issues/124) [compat/FMO] FineFMO 共有メモリが未実装 | open | 保留 / Deferred | Windows FineFMO共有メモリは未実装。通常POSIX FMOとは別契約 / FineFMO remains a platform gap, distinct from implemented POSIX FMO. |
| [#131](https://github.com/eightman999/Ourin/issues/131) [compat/Execute] WebSocket イベントが UKADOC と不一致（Reference の並び・Failure/Reconnect/_SSLInfo・--async） | closed | master反映済み / Merged into master | PR #142をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#132](https://github.com/eightman999/Ourin/issues/132) [compat/Events] OnIdle に時刻系の Reference（トーク可否・放置秒数）を付ける | closed | 実装済み / Implemented | `Ourin/SHIORIEvents/TimerEmitter.swift`, `EventReferenceSpec.swift`; `OurinTests/EventObserverLifecycleTests.swift`, `EventReferenceTableTests.swift`; `0a2a37d` |
| [#133](https://github.com/eightman999/Ourin/issues/133) [compat/Execute] \![execute,filewatch] と OnExecuteFileWatchChange/Failure が未実装 | closed | master反映済み / Merged into master | PR #143をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#134](https://github.com/eightman999/Ourin/issues/134) [compat/Events] OnDesktopWallpaperChange が未実装 | closed | master反映済み / Merged into master | PR #144をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#135](https://github.com/eightman999/Ourin/issues/135) [compat/Input] textareabox と OnTextAreaInput/OnTextAreaInputCancel が未実装 | closed | master反映済み / Merged into master | PR #145をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#136](https://github.com/eightman999/Ourin/issues/136) [compat/Calendar] schedule-add/delete/get と OnExecuteSchedule*、OnScheduleTodayNotify が未実装 | closed | master反映済み / Merged into master | PR #147をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#137](https://github.com/eightman999/Ourin/issues/137) [compat/Execute] ical-get/ical-post と OnExecuteICal* が未実装 | closed | master反映済み / Merged into master | PR #148をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#138](https://github.com/eightman999/Ourin/issues/138) [compat/Sound] OnSoundSpectrum が未実装 | closed | master反映済み / Merged into master | PR #150をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#139](https://github.com/eightman999/Ourin/issues/139) [compat/SAORI] 内蔵SAORIの非同期呼び出し OnInternalSaoriComplete/Failure が未実装 | closed | master反映済み / Merged into master | PR #155をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#140](https://github.com/eightman999/Ourin/issues/140) [compat/Calendar] OnNotifyHolidayInfo が未実装 | closed | master反映済み / Merged into master | PR #149をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#141](https://github.com/eightman999/Ourin/issues/141) [Meta][compat/Events] UKADOC の SHIORI イベントの不足・不一致への対応 | open | 追跡 / Tracker | #131〜140の実装・PR統合済み。祝日表運用と実機イベントの網羅は継続。 / Implementations merged; operational and device coverage remains. |
| [#151](https://github.com/eightman999/Ourin/issues/151) [compat/SAORI] SAORI over DirectSSTP と内蔵モジュール（internal_*）が未実装 | open | master反映済み / Merged into master | PR #155と後続PRのInternalSaori/DirectSSTP基盤・内蔵モジュールと回帰試験を統合。GitHub issueはopen。 |
| [#152](https://github.com/eightman999/Ourin/issues/152) [compat/SAORI] internal_crypto（ハッシュ・暗号・鍵導出・署名など）が未実装 | closed | master反映済み / Merged into master | PR #160をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#153](https://github.com/eightman999/Ourin/issues/153) [compat/SAORI] internal_jwt（JWT の作成と検証）が未実装 | open | master反映済み / Merged into master | PR #159をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#154](https://github.com/eightman999/Ourin/issues/154) [compat/SAORI] internal_file（MediaInfo）と互換モジュールの扱いが未実装 | closed | master反映済み / Merged into master | PR #162をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#161](https://github.com/eightman999/Ourin/issues/161) ゴーストのシェル／バルーン読み込み不具合と切り替えメニューの日本語化要望 | open | 検証待ち / Verification | 表示/メニュー改善はあるが報告ゴーストでの再現・解消未確認。#184/#192とも照合 / reproduce reported shell/balloon problems. |
| [#163](https://github.com/eightman999/Ourin/issues/163) [compat/i18n] 日本語以外の文字コード（Big5・GBK・EUC-KR・Windows-1252 など）を読めない | closed | master反映済み / Merged into master | PR #166をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#164](https://github.com/eightman999/Ourin/issues/164) [i18n] UI の多言語化（日本語の直書きを英語・日本語で切り替え、中国語・韓国語を追加） | closed | master反映済み / Merged into master | PR #168をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#165](https://github.com/eightman999/Ourin/issues/165) [compat/Calendar] 外国の祝日（holidays-XX.txt）と言語ごとの祝日名 | closed | master反映済み / Merged into master | PR #167をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#169](https://github.com/eightman999/Ourin/issues/169) NAR インストーラで LZMA 圧縮の NAR を展開できない | closed | master反映済み / Merged into master | PR #172をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#170](https://github.com/eightman999/Ourin/issues/170) 別名の DLL（aya.dll など）で同梱された YAYA を YAYA として起動する | closed | master反映済み / Merged into master | PR #173をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#171](https://github.com/eightman999/Ourin/issues/171) yaya_core で Big5・GBK・EUC-KR の辞書を読む | closed | master反映済み / Merged into master | PR #174をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#175](https://github.com/eightman999/Ourin/issues/175) yaya_core が Taromati2 の辞書の YAYA 構文を解析できない | closed | master反映済み / Merged into master | PR #178をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#176](https://github.com/eightman999/Ourin/issues/176) yaya_core が関数の呼び出しの深さに上限を持たず、再帰でスタックを使い切って落ちる | closed | master反映済み / Merged into master | PR #177をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#179](https://github.com/eightman999/Ourin/issues/179) yaya_core のファイル関数を YAYA に合わせ、ゴーストの profile フォルダを用意する | closed | master反映済み / Merged into master | PR #180取込み後、FOPEN/FREADのfilename契約・EOF・SAVEVAR既定保存先・GETVARLISTを修正。Emily4/Taromati2の保存・別process再load成功。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#181](https://github.com/eightman999/Ourin/issues/181) Xcode の増分ビルドで yaya_core・satori_core のソースの変更が反映されない | closed | master反映済み / Merged into master | PR #182をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#183](https://github.com/eightman999/Ourin/issues/183) 直下にフォルダが1つだけある NAR（Taromati2.nar など）をインストールできない | closed | master反映済み / Merged into master | PR #186をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#184](https://github.com/eightman999/Ourin/issues/184) ゴーストの descript.txt の balloon（標準バルーン）を使わない | closed | master反映済み / Merged into master | PR #187をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#185](https://github.com/eightman999/Ourin/issues/185) \![open,inputbox] などの入力ボックスがモーダルで、閉じるまでアプリ全体が止まる | closed | master反映済み / Merged into master | PR #188をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#189](https://github.com/eightman999/Ourin/issues/189) yaya_core が %(username) など SSP の環境変数と同じ名前の埋め込み要素を展開しない | closed | master反映済み / Merged into master | PR #190をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#192](https://github.com/eightman999/Ourin/issues/192) バルーンの descript.txt の font.color・font.height が、表示した最初の本文に使われない | closed | master反映済み / Merged into master | PR #193をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |
| [#194](https://github.com/eightman999/Ourin/issues/194) OnSurfaceRestore がサーフェス変更の 15 秒後に送られ、選択肢待ちのバルーンを消す | closed | master反映済み / Merged into master | PR #195をmasterへ反映済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。 / Merged into master; see validation and limitations in the takeover record. |

| [#196](https://github.com/eightman999/Ourin/issues/196) [Meta][Compatibility Doctor] Wine不要の一般ユーザー向け互換性診断・導入・修復UX | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#197](https://github.com/eightman999/Ourin/issues/197) [P0][Doctor/Model] 診断レポートとステータスの型・根拠・文言契約を定義 | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#198](https://github.com/eightman999/Ourin/issues/198) [P0][Doctor/Security] NAR/ZIPの非実行プレフライトと安全な展開検査 | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#199](https://github.com/eightman999/Ourin/issues/199) [P0][Doctor/Static] ゴースト・シェル・バルーンの静的診断と検出根拠 | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#200](https://github.com/eightman999/Ourin/issues/200) [P0][Doctor/Resolver] WineなしのSHIORI識別・別名判定とロード候補決定 | open | 計画 / Planned | 既存factoryと別名YAYA判定を利用可能。診断結果への統合は未実装。 / Existing runtime resolver available; Doctor integration pending. |
| [#201](https://github.com/eightman999/Ourin/issues/201) [P0][Doctor/UI] 説明しやすい診断ウィザード・結果画面と表示状態 | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#202](https://github.com/eightman999/Ourin/issues/202) [P0][Doctor/Install] 診断後の同意・変更差分プレビュー・バックアップ・復旧 | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#203](https://github.com/eightman999/Ourin/issues/203) [P0][Doctor/Core] NARの全導入入口を診断・確認フローへ統一する | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#204](https://github.com/eightman999/Ourin/issues/204) [P1][Doctor/Dependencies] SAORI・プラグイン・外部機能依存の静的検出 | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#205](https://github.com/eightman999/Ourin/issues/205) [P1][Doctor/Modules] 署名付きmacOSネイティブモジュールカタログと導入UX | open | 計画 / Planned | 同梱栞は対応拡充中。署名付きオンラインカタログ・追加導入UIは未実装。 / Bundled engines expanding; signed remote catalog and install UI pending. |
| [#206](https://github.com/eightman999/Ourin/issues/206) [P1][Doctor/Runtime] 起動後の基本動作チェックと未確認項目の表示 | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#207](https://github.com/eightman999/Ourin/issues/207) [P1][Doctor/Repair] 不足機能の対処・再診断・コンテンツ修復案内 | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#208](https://github.com/eightman999/Ourin/issues/208) [P1][Doctor/Report] プライバシー保護した診断レポートの保存・共有 | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#209](https://github.com/eightman999/Ourin/issues/209) [P0][Doctor/Tests] 診断→同意→導入→起動の回帰テストとリリースゲート | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#210](https://github.com/eightman999/Ourin/issues/210) [P1][Doctor/Compatibility] 実ゴースト互換性データと診断結果の紐付け | open | 計画 / Planned | 実ゴースト検証文書あり。診断アプリへの版・hash照合とオフラインDB統合は未実装。 / Evidence documents exist; app integration pending. |
| [#211](https://github.com/eightman999/Ourin/issues/211) [P1][Doctor/UX] 日本語・英語の案内文、VoiceOver、キーボード操作、初回ヘルプ | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#212](https://github.com/eightman999/Ourin/issues/212) [P2][Doctor/Contents] 導入済みゴースト・シェル・バルーン管理に再診断を統合 | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |
| [#213](https://github.com/eightman999/Ourin/issues/213) [P2][Doctor/Developers] DevTools・CLI・MCP向け診断APIと互換性トレース | open | 計画 / Planned | 計画・未実装 / Planned; dedicated Doctor implementation not yet present. |

## Closed issue照合 / Closed issues

GitHub closed一覧: #73 / #75 / #77 / #79 / #83 / #85 / #87 / #111 / #113 / #131 / #132 / #133 / #134 / #135 / #136 / #137 / #138 / #139 / #140 / #152 / #154 / #163 / #164 / #165 / #169 / #170 / #171 / #175 / #176 / #179 / #181 / #183 / #184 / #185 / #189 / #192 / #194。古い包括issueのcloseを、最新の全互換性・全翻訳完了とは扱わない。特に #87 はclosedでも翻訳プレースホルダー20件が残る。#111はwire確認、#113はEXECUTEネイティブコマンドと回帰（`210fd5d`、`OurinTests/SSTPDispatcherTests.swift`）を完了記録へ整理する。

Closed historical umbrella issues do not prove current complete compatibility or translation coverage. In particular, #87 is closed while 20 translation placeholders remain. #111 concerns native wire verification; #113 has native EXECUTE regression coverage (`210fd5d`).

## 実配布物の検証ループ（2026-10-25）

公開配布物92件を対象とする取得・実行・削除のコーパスを追加。配布元・取得URL・SHA-256・確認層を[対応一覧](compatibility-corpus/results.md)とWebで併記する。里々のBOM/文字変換・IPCと混在Windowsパスの取り込みを修正。最終件数・回帰・未対応依存は[検証記録](compatibility-corpus/validation.md)を参照。これは開発用CLIの検証基盤であり、#196–#213の診断UI・ユーザー同意・自動修復を完成扱いにはしない。

## 次の着手順 / Next work

1. P0: #96/#98/#99/#100/#103 の保護設定・正式リリース・信頼境界・配布物監査の残gate。master CI全5ジョブは成功。
2. P1: #101/#102 の実ゴーストとクリーンMac。もすの追加native依存、GUI/SAORI、最低OS/Intel実機。YAYAの上流保存形式互換。
3. P1: #109のSSP差分確認、#104の診断Exportと匿名化。#118の手動操作確認。
4. P2/P3: 描画・音声・OSイベントの実機差分、#121の自動同期、既存翻訳20件。

実装・設定・文書整備が完了した項目は再実装せず検証層を進める。[担当・モデル・実行結果](DELEGATION_2026-10-25.md)を参照。GitHub priority labelは変更していない。
