# Claude PR引継ぎ・統合記録 / Claude PR Takeover

**確認日 / Checked:** 2026-10-25 JST

ユーザー依頼により公開中の33 PRを引き継いだ。元の作業ツリーとClaudeのworktreeを保全し、専用worktreeへローカル統合した。GitHubのmerge/close、commit/pushは行っていない。 / Took over 33 open PRs in a dedicated worktree; original checkouts preserved. No remote merge/close, commit or push.

- 作業コピー / Worktree: `/Users/eightman/.codex/worktrees/ourin-pr-integration/Ourin`
- 基点 / Baseline: `77500e31655a3b920c036e56fe7653050f3c0265` (`test/all-verify`)。ローカル作業ブランチ: `codex/ourin-pr-integration`。32 PRのheadを祖先として確認。
- 追加 / Added: PR #195 (`0459da1`) の差分と現行ブランチ `3bcf86b` のDLL互換修正。
- 競合解消 / Resolution: `SaoriManager` は内蔵/互換SAORIとネイティブモジュールのVersion handshakeを両方維持。
- 作業ツリーの既存 `Plugins/ScriptBridge` とそのテストもコピーし、統合側での回帰対象に含めた（元ファイルは変更なし）。
- 除外 / Excluded: `b5db96f` のローカル専用 `VerifySnapshotter` と呼び出しを逆適用。
- 既存heap修正 / Existing heap fix: `66749e3` とroot作業ツリーの関連修正を包含。元統合の1465 PASS記録は今回の検証を代替しない。

## PR一覧 / Pull requests

| PR | 内容 / Change | Head | 関連issue / Issues |
|---|---|---|---|
| [#142](https://github.com/eightman999/Ourin/pull/142) | fix(websocket): WebSocket の SHIORI イベントを UKADOC 2.8.05 に合わせる | `236252ea` | #131 |
| [#143](https://github.com/eightman999/Ourin/pull/143) | feat(filewatch): \![execute,filewatch] と OnExecuteFileWatchChange/Failure を実装する | `0df877fa` | #133 |
| [#144](https://github.com/eightman999/Ourin/pull/144) | feat(events): OS の壁紙変更を OnDesktopWallpaperChange で通知する | `c9d195bd` | #134 |
| [#145](https://github.com/eightman999/Ourin/pull/145) | feat(input): 複数行入力ボックス textareabox と OnTextAreaInput/Cancel を実装する | `9fb01a50` | #135 |
| [#146](https://github.com/eightman999/Ourin/pull/146) | feat(ghost): 標準ゴーストを さくら・りんね・ベル に刷新し、Emily の同梱をやめる | `6cf6a589` | #132 |
| [#147](https://github.com/eightman999/Ourin/pull/147) | feat(calendar): ゴースト用予定表 schedule-add/delete/get と OnScheduleTodayNotify を実装する | `27cdc118` | #136 |
| [#148](https://github.com/eightman999/Ourin/pull/148) | feat(calendar): \![execute,ical-get/ical-post] と OnExecuteICal* を実装する | `a34767a1` | #137 |
| [#149](https://github.com/eightman999/Ourin/pull/149) | feat(events): 起動時に今日の祝日名を OnNotifyHolidayInfo で通知する | `96e42fb4` | #140 |
| [#150](https://github.com/eightman999/Ourin/pull/150) | feat(sound): --spectrum 指定のサウンドで OnSoundSpectrum を通知する | `3bf3db8d` | #138 |
| [#155](https://github.com/eightman999/Ourin/pull/155) | feat(saori): SAORI over DirectSSTP の基盤と内蔵モジュール（system/random/time/text/data）を実装する | `07f7988d` | #139 |
| [#156](https://github.com/eightman999/Ourin/pull/156) | feat(saori): internal_crypto 第1段（ハッシュ・HMAC・暗号化・鍵導出・TOTP・署名） | `b4471f0d` | — |
| [#157](https://github.com/eightman999/Ourin/pull/157) | feat(saori): internal_jwt（JWT の作成と検証） | `11d541c5` | — |
| [#158](https://github.com/eightman999/Ourin/pull/158) | feat(saori): internal_file の MediaInfo | `0a809ccc` | — |
| [#159](https://github.com/eightman999/Ourin/pull/159) | feat(saori): RSA（rs256・ps256・鍵生成）と JWT の RS256/PS256 | `17947227` | — |
| [#160](https://github.com/eightman999/Ourin/pull/160) | feat(saori): internal_crypto の残り（sha3・blake2・scrypt・argon2id・bip340・KeyAgreement・crypt 系・Protect） | `7731703d` | #152 |
| [#162](https://github.com/eightman999/Ourin/pull/162) | feat(saori): SSP の互換モジュール 10 種を内蔵して DLL を差し替える | `7fa70d5d` | #154 |
| [#166](https://github.com/eightman999/Ourin/pull/166) | feat(i18n): 日本語以外の文字コードに対応（Big5・GBK・EUC-KR・Windows-125x など） | `f68ba0a9` | #163 |
| [#167](https://github.com/eightman999/Ourin/pull/167) | feat(calendar): 外国の祝日表と言語ごとの祝日名 | `ff597727` | #165 |
| [#168](https://github.com/eightman999/Ourin/pull/168) | feat(i18n): UI を英語・日本語・簡体字・繁体字・韓国語に対応 | `89964c3f` | #164 |
| [#172](https://github.com/eightman999/Ourin/pull/172) | fix(nar): LZMA 圧縮の NAR を bsdtar で展開できるようにする | `ba422f23` | #169 |
| [#173](https://github.com/eightman999/Ourin/pull/173) | feat(shiori): 別名の DLL（aya.dll など）で同梱された YAYA を YAYA として起動する | `f87e9d1b` | #170 |
| [#174](https://github.com/eightman999/Ourin/pull/174) | feat(yaya): yaya_core で Big5・GBK・EUC-KR の辞書を読む | `1355b3a8` | #171 |
| [#177](https://github.com/eightman999/Ourin/pull/177) | fix(yaya): 関数の呼び出しの深さに上限を設け、再帰で yaya_core が落ちないようにする | `f39552f7` | #176 |
| [#178](https://github.com/eightman999/Ourin/pull/178) | fix(yaya): Taromati2 の辞書の YAYA 構文を yaya_core で解析できるようにする | `d47027cf` | #175 |
| [#180](https://github.com/eightman999/Ourin/pull/180) | fix(yaya): ファイル関数を YAYA に合わせ、ゴーストの profile フォルダを用意する | `b413ec51` | #179 |
| [#182](https://github.com/eightman999/Ourin/pull/182) | fix(build): ソースの変更で yaya_core・satori_core を作り直す | `9b9104e3` | #181 |
| [#186](https://github.com/eightman999/Ourin/pull/186) | fix(nar): フォルダごと圧縮した NAR を、その中をルートとしてインストールする | `f8da7229` | #183 |
| [#187](https://github.com/eightman999/Ourin/pull/187) | fix(balloon): ゴーストの descript.txt の標準バルーンを、インストール済みのバルーンから選ぶ | `c0709463` | #184 |
| [#188](https://github.com/eightman999/Ourin/pull/188) | fix(input): 入力ボックスをモーダルにせず、閉じるまでアプリ全体を止めない | `625b991e` | #185 |
| [#190](https://github.com/eightman999/Ourin/pull/190) | fix(yaya_core): %(…) を SSP の環境変数と同じ名前でも YAYA の式として評価する | `bb550fb6` | #189 |
| [#191](https://github.com/eightman999/Ourin/pull/191) | fix(yaya): 配列要素の ++/-- と文字列への添字を解析し、簡易配列の要素を YAYA と同じく読み書きする | `beb19bbb` | — |
| [#193](https://github.com/eightman999/Ourin/pull/193) | fix(balloon): descript.txt の font.color・font.height を表示の最初から本文に使う | `e085dec6` | #192 |
| [#195](https://github.com/eightman999/Ourin/pull/195) | fix(surface): OnSurfaceRestore をバルーンが閉じてから 15 秒後に一度だけ送る | `0459da1c` | #194 |

## PR統合時点の検証 / Validation before subsequent delegated changes

- YAYA `./build.sh`: PASS（arm64/x86_64）。
- `build-for-testing`: TEST BUILD SUCCEEDED。
- 実アプリ: 一時データディレクトリでsakura.nar導入→標準ゴースト表示→ダブルクリックからOnMouseDoubleClick応答→設定を開閉→通常終了(exit 0)を確認。ユーザーのghostデータは使用していない。 / Verified the real app with isolated temporary data.
- 追加委譲前の統合OurinTests: **PASS、1,509実行ケース・失敗0件**（パラメータ展開前1,498テスト）。`/tmp/ourin-integration-final-20261025.xcresult`、macOS 26.6.2 / arm64、exit 0。 / Integration before subsequent changes: 1,509 executions passed, zero failures (1,498 tests before parameter expansion).
- 統合時の修正: XPC起動handshakeの固定2秒を設定済みload期限へ統一。SHIOLINK失敗系テストは子process生成直後のPIDを使って回収確認。iCal非同期テストはMainActor高負荷時の通知確認を修正。 / Fixed XPC startup deadline handling and race-prone process/notification test assertions.
- SHIOLINKの実アプリ起動: 合成fixtureを一時ghostディレクトリから起動し、`kind=shiolink`、OnBoot成功、本文トークン出力をログで確認。Macがロックされていたため画面確認は未実施。 / Real app loaded the synthetic SHIOLINK fixture and processed its OnBoot script; visual confirmation was blocked by the locked Mac.
- OurinUITests、実Emily4（`OURIN_EMILY4_DIR`未指定）、実音声デバイスによる網羅検証は未実施。環境依存テストの早期returnがあるため、集計のskip 0件を実環境網羅とは扱わない。 / UI tests, real Emily4 and complete audio-device coverage were not run; some environment-dependent tests return early.

## 残件 / Remaining

- 実ゴーストの網羅、音声デバイス・壁紙・外部SSTPなど実環境の検証。
- PR #191記載のTaromati2 OnMinuteChange停止、配列delimiter／foreach／SAVEVARの問題は追加修正・複製上の再検証済み。上流保存形式importや広い実ゴースト網羅は残る。[現在の実ゴースト結果](REAL_GHOST_VERIFICATION_2026-10-25.md)を参照。
- 華和梨/KAGARIの実エンジンをUniversal 2で同梱し、in-process/XPCを検証済み。「もす」のmacOS native依存とその他の辞書言語は残件。実装なしの栞を対応済みとしない。


## 栞拡張 / SHIORI expansion

- [Native ABI](NATIVE_SHIORI_ABI_ja-jp.md): app/XPC共通の明示ABI、32/64bit長、load辞書dir、load失敗とプロセス隔離の回帰を追加。
- [SHIOLINK](SHIOLINK_ja-jp.md): 本番factoryへ接続、実子processでload/GET/NOTIFY/unload、期限・同期・上限・子回収を検証。MiyoJS実ゴーストは未検証。
- [華和梨/KAGARIの実装記録](KAWARI_KAGARI_ENGINES_ja-jp.md): 固定版、ライセンス通知、Universal 2 build、専用ABI、最小辞書のload/request/unloadを検証。華和梨LOBOは保存→再ロード成功。KAGARI「もす」は依存不足で未完。
- 美坂・灯・ese-shiori・偽栞・忍・翡翠・結奈・里珠は未対応。原版・参考実装の対応範囲を区別し、暗号化辞書やSAORI等の制限も個別記録する。

Native ABI and SHIOLINK are wired into the development build, with process-level fixtures. Real MiyoJS compatibility is unverified. KAWARI and KAGARI are now bundled and tested through in-process/XPC paths; KAWARI LOBO passed lifecycle checks, while KAGARI Mosu still lacks a macOS native dependency. Other listed engines remain unsupported. A support label requires a pinned implementation, license review, macOS build and real dictionary lifecycle evidence, not only a loader or sample parser.


## 追加委譲後の検証 / Validation after delegated changes

作業先: `/Users/eightman/.codex/worktrees/ourin-pr-integration/Ourin`。root作業ツリーのアプリコードは上書きせず、TODO・検証資料を同期した。commit/pushは実施していない。

The implementation remains in the dedicated worktree. Root application edits were preserved; only task documentation and templates were synchronized. No commit or push was made.

- 同梱KAWARI/KAGARI・Native ABI・FINE/scriptboxの先行対象検証: **42実行 / 35固有テスト、失敗0/skip0**。`/tmp/ourin-engines-targeted-20261025.xcresult`。
- YAYA実helperのファイル・永続化回帰: **9件PASS**。実ゴースト結果は[専用記録](REAL_GHOST_VERIFICATION_2026-10-25.md)。
- 全体r3で旧handle/文字コード変換APIを前提とするテスト2件が失敗。標準filename、FWRITE改行、FREADENCODE/FWRITEDECODEのbase64契約へfixtureを修正。多言語辞書のencoding検証を維持し、関連3件がPASS。`/tmp/ourin-yaya-charset-targeted-r2-20261025.xcresult`。
- 今回の試験準備中にtestmanagerdの接続停止を確認し、停止した試行は成功件数に含めていない。r3は実行完了後に上記2件の失敗を集計した。
- 現在の全体実行結果: **PASS、1,541実行ケース / 1,520集計テスト、失敗0・報告skip0**。`/tmp/ourin-delegated-unit-final-r4-20261025.xcresult`、macOS 26.6.2 / arm64、exit 0。`xcresulttool get test-results summary`のdevice別実行数1541と総テスト数1520を区別。 / Final full unit run passed: 1,541 parameter-expanded executions, 1,520 aggregate tests, zero failures or reported skips.
- 最終OurinUITestsは未実施。Macロック中のため、今回のLOBO実appはXPC/OnBootログまで確認し、画面操作を確認済みとはしない。環境変数未指定で早期returnするテストがあり、集計のskip0を実環境網羅とは扱わない。

Targeted engine tests and real-helper regressions passed. The first completed full run exposed two obsolete test fixtures; those were corrected and three related tests passed. Interrupted test-manager sessions are excluded from success counts. UI, physical Intel/minimum-macOS and clean-Mac validation remain separate. Some tests return early without optional environment fixtures, so zero reported skips does not establish complete real-world coverage.


## 公開用ブランチ / Publication branch

上記の「未コミット・未push」は検証完了時点の記録。続くユーザーのcommit/push指示を受け、`codex/ourin-pr-integration-publish` に最終状態をまとめる。元のローカル統合履歴を保持し、検証専用snapshotコミットを公開履歴へ含めない。コードの最終treeは検証済み統合版と一致させる。GitHub PRのmerge・issueのcloseは別途未実施。

The preceding uncommitted/unpushed statements describe the validation checkpoint. Following the user’s commit/push instruction, the final tree is consolidated on `codex/ourin-pr-integration-publish`, preserving the original local history while excluding its local-only snapshot commit from public ancestry. No GitHub PR merge or issue closure is performed.
