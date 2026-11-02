# 20 用語集

<details>
<summary>関連ソースファイル</summary>

このページは次のファイルをもとに作成した。

- [README.md](../../README.md)
- [AGENTS.md](../../AGENTS.md)
- [Ourin/USL/ShioriRuntime.swift](../../Ourin/USL/ShioriRuntime.swift)
- [Ourin/USL/BundledShioriEngine.swift](../../Ourin/USL/BundledShioriEngine.swift)
- [Ourin/USL/ShioriRuntimeFactory.swift](../../Ourin/USL/ShioriRuntimeFactory.swift)
- [Ourin/SSTP/SSTPParser.swift](../../Ourin/SSTP/SSTPParser.swift)
- [Ourin/SSTP/SSTPDispatcher.swift](../../Ourin/SSTP/SSTPDispatcher.swift)
- [Ourin/SHIORIEvents/EventBridge.swift](../../Ourin/SHIORIEvents/EventBridge.swift)
- [Ourin/FMO/FmoManager.swift](../../Ourin/FMO/FmoManager.swift)
- [Ourin/ExternalServer/OurinExternalServer.swift](../../Ourin/ExternalServer/OurinExternalServer.swift)
- [Ourin/ExternalServer/XpcDirectServer.swift](../../Ourin/ExternalServer/XpcDirectServer.swift)
- [Ourin/Web/WebHandler.swift](../../Ourin/Web/WebHandler.swift)
- [Ourin/NarInstall/Paths.swift](../../Ourin/NarInstall/Paths.swift)

</details>

この wiki と Ourin のソース・文書に出てくる用語を、伺か一般の用語と Ourin 固有の名前に分けてまとめる。伺か一般の用語の正式な定義は UKADOC（SSP のマニュアル）にある。詳しい説明は「ページ」列のリンク先を参照する。

## 伺かの基本用語

| 用語 | 意味 | ページ |
|---|---|---|
| 伺か（ukagaka） | デスクトップに常駐するキャラクター（ゴースト）と、それを動かす仕組みの総称 | [1](./01-overview.md) |
| ベースウェア | ゴーストを読み込んで表示・実行する本体アプリ。Windows では SSP、macOS では Ourin | [1](./01-overview.md) |
| SSP | 現行の代表的な Windows 用ベースウェア。Ourin の互換性の基準 | [1](./01-overview.md) |
| UKADOC | SSP のマニュアル。SHIORI/3.0・さくらスクリプト・プロパティシステムなどの仕様の一次参照 | [7](./07-sakura-script.md)、[8](./08-shiori-runtime.md) |
| ゴースト | キャラクターの辞書（会話）・シェル・既定バルーンをまとめた単位。`ghost/master/descript.txt` で定義する | [4](./04-ghost-manager.md) |
| シェル / サーフェス | シェルはキャラクターの見た目一式、サーフェスはその 1 枚の画像（`surfaceNNNN.png` と `surfaces.txt` の定義） | [5](./05-surface-shell-animation.md) |
| SERIKO / MAYUNA | サーフェスのアニメーション（SERIKO）と着せ替え（MAYUNA）の定義体系 | [5](./05-surface-shell-animation.md) |
| バルーン | 台詞を表示する吹き出し。独立したパッケージとして差し替えられる | [6](./06-balloon.md) |
| スコープ（`\0`・`\1` …） | 複数のキャラクター（本体・相方 …）のどれが話すかの切り替え | [4](./04-ghost-manager.md)、[7](./07-sakura-script.md) |
| さくらスクリプト | ゴーストの台詞と動作を記述するスクリプト。`\h`・`\s[0]`・`\w9`・`\![...]` などのタグで表情・待機・コマンドを表す | [7](./07-sakura-script.md) |
| SHIORI（栞） | ゴーストの会話エンジン。ベースウェアからの要求（イベント）に応答スクリプトを返す。プロトコルは SHIORI/3.0（2.x 互換あり） | [8](./08-shiori-runtime.md) |
| イベント / Reference | SHIORI に送る通知（`OnBoot`・`OnMouseClick`・`OnSecondChange` など）と、その引数（`Reference0`…） | [9](./09-shiori-events.md) |
| SSTP | 外部のアプリやゴーストからベースウェアへ要求を送るプロトコル（`SEND`・`NOTIFY`・`EXECUTE` など） | [10](./10-sstp.md) |
| SAORI | SHIORI から呼び出す拡張モジュール（Windows では DLL）。SAORI/1.0 | [13](./13-saori.md) |
| PLUGIN | ベースウェアに常駐し、イベントを受けてスクリプトを返す拡張。PLUGIN/2.0 | [12](./12-plugin.md) |
| HEADLINE | ヘッドライン（ニュースなど）を取得して読み上げる拡張。HEADLINE/2.0 | [16](./16-auxiliary-features.md) |
| FMO | ベースウェア間で起動中のゴースト情報を共有する仕組み。Windows ではファイルマッピングオブジェクト、Ourin では POSIX 共有メモリ | [11](./11-fmo.md) |
| NAR | ゴースト・シェル・バルーン・プラグインなどの配布用 zip。`install.txt` で種類と展開先を指定する | [15](./15-nar-install.md) |
| `descript.txt` / `install.txt` | 各パッケージの属性ファイル（名前・作者・SHIORI の指定など）と、NAR のインストール指示ファイル | [4](./04-ghost-manager.md)、[15](./15-nar-install.md) |
| プロパティシステム | `%property[baseware.name]` のように、ベースウェアやゴーストの情報を名前で取得・設定する仕組み | [14](./14-property-resource.md) |

**出典:** [README.md:1-36](../../README.md#L1-L36)、[AGENTS.md:1-11](../../AGENTS.md#L1-L11)、[AGENTS.md:20-26](../../AGENTS.md#L20-L26)

## 栞エンジン（SHIORI の実装）

| 用語 | 意味 | Ourin での接続 | ページ |
|---|---|---|---|
| YAYA（AYA 系） | C 風の辞書言語の SHIORI | `YayaAdapter` → helper `yaya_core`（C++、JSON line IPC） | [8.1](./08a-yaya.md) |
| 里々（SATORI） | 日本語の会話を書きやすい辞書形式の SHIORI | `SatoriAdapter` → helper `satori_core`（固定版 SATORI） | [8.2](./08b-satori.md) |
| 華和梨（KAWARI）/ 篝（KAGARI） | KIS 言語の SHIORI とその後継 | 同梱ネイティブエンジン（`BundledShioriEngine.kawari` / `.kagari`） | [8.3](./08c-external-engines.md) |
| 追加 7 栞 | 灯（akari）・ese-shiori・偽栞（niseshiori）・忍（shino）・翡翠（hisui）・結奈（yuhna）・美坂（misaka） | 同梱ネイティブエンジン（`lib<名前>.dylib`）。開発版のみ | [8.3](./08c-external-engines.md) |
| Aosora | ネイティブ SHIORI の一つ | 同梱ネイティブエンジン（`libaosora.dylib`） | [8.3](./08c-external-engines.md) |
| SHIOLINK | 外部プロセスの SHIORI と標準入出力で通信するプロトコル（MiyoJS など） | `ShiolinkAdapter` | [8.3](./08c-external-engines.md) |
| 里珠（Rishu） | Perl で書かれた SHIORI | `RishuProxyAdapter`（別途 Perl が必要） | [8.3](./08c-external-engines.md) |
| MAKOTO | 応答スクリプトを翻訳モジュールに通して変換する仕組み。Ourin は `TRANSLATE Sentence MAKOTO/2.0` 要求を組み立てて送る | `MakotoTranslator`（`MakotoWireCodec`） | [8](./08-shiori-runtime.md) |
| ネイティブ SHIORI | macOS 用にビルドされた SHIORI の dylib / bundle。`load` / `request` / `unload` の C ABI で呼ぶ | `ShioriLoader`・`NativeShioriModule` | [8](./08-shiori-runtime.md) |

**出典:** [Ourin/USL/ShioriRuntime.swift:106](../../Ourin/USL/ShioriRuntime.swift#L106)、[Ourin/USL/BundledShioriEngine.swift:4-31](../../Ourin/USL/BundledShioriEngine.swift#L4-L31)、[Ourin/USL/ShioriRuntimeFactory.swift:4](../../Ourin/USL/ShioriRuntimeFactory.swift#L4)、[README.md:7-12](../../README.md#L7-L12)

## Ourin 固有の名前

| 名前 | 意味 | 定義 | ページ |
|---|---|---|---|
| `GhostManager` | 1 体のゴーストの表示・スクリプト実行・SHIORI 呼び出しをまとめる中核クラス。`GhostManager+*.swift` に分割 | `Ourin/Ghost/GhostManager.swift` | [4](./04-ghost-manager.md) |
| `GhostShioriRuntime` | 各栞エンジンのアダプタが実装する SHIORI ランタイムのプロトコル | `Ourin/USL/ShioriRuntime.swift` | [8](./08-shiori-runtime.md) |
| USL | Universal-SHIORI Loader。SHIORI ランタイム層のディレクトリ名（`Ourin/USL/`）で、仕様書は `docs/OURIN_USL_1.0M_SPEC_ja-jp.md` | `Ourin/USL/` | [8](./08-shiori-runtime.md) |
| `ShioriRuntimeFactory` | ゴーストの設定から使うランタイムを選ぶ | `Ourin/USL/ShioriRuntimeFactory.swift` | [8](./08-shiori-runtime.md) |
| `BundledShioriEngine` | アプリに同梱したネイティブエンジンの一覧（kawari・kagari・akari・ese-shiori・niseshiori・shino・hisui・yuhna・misaka・aosora） | `Ourin/USL/BundledShioriEngine.swift` | [8](./08-shiori-runtime.md)、[8.3](./08c-external-engines.md) |
| `EventBridge` | OS の状態変化などを SHIORI イベントに変換して送る | `Ourin/SHIORIEvents/EventBridge.swift` | [9](./09-shiori-events.md) |
| `SSTPParser` / `SSTPDispatcher` | SSTP の解析と配送。すべての外部 SSTP がこの単一 stack を通る（旧 `SstpRouter` は復活させない） | `Ourin/SSTP/` | [10](./10-sstp.md) |
| `OurinExternalServer` | HTTP・生 TCP・XPC・Distributed IPC の外部受信口をまとめて起動する | `Ourin/ExternalServer/OurinExternalServer.swift` | [10.1](./10a-external-server-web.md) |
| `jp.ourin.sstp` | XPC の mach service 名。Distributed IPC の通知名は `jp.ourin.sstp.request` / `jp.ourin.sstp.response` | `XpcDirectServer.swift`・`OurinExternalServer.swift` | [10.1](./10a-external-server-web.md) |
| `x-ukagaka-link` | Web から Ourin を呼び出す URL スキーム | `Ourin/Web/WebHandler.swift` | [10.1](./10a-external-server-web.md) |
| `FmoManager` | FMO の共有メモリとセマフォを管理する | `Ourin/FMO/FmoManager.swift` | [11](./11-fmo.md) |
| `OurinPaths` | ユーザーデータの基準フォルダ（`~/Documents/Ourin`）とサブフォルダを決める | `Ourin/NarInstall/Paths.swift` | [15](./15-nar-install.md) |
| Ourin Migrator | Windows 用ゴーストの DLL / EXE を解析し、移行レポートやプラグインの雛形を作る DevTools の機能（外部の Ghidra を使う） | `Ourin/DevTools/Migrator/` | [17](./17-devtools-migrator.md) |
| `OnClaudeCode` | Claude Code の mod `ghost-narrator`（リポジトリ外）が SSTP `SEND` で送るイベント名 | README | [10.1](./10a-external-server-web.md) |
| 1.0M / 2.0M / 3.0M | Ourin の仕様書（`docs/*_SPEC_*.md`）が付ける版の表記。USL/1.0M と SHIORI Resource 3.0M の仕様書は表題で「macOS」と併記しており、M は macOS 版の意と読める（推測。`docs/AUDIT_PROMPT` も M 付きの版番号を Ourin 独自の拡張として扱う） | `docs/` | [19](./19-dev-tooling.md) |

**出典:** [Ourin/Ghost/GhostManager.swift:822](../../Ourin/Ghost/GhostManager.swift#L822)、[Ourin/SHIORIEvents/EventBridge.swift:31](../../Ourin/SHIORIEvents/EventBridge.swift#L31)、[Ourin/SSTP/SSTPParser.swift:4](../../Ourin/SSTP/SSTPParser.swift#L4)、[Ourin/SSTP/SSTPDispatcher.swift:4](../../Ourin/SSTP/SSTPDispatcher.swift#L4)、[Ourin/ExternalServer/OurinExternalServer.swift:13](../../Ourin/ExternalServer/OurinExternalServer.swift#L13)、[Ourin/ExternalServer/OurinExternalServer.swift:160-176](../../Ourin/ExternalServer/OurinExternalServer.swift#L160-L176)、[Ourin/ExternalServer/XpcDirectServer.swift:14](../../Ourin/ExternalServer/XpcDirectServer.swift#L14)、[Ourin/Web/WebHandler.swift:5](../../Ourin/Web/WebHandler.swift#L5)、[Ourin/FMO/FmoManager.swift:120](../../Ourin/FMO/FmoManager.swift#L120)、[Ourin/NarInstall/Paths.swift:4](../../Ourin/NarInstall/Paths.swift#L4)、[AGENTS.md:8](../../AGENTS.md#L8)、[README.md:207-225](../../README.md#L207-L225)、[Ourin/USL/MakotoTranslator.swift:1-20](../../Ourin/USL/MakotoTranslator.swift#L1-L20)、[docs/OURIN_USL_1.0M_SPEC_ja-jp.md:1](../../docs/OURIN_USL_1.0M_SPEC_ja-jp.md#L1)、[Ourin/USL/ShiolinkAdapter.swift:134-139](../../Ourin/USL/ShiolinkAdapter.swift#L134-L139)、[docs/PROPERTY_Resource_3.0M_SPEC_ja-jp.md:2](../../docs/PROPERTY_Resource_3.0M_SPEC_ja-jp.md#L2)、[docs/AUDIT_PROMPT_en-us.md:159](../../docs/AUDIT_PROMPT_en-us.md#L159)

## 関連ページ

- [目次](./README.md) — 全ページの一覧
- [1 概要](./01-overview.md) — 全体像
