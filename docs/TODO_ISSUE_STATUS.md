# TODO・GitHub issue照合 / TODO and GitHub Issue Reconciliation

**確認日 / Checked:** 2026-10-25 (JST)<br>
**対象 / Scope:** `codex/ourin-pr-integration` @ `77500e31655a3b920c036e56fe7653050f3c0265` ＋統合済み・未コミット変更 / integrated uncommitted changes.

10/24の現行ブランチ照合後、10/25に公開中のClaude PR 33件を専用worktreeへ統合。以下は元ブランチの状態を基礎に、統合済みPRと今回の外部委譲成果を反映したもの。GitHub issue/PRのclose・mergeは行っていない。最終検証結果とhead一覧は[PR引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。

After the October 24 branch audit, 33 open Claude PRs were integrated into a dedicated worktree on October 25. Integrated rows below supersede the previous branch-only status. GitHub issue/PR state remains unchanged. See the [takeover record](PR_TAKEOVER_2026-10-25.md) for exact heads and validation.

- 元ブランチで実装済み12件は[完了記録](AUDITS_COMPLETED.md)へ整理済み。
- 保留・対象外は #114 / #122 / #124。リリース判定・実ゴースト網羅は引き続き残件。
- 「ローカル統合済み」は公開版やmaster反映を意味しない。 / Local integration does not mean a public release or merge into master.

優先順と実行モデル・認証待ちは[委譲記録](DELEGATION_2026-10-25.md)、実ゴーストの判定は[検証結果](REAL_GHOST_VERIFICATION_2026-10-25.md)を参照。

**最新ローカル検証:** OurinTests 1,541実行 / 1,520集計テスト、失敗0（2026-10-25、arm64）。GUI・クリーンMac・Intel実機・認証待ちは別途残る。 / Latest local full unit run: 1,541 executions / 1,520 aggregate tests, zero failures; broader runtime/release gates remain.

## Open issue全件 / All open issues

| Issue | 現ブランチの判定 / Branch status | 根拠・残件 / Evidence and remaining work |
|---|---|---|
| [#95](https://github.com/eightman999/Ourin/issues/95) [Process] OurinをIssue駆動開発へ移行する | ローカル整備済み / Locally prepared | CONTRIBUTING・Issue/PR templates追加。運用の定着は別 / templates and workflow prepared, adoption remains. |
| [#96](https://github.com/eightman999/Ourin/issues/96) [P0][Release] master/PR に必須の macOS CI リリースゲートを導入する | ローカル整備済み・CI待ち / CI pending | Release/helper/metadata gateを追加。GitHub CI実行とbranch protection未確認。RELEASE_GATES_2026-10-25.md。 |
| [#97](https://github.com/eightman999/Ourin/issues/97) [P0][Bug] macOS minimum deployment target の不整合を解消する | ローカル整合済み / Aligned locally | app/XPC/testsをREADMEのmacOS13へ統一。metadata検査PASS。最低OS実機は未確認。公開v0.0.1.21の要件とは別。 |
| [#98](https://github.com/eightman999/Ourin/issues/98) [P0][Release] Developer ID署名・notarization・配布パッケージを確立する | 一部 / Partial | [v0.0.1.21](https://github.com/eightman999/Ourin/releases/tag/v0.0.1.21) に署名・公証済み配布の記載。`scripts/release.sh` は未追跡。1.0.0向け再現可能な署名/公証・クリーンMac検証が残る / release reports signed/notarized delivery; reproducible 1.0.0 flow and clean-Mac verification remain. |
| [#99](https://github.com/eightman999/Ourin/issues/99) [P0][Release] v1.0.0向けバージョン・リリースメタデータを整理する | 開発版整合済み / Development aligned | 0.0.1.21/build21を同期し、release時は3整数bundle版数を要求。正常/変異17ケースPASS。正式1.0.0への変更は未実施。 |
| [#100](https://github.com/eightman999/Ourin/issues/100) [P0][Security] 第三者ゴースト/SHIORI/SAORI実行の信頼モデルと権限制御を定義する | 監査文書作成・残gateあり / Audit draft | HAIがTHIRD_PARTY_TRUST_MODEL_ja-jp.mdを作成。native/XPCは権限制限そのものではない。危険操作・実配布物の境界検証は残る。 |
| [#101](https://github.com/eightman999/Ourin/issues/101) [P1][Compatibility] 実ゴースト互換性マトリクスを拡充する | 検証拡充 / Expanded | KAWARI/KAGARI Universal2同梱・実エンジンXPC成功。LOBO/Emily4/Taromati2を複製上で検証。もすnative依存・GUI/実SAORI・広い網羅は残る。 |
| [#102](https://github.com/eightman999/Ourin/issues/102) [P1][QA] クリーンMacでインストール〜NAR〜再起動までのE2Eリリース試験を整備する | チェックリスト整備・実機待ち / Device pending | RELEASE_GATESに手順追加。クリーンMac install→NAR→保存→再起動と最低OS実機は未確認。 |
| [#103](https://github.com/eightman999/Ourin/issues/103) [P0][Legal] v1.0.0配布物の第三者ライセンス・再配布条件を最終監査する | 部分監査 / Partial audit | HAI監査文書と新エンジン5通知の現物一致確認。正式archive全依存監査、既定ghost通知の名称差、素材権利記録は残る。 |
| [#104](https://github.com/eightman999/Ourin/issues/104) [P1][Release] Known Issues・バグ報告導線・診断情報を整備する | 文書整備済み・一部残件 / Docs prepared | Known Issues/報告手順の日英文書・bug template追加。toolbarログExportとDebug診断stubの差、自動匿名化などは残る。 |
| [#105](https://github.com/eightman999/Ourin/issues/105) [Meta][Release] Ourin v1.0.0-beta.1 / v1.0.0 リリーストラッカー | 追跡 / Tracker | v1.0.0-beta.1→v1.0.0、日程未定。PR #125取込済み、P0/P1 gate残存 / PR #125 merged; release gates remain. |
| [#106](https://github.com/eightman999/Ourin/issues/106) [compat/SSTP] Sender と User-Agent の両方無しリクエストの 400 拒否が未実装 | 実装済み / Implemented | `Ourin/SSTP/SSTPDispatcher.swift` (`refuseIfMissingSenderAndUserAgent`); `OurinTests/SSTPCompatRegressionTests.swift` |
| [#107](https://github.com/eightman999/Ourin/issues/107) [compat/SSTP] SHIORI 非標準ステータスを 204 に丸める変換が未実装 | 実装済み / Implemented | `Ourin/SSTP/SSTPDispatcher.swift`; `OurinTests/SSTPCompatRegressionTests.swift` |
| [#108](https://github.com/eightman999/Ourin/issues/108) [compat/SSTP] X-Force-Activate-Me ヘッダによるウィンドウアクティブ化が未実装 | 実装済み / Implemented | `Ourin/SSTP/SSTPDispatcher.swift`; `OurinTests/SSTPCompatRegressionTests.swift` (実窓確認は別 / real-window check separate) |
| [#109](https://github.com/eightman999/Ourin/issues/109) [compat/SSTP] FINE メソッド（MessageSend/SetScript/SetScriptPartial）が未実装 | ローカル修正・差分残 / Locally fixed | z.ai＋統合修正でFINE行subcommand/Reference3本文、単一宛先配送・wire回帰を追加。SSP優先ghost fallbackと曖昧Reference仕様は未確定。 |
| [#110](https://github.com/eightman999/Ourin/issues/110) [compat/SSTP] X-SSTP-Return- への PassThru フォールバックが未実装 | 実装済み / Implemented | `Ourin/SSTP/SSTPDispatcher.swift`; `OurinTests/SSTPCompatRegressionTests.swift` |
| [#112](https://github.com/eightman999/Ourin/issues/112) [compat/SHIORI] SecurityOrigin 無し時の 'null' 送出が未実装 | 実装済み / Implemented | `Ourin/SSTP/SSTPDispatcher.swift`; `OurinTests/ShioriRuntimeTests.swift` |
| [#114](https://github.com/eightman999/Ourin/issues/114) [compat] mcp.exe は MCP サーバであり ukagaka 互換対象外（記録） | 対象外 / Out of scope | mcp.exe はMCP serverとして記録。伺か互換実装のTODOから除外 / excluded from compatibility implementation. |
| [#115](https://github.com/eightman999/Ourin/issues/115) [compat/Property] selfname が sakuraname の別名として未解決 | 実装済み / Implemented | `Ourin/Property/GhostPropertyProvider.swift`; `OurinTests/PropertySystemTests.swift` |
| [#116](https://github.com/eightman999/Ourin/issues/116) [compat/SERIKO] interval 略称と never 複合の挙動が SSP と異なる | 実装済み / Implemented | `Ourin/Animation/SerikoParser.swift`, `SerikoExecutor.swift`; `OurinTests/SerikoParserTests.swift`, `SerikoExecutorTests.swift` |
| [#117](https://github.com/eightman999/Ourin/issues/117) [compat/SERIKO] method ccyr / noop が未実装 | 実装済み / Implemented | `Ourin/Animation/SerikoParser.swift`; `OurinTests/SerikoParserTests.swift` |
| [#118](https://github.com/eightman999/Ourin/issues/118) [compat/Input] scriptbox 入力種別が未実装 | ローカル修正済み / Locally fixed | z.aiがscriptbox/textareaboxのopen/close誤配線を修正。入力窓生成とclose回帰テスト。Macロック中で手動画面操作未確認。 |
| [#119](https://github.com/eightman999/Ourin/issues/119) [compat/Calendar] PlayTodaysEvent（#todays event header）が未実装 | 実装済み / Implemented | `Ourin/Calendar/CalendarSchedule.swift`, `CalendarWindow.swift`; `OurinTests/CalendarScheduleTests.swift` |
| [#120](https://github.com/eightman999/Ourin/issues/120) [compat/Cookie] SSTP Cookie のディスク永続化が未実装（メモリのみ） | 実装済み / Implemented | `Ourin/SSTP/SstpSessionStore.swift`; `OurinTests/SSTPDispatcherTests.swift` (Sender単位の最低要件 / minimum Sender-scoped requirement) |
| [#121](https://github.com/eightman999/Ourin/issues/121) [compat/SaveShare] OneDrive/Dropbox クラウドセーブ（.ssg）が未実装 | 一部 / Partial | `Ourin/SaveShare/SaveShareManager.swift` とテストで手動.ssg入出力済み。cloud検出/load-unload同期が残る / manual import/export done; automatic cloud sync pending. |
| [#122](https://github.com/eightman999/Ourin/issues/122) [compat] IP Messenger / MsgSender 連携が未実装 | 保留 / Deferred | `1c30313`でIP Messenger対象外記録。必要時にMsgSenderも含め方針再検討 / revisit interoperability if required. |
| [#123](https://github.com/eightman999/Ourin/issues/123) [compat/Sound] http(s)/ストリーミング URL 再生が未対応（ローカルのみ） | 実装済み / Implemented | `Ourin/Ghost/GhostManager+Display.swift`; `OurinTests/SoundPlayerTests.swift` (実再生は別 / actual playback separate) |
| [#124](https://github.com/eightman999/Ourin/issues/124) [compat/FMO] FineFMO 共有メモリが未実装 | 保留 / Deferred | Windows FineFMO共有メモリは未実装。通常POSIX FMOとは別契約 / FineFMO remains a platform gap, distinct from implemented POSIX FMO. |
| [#131](https://github.com/eightman999/Ourin/issues/131) [compat/Execute] WebSocket イベントが UKADOC と不一致（Reference の並び・Failure/Reconnect/_SSLInfo・--async） | ローカル統合済み / Locally integrated | PR #142を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#132](https://github.com/eightman999/Ourin/issues/132) [compat/Events] OnIdle に時刻系の Reference（トーク可否・放置秒数）を付ける | 実装済み / Implemented | `Ourin/SHIORIEvents/TimerEmitter.swift`, `EventReferenceSpec.swift`; `OurinTests/EventObserverLifecycleTests.swift`, `EventReferenceTableTests.swift`; `0a2a37d` |
| [#133](https://github.com/eightman999/Ourin/issues/133) [compat/Execute] \![execute,filewatch] と OnExecuteFileWatchChange/Failure が未実装 | ローカル統合済み / Locally integrated | PR #143を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#134](https://github.com/eightman999/Ourin/issues/134) [compat/Events] OnDesktopWallpaperChange が未実装 | ローカル統合済み / Locally integrated | PR #144を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#135](https://github.com/eightman999/Ourin/issues/135) [compat/Input] textareabox と OnTextAreaInput/OnTextAreaInputCancel が未実装 | ローカル統合済み / Locally integrated | PR #145を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#136](https://github.com/eightman999/Ourin/issues/136) [compat/Calendar] schedule-add/delete/get と OnExecuteSchedule*、OnScheduleTodayNotify が未実装 | ローカル統合済み / Locally integrated | PR #147を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#137](https://github.com/eightman999/Ourin/issues/137) [compat/Execute] ical-get/ical-post と OnExecuteICal* が未実装 | ローカル統合済み / Locally integrated | PR #148を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#138](https://github.com/eightman999/Ourin/issues/138) [compat/Sound] OnSoundSpectrum が未実装 | ローカル統合済み / Locally integrated | PR #150を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#139](https://github.com/eightman999/Ourin/issues/139) [compat/SAORI] 内蔵SAORIの非同期呼び出し OnInternalSaoriComplete/Failure が未実装 | ローカル統合済み / Locally integrated | PR #155を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#140](https://github.com/eightman999/Ourin/issues/140) [compat/Calendar] OnNotifyHolidayInfo が未実装 | ローカル統合済み / Locally integrated | PR #149を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#141](https://github.com/eightman999/Ourin/issues/141) [Meta][compat/Events] UKADOC の SHIORI イベントの不足・不一致への対応 | 追跡 / Tracker | #131〜140のレビュー/統合と祝日表運用。#132は現ブランチ実装済み / review/integrate event changes; #132 implemented here. |
| [#151](https://github.com/eightman999/Ourin/issues/151) [compat/SAORI] SAORI over DirectSSTP と内蔵モジュール（internal_*）が未実装 | 未反映 / Not integrated | 現`Ourin/SaoriHost`/SSTPにinternal_*基盤なし。issueにPR #155を記載 / internal SAORI foundation not in this branch; track #155. |
| [#152](https://github.com/eightman999/Ourin/issues/152) [compat/SAORI] internal_crypto（ハッシュ・暗号・鍵導出・署名など）が未実装 | ローカル統合済み / Locally integrated | PR #160を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#153](https://github.com/eightman999/Ourin/issues/153) [compat/SAORI] internal_jwt（JWT の作成と検証）が未実装 | ローカル統合済み / Locally integrated | PR #159を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#154](https://github.com/eightman999/Ourin/issues/154) [compat/SAORI] internal_file（MediaInfo）と互換モジュールの扱いが未実装 | ローカル統合済み / Locally integrated | PR #162を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#161](https://github.com/eightman999/Ourin/issues/161) ゴーストのシェル／バルーン読み込み不具合と切り替えメニューの日本語化要望 | 検証待ち / Verification | 表示/メニュー改善はあるが報告ゴーストでの再現・解消未確認。#184/#192とも照合 / reproduce reported shell/balloon problems. |
| [#163](https://github.com/eightman999/Ourin/issues/163) [compat/i18n] 日本語以外の文字コード（Big5・GBK・EUC-KR・Windows-1252 など）を読めない | ローカル統合済み / Locally integrated | PR #166を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#164](https://github.com/eightman999/Ourin/issues/164) [i18n] UI の多言語化（日本語の直書きを英語・日本語で切り替え、中国語・韓国語を追加） | ローカル統合済み / Locally integrated | PR #168を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#165](https://github.com/eightman999/Ourin/issues/165) [compat/Calendar] 外国の祝日（holidays-XX.txt）と言語ごとの祝日名 | ローカル統合済み / Locally integrated | PR #167を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#169](https://github.com/eightman999/Ourin/issues/169) NAR インストーラで LZMA 圧縮の NAR を展開できない | ローカル統合済み / Locally integrated | PR #172を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#170](https://github.com/eightman999/Ourin/issues/170) 別名の DLL（aya.dll など）で同梱された YAYA を YAYA として起動する | ローカル統合済み / Locally integrated | PR #173を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#171](https://github.com/eightman999/Ourin/issues/171) yaya_core で Big5・GBK・EUC-KR の辞書を読む | ローカル統合済み / Locally integrated | PR #174を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#175](https://github.com/eightman999/Ourin/issues/175) yaya_core が Taromati2 の辞書の YAYA 構文を解析できない | ローカル統合済み / Locally integrated | PR #178を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#176](https://github.com/eightman999/Ourin/issues/176) yaya_core が関数の呼び出しの深さに上限を持たず、再帰でスタックを使い切って落ちる | ローカル統合済み / Locally integrated | PR #177を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#179](https://github.com/eightman999/Ourin/issues/179) yaya_core のファイル関数を YAYA に合わせ、ゴーストの profile フォルダを用意する | ローカル統合済み / Locally integrated | PR #180取込み後、FOPEN/FREADのfilename契約・EOF・SAVEVAR既定保存先・GETVARLISTを修正。Emily4/Taromati2の保存・別process再load成功。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#181](https://github.com/eightman999/Ourin/issues/181) Xcode の増分ビルドで yaya_core・satori_core のソースの変更が反映されない | ローカル統合済み / Locally integrated | PR #182を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#183](https://github.com/eightman999/Ourin/issues/183) 直下にフォルダが1つだけある NAR（Taromati2.nar など）をインストールできない | ローカル統合済み / Locally integrated | PR #186を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#184](https://github.com/eightman999/Ourin/issues/184) ゴーストの descript.txt の balloon（標準バルーン）を使わない | ローカル統合済み / Locally integrated | PR #187を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#185](https://github.com/eightman999/Ourin/issues/185) \![open,inputbox] などの入力ボックスがモーダルで、閉じるまでアプリ全体が止まる | ローカル統合済み / Locally integrated | PR #188を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#189](https://github.com/eightman999/Ourin/issues/189) yaya_core が %(username) など SSP の環境変数と同じ名前の埋め込み要素を展開しない | ローカル統合済み / Locally integrated | PR #190を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#192](https://github.com/eightman999/Ourin/issues/192) バルーンの descript.txt の font.color・font.height が、表示した最初の本文に使われない | ローカル統合済み / Locally integrated | PR #193を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.
| [#194](https://github.com/eightman999/Ourin/issues/194) OnSurfaceRestore がサーフェス変更の 15 秒後に送られ、選択肢待ちのバルーンを消す | ローカル統合済み / Locally integrated | PR #195を専用worktreeへ取り込み済み。統合テスト結果・残る制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)を参照。GitHubはopen。 / Integrated locally; see validation and limitations in the takeover record.

## Closed issue照合 / Closed issues

GitHub closed一覧は #73 / #75 / #77 / #79 / #83 / #85 / #87 / #111 / #113。古い包括issueのcloseを、最新の全互換性・全翻訳完了とは扱わない。特に #87 はclosedでも翻訳プレースホルダー20件が残る。#111はwire確認、#113はEXECUTEネイティブコマンドと回帰（`210fd5d`、`OurinTests/SSTPDispatcherTests.swift`）を完了記録へ整理する。

Closed historical umbrella issues do not prove current complete compatibility or translation coverage. In particular, #87 is closed while 20 translation placeholders remain. #111 concerns native wire verification; #113 has native EXECUTE regression coverage (`210fd5d`).

## 次の着手順 / Next work

1. P0: #96/#98/#99/#100/#103 の正式リリース・remote CI・信頼境界・配布物監査の残gate。
2. P1: #101/#102 の実ゴーストとクリーンMac。もすの追加native依存、GUI/SAORI、最低OS/Intel実機。YAYAの上流保存形式互換。
3. P1: #109のSSP差分確認、#104の診断Exportと匿名化。#118の手動操作確認。
4. P2/P3: 描画・音声・OSイベントの実機差分、#121の自動同期、既存翻訳20件。

実装・設定・文書整備が完了した項目は再実装せず検証層を進める。[担当・モデル・実行結果](DELEGATION_2026-10-25.md)を参照。GitHub priority labelは変更していない。
