# SHIORIランタイム互換性マトリクス

**更新日:** 2026-07-14
**位置付け:** SHIORIランタイム選択・ロード・障害隔離の正本。仕様語彙はUKADOC SHIORI/3.0およびghost `descript.txt`に従う。

## 状態定義

- **実装**: 通常のGhostManager起動経路へ接続済み
- **自動試験**: 実バイナリまたは注入可能なfixtureで継続検証済み
- **実ゴースト**: 配布ゴーストで起動・会話・終了を確認済み
- **隔離**: ハング/クラッシュがOurin本体へ波及しない

## ランタイム

| 対象 | 選択規則 | 実装 | 自動試験 | 実ゴースト | 隔離 | 備考 |
|---|---|---:|---:|---:|---:|---|
| YAYA | `yaya.dll`, `libyaya.*`, `yaya_core` | 済 | 済 | Emily4回帰あり | 済 | helper障害時は終了し、次要求前にロード文脈を復元 |
| 里々 | `satori.dll`, `satoriya.dll`, `satori_core` | 済 | 実辞書＋外部SAORI fixture | `9-1`で済 | 済 | 固定版SATORIをUniversal 2 helperとして同梱 |
| Native Bundle | その他の`*.bundle/*.plugin` | 済 | Fake loader | 未 | 既定で済 | XPC Service内でC ABIをロード。明示的inprocess設定時のみ直接ロード |
| Native Dylib | その他の`*.dll/*.dylib/*.so` | 済 | Loader単体 | 未 | 既定で済 | macOSではWindows DLLを除外し、XPC Service内で代替moduleをロード |
| Native XPC | 既定。`OURIN_SHIORI_ISOLATION_MODE=inprocess`でのみ無効 | 済 | 実Service往復 | 未 | 済 | 接続単位session、load/request/unload、5秒watchdog |
| SHIORI 2.x | Native backendを互換ラッパーで変換 | 済 | 済 | 未 | backend依存 | `Shiori2CompatBackend`を使用 |

## P0受け入れ条件

- [x] `GhostShioriRuntime`に`load/request/unload`とロード状態がある
- [x] 通常起動と`execute load shiori`が同じ`descript.txt`の`shiori`値を使用する
- [x] load成功後だけGhostManagerとEventBridgeへruntimeを公開する
- [x] unload/reload時にEventBridgeが旧runtimeを保持しない
- [x] Native SHIORIが共通ワイヤCodec経由で構造化応答を返す
- [x] YAYA/里々のIPC timeout時にhelperを終了し、直列readタスクを残さない
- [x] Windows DLLとmacOS moduleが併存した場合にmacOS moduleを選択する
- [x] timeout後に同一runtimeがhelperを自動再生成し、ロード状態を復元する
- [x] Native SHIORIを実在するXPC Serviceへ隔離する

P0は2026-07-13に完了。強制終了直前の未保存VM変数やSAORI副作用は復元できず、最後に永続化された状態から再ロードする。

## P1受け入れ条件

- [x] `ukatech/satoriya-shiori`をtag/commit固定し、BSD-2-Clause本文とローカルpatch記録を保持する
- [x] SATORIのPOSIX ABIを`arm64/x86_64` Universal 2 helperへ静的リンクする
- [x] JSON Lines境界をUTF-8、SATORI内部ワイヤをCP932として変換する
- [x] `SatoriAdapter`を通常のGhostManager起動・終了・timeout復旧へ接続する
- [x] graceful unloadでSATORIの終了処理とsavedata保存を完了してからhelperを終了する
- [x] `shiori.version/encoding/forceencoding/escape_unknown`をNative境界へ反映し、里々の`escape_unknown`を往復復元する
- [x] `sakura.name2`、`makoto`、scope別`balloon.defaultsurface`を`GhostConfiguration`へ保持する
- [x] 実SATORI fixtureでOnBoot、日本語応答、Unicode escape、savedata生成を自動試験する
- [x] Xcodeビルドで`satori_core`を署名・同梱する

P1は2026-07-13に完了。

## P2受け入れ条件

- [x] 表示直前に環境変数展開 → `OnTranslate` → ghost MAKOTO → shell MAKOTOの順で変換する
- [x] `MAKOTO/2.0`の`TRANSLATE Sentence`と`String`ヘッダをNative XPCのraw backendで往復する
- [x] SSTPの`notranslate`を尊重し、`sstp.alwaystranslate=1`の場合だけSSTP表示を強制変換する
- [x] `OnTranslate`へ原因、元イベントID、元Reference群を仕様の区切りで渡す
- [x] SSTP由来の`Sender`、`SecurityLevel`、`SecurityOrigin`を`OnTranslate`へ継承する
- [x] `shiori.cache=1`のゴースト切替でruntimeをbounded LRUに保持し、Suspend/Restoreを通知する
- [x] `shiori.cache=0`、明示unload/reload、アプリ終了、LRU evictionでは`OnDestroy`後にunloadする
- [x] SATORI/YAYAがゴーストローカルと共通のSAORI検索パスを使用する
- [x] 配布物中のWindows SAORI名を`.dylib/.so`へ安全に代替する
- [x] 実SATORI＋外部SAORI native fixtureの呼び出しを自動試験する
- [x] 第三者配布の里々ゴーストで起動・会話・終了を確認する

P2は2026-07-14に完了。第三者配布ゴースト`9-1`の複製上で、OnBoot、ダブルクリック会話、SAORIメニュー、Windows SAORI呼び出し時の安全な継続、OnClose、unload、savedata生成を確認した。

## ワイヤ応答

| 項目 | 状態 | テスト/実装 |
|---|---|---|
| GET / NOTIFY、CRLF＋空行終端 | 済 | `ShioriWireCodec` |
| Charset / Sender / ID / ReferenceN | 済 | `ShioriRuntimeTests` |
| Value / ValueNotify | 済 | `ShioriRuntimeTests` |
| Reference0以降の複数応答 | 済 | `ShioriWireCodec`, `SSTPDispatcher` |
| Marker / Age / BalloonOffset / ErrorLevel | 実装済・回帰拡充待ち | `SSTPDispatcher.mapShioriResponse` |
| CP932強制・未知文字escape | 済 | Native全境界、SATORI実fixture |

## ライセンス境界

- ninix-kagariは挙動・構造の参照および差分試験に限定し、GPL実装をOurinへコピーしない。
- YAYA/里々等の上流を取り込む場合は固定リビジョンとLICENSE/NOTICEを同時に保持する。
