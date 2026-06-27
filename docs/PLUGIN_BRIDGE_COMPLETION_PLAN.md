# Plugin Bridge 完全実装計画

**作成日:** 2026-06-26  
**対象:** Ourin の PLUGIN/2.0M bridge / SSP PLUGIN 互換 / PLUGIN/1.0 挙動互換  
**目的:** UKADOC PLUGIN/2.0 の request/response、PLUGIN Event、plugin descript、旧 PLUGIN/1.0 由来の挙動を、macOS native plugin bridge として実用互換レベルまで実装する。

## 参照仕様

- UKADOC PLUGIN/2.0: https://ssp.shillest.net/ukadoc/manual/spec_plugin.html
- UKADOC PLUGIN Event: https://ssp.shillest.net/ukadoc/manual/list_plugin_event.html
- UKADOC Plugin descript.txt: https://ssp.shillest.net/ukadoc/manual/descript_plugin.html
- PLUGIN/1.0 参考: http://usada.sakura.vg/contents/plugin.html
- Ourin 仕様: `docs/SPEC_PLUGIN_2.0M_ja-jp.md`
- Ourin イベント仕様: `docs/PLUGIN_EVENT_2.0M_SPEC_ja-jp.md`

## 完了定義

Plugin bridge 完全実装とは、以下を満たす状態とする。

1. プラグインへの送信が PLUGIN/2.0 の wire semantics に準拠する。
2. プラグインからの `Event` / `Reference*` / `Target` / `Script` / `ScriptOption` / `EventOption` 応答が、ゴーストへ仕様通り橋渡しされる。
3. UKADOC PLUGIN Event リストの全イベントについて、少なくとも「正しい ID、GET/NOTIFY、Reference 順」で送信経路がある。
4. `descript.txt` の `charset` / `secondchangeinterval` / `otherghosttalk` が実動作へ接続される。
5. `property.get` / `property.set` が `pluginlist(...).ext` 系の拡張プロパティとして plugin へ委譲される。
6. Shift_JIS/CP932 plugin と UTF-8 plugin の双方で、request/response の文字化けがない。
7. PLUGIN/1.0 は macOS 上で Windows DLL を直接ロードしないが、イベント名・メニュー呼び出し・旧 descript 由来 metadata の挙動互換を提供する。

## 現状サマリ

更新 2026-06-27: 本計画の runtime bridge 項目は実装済み。`Charset` の byte encode/decode、`Target`
配送、`Event`/`Script` fallback、`ScriptOption`、plugin 別 `secondchangeinterval`、`otherghosttalk`
before/after、catalog/install/ghost/menu event wiring、`pluginlist(...).ext` property 委譲、PLUGIN/1.0
metadata 互換、DevTools console、選択肢/アンカーの plugin-origin one-shot hook を接続した。回帰は
`PluginEncodingTests`、`PluginTargetRoutingTests`、`PluginPropertyBridgeTests` と既存 matrix、および full
`xcodebuild -project Ourin.xcodeproj -scheme Ourin test` で検証する。

実装済み:

- `.plugin` / `.bundle` 検出と `request` / `loadu` / `unload` 呼び出し。
- `PluginFrame` による GET/NOTIFY フレーム構築。
- `PluginEventDispatcher` による plugin 単位の直列 dispatch。
- `OurinPluginEventBridge` による `raiseplugin` / `notifyplugin` 応答 bridge。
- `EventOption: notify`、`ScriptOption` parse、`__SYSTEM_ALL_GHOST__` の基本受理。
- `OnChoiceSelect(Ex)` / `OnAnchorSelect(Ex)` の plugin-origin one-shot 横流し。
- negotiated `Charset` に基づく実 byte encode/decode。
- `Target` の特定 ghost / all ghost / baseware 配送。
- `notranslate` / `nobreak` の SakuraScript 実行制御。
- `property.get` / `property.set` の plugin 委譲。
- `OnOtherGhostTalk` の実発話 pipeline 接続と `before` / `after`。
- catalog 系通知の起動時・install 時 wiring。
- PLUGIN/1.0 由来 plugin metadata / menu/message 挙動互換。

## Phase 0: 実装状況の棚卸しと仕様同期

**目的:** 古い docs と実コードのずれをなくし、後続実装の基準を固定する。

対象:

- `docs/SPEC_PLUGIN_2.0M_ja-jp.md`
- `docs/PLUGIN_EVENT_2.0M_SPEC_ja-jp.md`
- `docs/PLUGIN_COMPAT_FIX_PROPOSAL.md`
- `Ourin/PluginEvent/*`
- `Ourin/PluginHost/*`

作業:

1. UKADOC のイベント一覧を Ourin 実装表へ転記し直す。
2. 各イベントを `implemented` / `helper-only` / `not wired` / `not implemented` に分類する。
3. 既存 docs の「実装済み」表現を、helper-only と runtime-wired に分ける。

受け入れ条件:

- docs の実装状況と `rg` で確認できるコードが矛盾しない。
- 各未実装項目がこの計画書の Phase に対応する。

## Phase 1: Wire charset を byte レベルで実装

**目的:** PLUGIN/2.0 の `Charset` を実際の request/response encode/decode に反映する。

対象:

- `Ourin/PluginHost/Plugin.swift`
- `Ourin/PluginHost/PluginProtocol.swift`
- `Ourin/PluginEvent/PluginEncodingNormalizer.swift`
- `Ourin/PluginEvent/PluginEventDispatcher.swift`
- `OurinTests/OurinPluginEventBridgeTests.swift`
- 新規: `OurinTests/PluginEncodingTests.swift`

作業:

1. `Plugin.send` を `String.Encoding` 指定可能にする。
2. `PluginRequest` build 後の wire を negotiated charset で byte 化する。
3. plugin response を response `Charset` または request charset で decode し、内部 UTF-8 `String` へ正規化する。
4. `version` 応答の `Charset` を plugin ごとに保持し、次回 request へ適用する。
5. Shift_JIS/CP932 の round-trip fixture plugin または mock request 関数をテストに追加する。

受け入れ条件:

- `Charset: Shift_JIS` plugin に日本語 `Reference*` を送っても文字化けしない。
- Shift_JIS response の `Script` / `Event` / `Reference*` を UTF-8 内部文字列として扱える。
- UTF-8 plugin の既存テストが退行しない。

## Phase 2: Target routing の完全化

**目的:** `Target` が指定された plugin response を、仕様通り対象 ghost へ返す。

対象:

- `Ourin/PluginEvent/OurinPluginEventBridge.swift`
- `Ourin/SHIORIEvents/EventBridge.swift`
- `Ourin/Ghost/GhostManager.swift`
- `Ourin/Ghost/GhostManager+System.swift`
- `Ourin/SSTP/BridgeToSHIORI.swift`

作業:

1. `PluginTransportAction.target` を文字列のまま判定するだけでなく、配送先 resolver に渡す。
2. target resolver を追加する。
   - `nil` / empty: 呼び出し元 ghost を優先し、なければ active ghost。
   - `__SYSTEM_ALL_GHOST__`: 起動中全 ghost。
   - ghost name / ghost id / ghost path / owned SSTP id: 該当 ghost。
   - `baseware` / `ourin`: baseware 側処理。
3. `raiseplugin` 呼び出し元 ghost を action context に保持する。
4. `PluginEventDispatcher` の system event 由来 response は active ghost または target 指定に従う。
5. target 不一致時は fallback script を実行しない。

受け入れ条件:

- 2 体起動時、`Target` 指定 response が該当 ghost のみに届く。
- `__SYSTEM_ALL_GHOST__` は全 ghost に届く。
- `raiseplugin` response は target 未指定なら呼び出し元 ghost に戻る。

## Phase 3: Event/Script response semantics の厳密化

**目的:** `Event` が反応しない場合だけ default `Script` を実行する仕様を安定化する。

対象:

- `Ourin/PluginEvent/OurinPluginEventBridge.swift`
- `Ourin/SHIORIEvents/EventBridge.swift`
- `Ourin/SHIORIEvents/EventID.swift`
- `Ourin/Ghost/GhostManager.swift`
- `Ourin/SakuraScriptEngine.swift`

作業:

1. plugin response 由来 `Event` は `EventOption: notify` なしなら GET として SHIORI に送る。
2. GET response script が空なら plugin response `Script` を fallback として実行する。
3. `EventOption: notify` の場合は response script を見ず、plugin response `Script` fallback も実行しない。
4. `ScriptOption: nobreak` を「現在のトーク後に enqueue」として実装する。
5. `ScriptOption: notranslate` を SakuraScript 実行 context に伝播する。
6. `OnOtherGhostTalk` の reasons に `plugin-script` / `plugin-event` / `notranslate` を付与できるようにする。

受け入れ条件:

- `Event + Script` response で ghost が GET 応答した場合、default Script は再生されない。
- ghost が空応答の場合だけ default Script が再生される。
- `nobreak` は再生中トークを中断しない。
- `notranslate` は translate pipeline を通らない。

## Phase 4: UKADOC PLUGIN Event 全送信経路

**目的:** イベント一覧の全 ID を runtime event source と接続する。

対象:

- `Ourin/PluginEvent/PluginEventDispatcher.swift`
- `Ourin/OurinApp.swift`
- `Ourin/Ghost/GhostManager+System.swift`
- `Ourin/Ghost/GhostManager+Balloon.swift`
- `Ourin/NarInstall/*`
- `Ourin/HeadlineHost/*`
- `Ourin/Property/*`

イベント別作業:

1. `version`
   - 現状維持。ただし charset byte 実装後に再検証する。
2. `installedplugin`
   - 起動時、plugin reload 時、install/uninstall 時に送る。
3. `installedghostname`
   - 起動時、ghost install/uninstall 時に送る。
   - `Reference0`: ghost names。
   - `Reference1`: sakura names。
   - `Reference2`: kero names。
4. `installedballoonname`
   - 起動時、balloon install/uninstall 時に送る。
5. `ghostpathlist`
   - 起動時、ghost path 設定変更時に送る。
6. `balloonpathlist`
   - 起動時、balloon path 設定変更時に送る。
7. `headlinepathlist`
   - 起動時、headline path 設定変更時に送る。
8. `pluginpathlist`
   - 起動時、plugin reload/install/uninstall 時に送る。
9. `OnSecondChange`
   - `secondchangeinterval` を plugin ごとに尊重する。現在の最小 interval 一括 timer ではなく、plugin 別 timer または tick filter にする。
10. `OnOtherGhostTalk`
    - ghost 発話直前/直後に接続する。
    - `otherghosttalk` の `false/0/true/1/after/before` を尊重する。
11. `OnGhostBoot`
    - ghost boot 完了時に送る。window 未構築なら `0`。
12. `OnGhostExit`
    - ghost exit 時に NOTIFY で送る。
13. `OnGhostInfoUpdate`
    - ghost config/shell/info update 時に NOTIFY で送る。
14. `OnMenuExec`
    - plugin menu 実行時に GET で送る。
15. `OnInstallComplete`
    - NAR / ghost / shell / balloon / plugin / headline install 完了時に送る。
16. `OnChoiceSelect(Ex)` / `OnAnchorSelect(Ex)` / arbitrary choice event
    - plugin response 由来 script/event から出た選択肢だけ、一回限り plugin へ横流しする marker を付ける。
17. `raiseplugin` / `notifyplugin` 任意名
    - 現状を維持し、Target context と charset を接続する。
18. `property.get`
    - Phase 5 で実装する。
19. `property.set`
    - Phase 5 で実装する。

受け入れ条件:

- 各イベントの Reference 順が UKADOC と一致する。
- `[NOTIFY]` イベントは response script を無視する。
- `OnSecondChange` は plugin ごとの interval を守る。
- `OnOtherGhostTalk` は `before` / `after` を区別する。

## Phase 5: plugin 拡張 property.get / property.set

**目的:** `pluginlist(...).ext` 由来の拡張 property を plugin request へ委譲する。

対象:

- `Ourin/Property/PluginPropertyProvider.swift`
- `Ourin/Property/PropertyManager.swift`
- `Ourin/PluginHost/PluginRegistry.swift`
- `Ourin/PluginEvent/PluginEventDispatcher.swift`
- `OurinTests/PropertySystemTests.swift`

設計:

- `pluginlist(name).ext.foo` または `pluginlist.index(n).ext.foo` を拡張 property として扱う。
- get:
  - target plugin へ `GET PLUGIN/2.0M`
  - `ID: property.get`
  - `Reference0: foo`
  - `Value` または `Script` ではなく、仕様通り property value として response value を採用する。
- set:
  - target plugin へ `GET` または `NOTIFY` ではなく、仕様に合わせ `GET` 相当の request-response とする。
  - `ID: property.set`
  - `Reference0: foo`
  - `Reference1: value`
  - status `204` または `200` を成功扱い。

受け入れ条件:

- `pluginlist.index(0).ext.somekey` が plugin の `property.get` response を返す。
- `PropertyManager.set("pluginlist.index(0).ext.somekey", value: "x")` が `property.set` を呼ぶ。
- 404/500 response は property get nil / set false になる。

## Phase 6: PLUGIN/1.0 挙動互換

**目的:** Windows DLL バイナリ互換ではなく、旧 plugin 配布物・旧 metadata・旧 menu 挙動を Ourin 上で扱いやすくする。

対象:

- `Ourin/PluginHost/PluginRegistry.swift`
- `Ourin/PluginHost/PluginProtocol.swift`
- `Ourin/PluginEvent/PluginEventDispatcher.swift`
- `Ourin/OwnerDrawMenu/*`
- `OurinTests/LegacyPluginRegistryTests.swift`

作業:

1. legacy metadata-only plugin directory を bridge 対象として扱う条件を整理する。
2. `descript.txt` の旧 key alias を正規化する。
3. native `.plugin` がない Windows DLL plugin は「ロード不可だが metadata visible」とし、menu 実行時には明示エラーまたは無効表示にする。
4. PLUGIN/1.0 由来の menu / author / readme / charset key を `PluginMeta` に保持する。
5. macOS native へ移植済み package が同一 ID で存在する場合、native を優先し legacy は重複登録しない。

受け入れ条件:

- legacy plugin directory は Ourin UI 上で識別できる。
- native replacement がある場合は二重ロードされない。
- 旧 descript の charset/name/id/filename が metadata として読める。

## Phase 7: Menu / UI / DevTools bridge

**目的:** plugin bridge の状態と発火を UI から検証できるようにする。

対象:

- `Ourin/ContentView.swift`
- `Ourin/DevTools/*`
- `Ourin/OwnerDrawMenu/*`
- `Ourin/PluginHost/PluginRegistry.swift`

作業:

1. Plugin DevTools に negotiated charset、package path、executable path、legacy/native 状態を表示する。
2. 任意 plugin に `GET` / `NOTIFY` request を送れる test console を追加または強化する。
3. `OnMenuExec` の実 menu からの起動を dispatcher に接続する。
4. `message.*.txt` を plugin menu 表示文言へ優先適用する。

受け入れ条件:

- DevTools から `version` / arbitrary event / property.get を手動検証できる。
- plugin menu 文言が `message.japanese.txt` / `message.english.txt` で切り替わる。

## Phase 8: Test plugin fixtures

**目的:** 実 plugin 互換を unit test と integration test で固定する。

対象:

- `OurinTests/Fixtures/plugin/*`
- 新規 fixture plugin source
- `OurinTests/PluginBridgeIntegrationTests.swift`

fixture:

1. UTF-8 echo plugin。
2. Shift_JIS echo plugin。
3. `Event + Script fallback` plugin。
4. `Target` plugin。
5. `property.get/set` plugin。
6. legacy metadata-only plugin。

受け入れ条件:

- CI または local `xcodebuild test` で fixture plugin をロードできる。
- byte charset、Target、fallback、property を実 plugin response で検証する。

## Phase 9: Regression test matrix

**対象テスト**

- `OurinPluginEventBridgeTests`
- `LegacyPluginRegistryTests`
- `PropertySystemTests`
- `SakuraScriptEngineTests`
- `SSTPDispatcherTests`
- 新規 `PluginEncodingTests`
- 新規 `PluginTargetRoutingTests`
- 新規 `PluginPropertyBridgeTests`
- 新規 `PluginEventDispatchMatrixTests`

検証コマンド:

```bash
xcodebuild -project Ourin.xcodeproj -scheme Ourin test
```

追加で、対象変更中は以下を個別実行する。

```bash
xcodebuild -project Ourin.xcodeproj -scheme Ourin -only-testing:OurinTests/OurinPluginEventBridgeTests test
xcodebuild -project Ourin.xcodeproj -scheme Ourin -only-testing:OurinTests/PropertySystemTests test
xcodebuild -project Ourin.xcodeproj -scheme Ourin -only-testing:OurinTests/LegacyPluginRegistryTests test
```

## 実装順序

推奨順:

1. Phase 0: docs/status 棚卸し。
2. Phase 1: charset byte 実装。
3. Phase 2: Target routing。
4. Phase 3: Event/Script semantics。
5. Phase 4: event wiring。
6. Phase 5: property.get/set。
7. Phase 6: PLUGIN/1.0 挙動互換。
8. Phase 7: UI/DevTools。
9. Phase 8/9: fixtures と test matrix 拡充。

理由:

- charset と Target は bridge 全体の土台で、後続イベントすべてに影響する。
- Event/Script semantics を先に固めると、OnMenuExec・raiseplugin・choice hook の挙動が安定する。
- property は独立度が高いが、target plugin resolution が必要なため Phase 2 後がよい。

## リスクと対策

| リスク | 影響 | 対策 |
| --- | --- | --- |
| Shift_JIS plugin response の decode 失敗 | 日本語 plugin が壊れる | byte fixture と CP932 fallback を追加 |
| Target routing で別 ghost に script が流れる | ユーザー体験・互換性に直撃 | multi-ghost routing tests を追加 |
| `nobreak` 実装で再生 queue が破綻 | トーク再生 regressions | SakuraScript playback tests を追加 |
| `OnOtherGhostTalk` が再帰的に発火 | plugin-event loop | reason flag と再入抑止 token を導入 |
| property.set が副作用を持つ | 予期せぬ plugin 状態変更 | 明示 target plugin のみに送る |
| legacy plugin を誤ロード | クラッシュ/無効 bundle | native bundle 有無でロード可否を分離 |

## 最小マイルストーン

### M1: bridge core 完成

- charset byte 実装。
- Target routing。
- Event/Script fallback 厳密化。
- `OurinPluginEventBridgeTests` / `PluginEncodingTests` / `PluginTargetRoutingTests` 成功。

### M2: event matrix 完成

- UKADOC PLUGIN Event 全 ID を runtime source に接続。
- `OnSecondChange` plugin 別 interval。
- `OnOtherGhostTalk` before/after。
- `PluginEventDispatchMatrixTests` 成功。

### M3: property と legacy 互換

- `property.get/set` plugin 委譲。
- PLUGIN/1.0 metadata-only 互換。
- native replacement 優先と重複抑止。

### M4: UI と運用検証

- DevTools で request/response を確認可能。
- plugin menu 文言に `message.*.txt` を反映。
- full `xcodebuild ... test` 成功。

## 完了後に更新する docs

- `docs/SPEC_PLUGIN_2.0M_ja-jp.md`
- `docs/SPEC_PLUGIN_2.0M_en-us.md`
- `docs/PLUGIN_EVENT_2.0M_SPEC_ja-jp.md`
- `docs/PLUGIN_EVENT_2.0M_SPEC_en-us.md`
- `docs/PropertySystem_ja-jp.md`
- `docs/PropertySystem_en-us.md`
- `docs/SUPPORTED_SAKURA_SCRIPT.md`

## チェックリスト

- [x] Charset negotiated byte encode/decode
- [x] Target resolver
- [x] caller ghost context for `raiseplugin`
- [x] `__SYSTEM_ALL_GHOST__` multi-ghost delivery
- [x] `Event` GET fallback semantics
- [x] `EventOption: notify`
- [x] `ScriptOption: nobreak`
- [x] `ScriptOption: notranslate`
- [x] plugin-specific `secondchangeinterval`
- [x] `otherghosttalk` before/after
- [x] `installedghostname`
- [x] `installedballoonname`
- [x] `ghostpathlist`
- [x] `balloonpathlist`
- [x] `headlinepathlist`
- [x] `OnGhostBoot`
- [x] `OnGhostExit`
- [x] `OnGhostInfoUpdate`
- [x] `OnMenuExec`
- [x] `OnInstallComplete`
- [x] choice/anchor one-shot plugin-origin hook
- [x] `property.get`
- [x] `property.set`
- [x] PLUGIN/1.0 metadata-only compatibility
- [x] DevTools request console
- [x] fixture/plugin bridge regression suite
