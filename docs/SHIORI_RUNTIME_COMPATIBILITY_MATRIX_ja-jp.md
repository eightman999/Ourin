# SHIORIランタイム互換性マトリクス

**更新日:** 2026-07-13
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
| 里々 | `satori.dll`, `satoriya.dll`, `satori_core` | 済 | 実辞書fixture | 未 | 済 | 固定版SATORIをUniversal 2 helperとして同梱 |
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

`shiori.cache`は値をロード文脈へ保持するが、OurinにSSP型のゴーストキャッシュ機構がないため実行効果はない。MAKOTOは記述値の保持のみで、translator ABI実装はP2。外部SAORIは内蔵SSU以外をP2へ分離する。

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
