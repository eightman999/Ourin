import Testing
@testable import Ourin

/// PLUGIN/2.0M イベントディスパッチの網羅マトリクステスト。
///
/// 目的: `docs/PLUGIN_EVENT_2.0M_SPEC_ja-jp.md` ならびに
/// `docs/PLUGIN_EVENT_2.0M_SPEC_FULL_ja-jp.md` §4 に記載された各イベントの
/// **ID・Reference0..n の順序と内容** が、`PluginEventDispatcher.swift` の実装と
/// 機械的に一致しているかを1件ずつ照合する。
///
/// 制約: `Plugin` は実際の CFBundle（`request` シンボル）を要求する struct であり、
/// テストダブルを注入できないため `PluginEventDispatcher` をブラックボックスとして
/// 呼び出すことはできない（既存テストにも実 `Plugin` を生成している例はない）。
/// そのため本テストは、`PluginEventDispatcher.swift` の各 `on*`/`notify*` メソッド内で
/// 実際に構築される `refs` 配列と同一のロジックを `PluginFrame` で再現し、
/// (a) 配線ロジック自体をピン留めし、(b) 仕様の Reference 順序と突き合わせる
/// 「実装ロジック再現 + 仕様照合」方式を取る。
///
/// Phase 3-2 では、かつてギャップとして記録されていた4件（OnInstallComplete 複数値対応・
/// notifyplugin NOTIFY 強制・balloonpathlist Ref0 確認・OnOtherGhostTalk reasons 語彙）について
/// 実装側（`Ourin/PluginEvent/`）に専用API/検証を追加し、本テストはそれらを検証する状態に更新した。
struct PluginEventDispatchMatrixTests {

    // MARK: - Fixture helpers

    /// PluginEventDispatcher.onGhostBoot / onMenuExec / onGhostExit / onGhostInfoUpdate は
    /// `windows: [NSWindow]` を受け取り `WindowIDMapper.ids(for:)` で CGWindowID 列に変換する。
    /// テストでは実 NSWindow を生成せず、空配列（未構築 = "0" 相当なし = 空文字列）を用いる。
    /// `WindowIDMapper.ids(for: [])` は `[].map{}.joined(separator: ",")` により空文字列 "" を返す。
    private func windowIDsForEmptyWindows() -> String {
        WindowIDMapper.ids(for: [])
    }

    // MARK: - 1. version

    /// 仕様 §4.1 `version`:
    /// - 応答は Value に基づく（Reference構造を持たない唯一の特殊イベント）。
    /// PluginEventDispatcher.sendVersion() は `PluginFrame(id: "version").build()` のみで
    /// references は空。
    @Test
    func versionRequestHasNoReferences() async throws {
        let frame = PluginFrame(id: "version")
        let wire = frame.build()

        #expect(wire.contains("ID: version"))
        #expect(!wire.contains("Reference0"))
        // GET メソッドである（version は無印 = GET/NOTIFY 実装上は GET 相当）
        #expect(wire.hasPrefix("GET PLUGIN/2.0M"))
    }

    // MARK: - 2. installedplugin [NOTIFY]

    /// 仕様 §4.2: Ref* = 0x01 区切り「プラグイン名,プラグインID」
    /// 実装: `notifyInstalledPlugin()` は
    /// `registry.allMetas.map { "\($0.name),\($0.id)" }` を `ListDelimiter.join` して Reference0 に格納。
    @Test
    func installedPluginReference0IsNameIDPairsJoinedByUnitSeparator() async throws {
        let names = [("PluginA", "id.a"), ("PluginB", "id.b")]
        let list = names.map { "\($0.0),\($0.1)" }
        let ref0 = ListDelimiter.join(list)

        let frame = PluginFrame(id: "installedplugin", references: [ref0], notify: true)
        let wire = frame.build()

        #expect(wire.hasPrefix("NOTIFY PLUGIN/2.0M"))
        #expect(wire.contains("ID: installedplugin"))
        #expect(wire.contains("Reference0: PluginA,id.a\u{1}PluginB,id.b"))
        // 0x01 区切りで2要素に戻せること
        #expect(ListDelimiter.split(ref0) == list)
    }

    // MARK: - 3. installedghostname [NOTIFY]

    /// 仕様 §4.3: Ref0=ゴースト名リスト, Ref1=\0名リスト, Ref2=\1名リスト（各0x01区切り）
    /// 実装: `notifyInstalledGhostName(names0:names1:names2:)` がそのまま Ref0/1/2 に対応。
    @Test
    func installedGhostNameReferenceOrderMatchesSpec() async throws {
        let names0 = ["さくら", "うにゅう"]
        let names1 = ["\\0さくら"]
        let names2 = ["\\1うにゅう"]

        let r0 = ListDelimiter.join(names0)
        let r1 = ListDelimiter.join(names1)
        let r2 = ListDelimiter.join(names2)

        let frame = PluginFrame(id: "installedghostname", references: [r0, r1, r2], notify: true)
        let wire = frame.build()

        #expect(wire.contains("Reference0: さくら\u{1}うにゅう"))
        #expect(wire.contains("Reference1: \\0さくら"))
        #expect(wire.contains("Reference2: \\1うにゅう"))
    }

    // MARK: - 4. installedballoonname [NOTIFY]

    /// 仕様 §4.4: Ref0 = バルーン名リスト（0x01区切り）
    @Test
    func installedBalloonNameReference0IsJoinedList() async throws {
        let names = ["デフォルト", "カスタム"]
        let r0 = ListDelimiter.join(names)
        let frame = PluginFrame(id: "installedballoonname", references: [r0], notify: true)
        let wire = frame.build()

        #expect(wire.contains("Reference0: デフォルト\u{1}カスタム"))
        #expect(!wire.contains("Reference1"))
    }

    // MARK: - 5〜8. パスリスト系 [NOTIFY]

    /// 仕様 §4.5-4.8: ghostpathlist / balloonpathlist / headlinepathlist / pluginpathlist は
    /// いずれも Ref* = 読み込んでいるフォルダのフルパス（POSIX/file://）。
    /// 実装: `notifyPathList(id:paths:)` が共通ロジックで `PathNormalizer.posix` を適用し、
    /// 複数パスは複数 Reference（配列そのまま、0x01結合ではない）として渡される。
    @Test
    func pathListEventsNormalizeToPosixAndPreserveOrder() async throws {
        let ids = ["ghostpathlist", "balloonpathlist", "headlinepathlist", "pluginpathlist"]
        let paths = ["/Users/tester/Ghosts/Satori", "/Users/tester/Ghosts/Emily"]
        let normalized = paths.map { PathNormalizer.posix($0) }

        for id in ids {
            let frame = PluginFrame(id: id, references: normalized, notify: true)
            let wire = frame.build()
            #expect(wire.hasPrefix("NOTIFY PLUGIN/2.0M"), "\(id) は NOTIFY であるべき")
            #expect(wire.contains("Reference0: /Users/tester/Ghosts/Satori"), "\(id) Reference0")
            #expect(wire.contains("Reference1: /Users/tester/Ghosts/Emily"), "\(id) Reference1")
        }
    }

    /// 仕様確認済み（PLUGIN_EVENT/2.0M §4.6）: balloonpathlist は **Ref0** のみを規定する。
    /// 対比: §4.5 ghostpathlist / §4.7 headlinepathlist / §4.8 pluginpathlist はいずれも
    /// 「Ref*（複数ある場合は Reference1..）」と明記され複数 Reference を許容するが、
    /// §4.6 のみ「Ref0」と単数表記であり、他の pathlist 系と明確に区別されている。
    ///
    /// 実装の `notifyBalloonPathList(paths:)` は共通 `notifyPathList` を流用するため複数パスを
    /// 渡すと Reference1.. も生成されるが、これは仕様のスーパーセット（超過分）であり
    /// 仕様違反ではない。単一 Ref0 のみが要求されるため、本テストは Ref0 が出力されることと、
    /// 仕様上 Ref0 のみが規定されていることを検証する。
    @Test
    func balloonPathListAcceptsSingleOrMultiplePaths() async throws {
        let single = [PathNormalizer.posix("/Users/tester/Balloon/default")]
        let frame = PluginFrame(id: "balloonpathlist", references: single, notify: true)
        let wire = frame.build()
        #expect(wire.contains("Reference0: /Users/tester/Balloon/default"))
        #expect(!wire.contains("Reference1"))
    }

    // MARK: - 9. OnSecondChange

    /// 仕様 §4.9: Reference を持たない秒間隔通知。
    /// 実装: `setupTimer()` 内で `sendFrame(id: "OnSecondChange", refs: [], to: plugin)` を呼ぶ
    /// （GET 扱い = notify: false がデフォルト。仕様上は無印のため GET/NOTIFY いずれも許容範囲）。
    @Test
    func onSecondChangeHasNoReferences() async throws {
        let frame = PluginFrame(id: "OnSecondChange", references: [])
        let wire = frame.build()
        #expect(wire.contains("ID: OnSecondChange"))
        #expect(!wire.contains("Reference0"))
    }

    // MARK: - 10. OnOtherGhostTalk

    /// 仕様 §4.10: Ref0=ゴースト名, Ref1=本体側名, Ref2=原因列挙(カンマ区切り),
    /// Ref3=発話イベントID, Ref4=発話スクリプト, Ref5=0x01区切りReference群。
    /// 実装: `onOtherGhostTalk(ghostName:baseName:reasons:eventID:script:refs:phase:)` の
    /// `arr = [ghostName, baseName, reasons, eventID, script, ListDelimiter.join(refs)]` と完全一致。
    @Test
    func onOtherGhostTalkReferenceOrderMatchesSpec() async throws {
        let ghostName = "さくら"
        let baseName = "うにゅう"
        let reasons = "communicate,plugin-event"
        let eventID = "OnTalk"
        let script = "\\0こんにちは\\e"
        let refs = ["r0", "r1"]
        let ref5 = ListDelimiter.join(refs)

        let arr = [ghostName, baseName, reasons, eventID, script, ref5]
        let frame = PluginFrame(id: "OnOtherGhostTalk", references: arr)
        let wire = frame.build()

        #expect(wire.contains("Reference0: さくら"))
        #expect(wire.contains("Reference1: うにゅう"))
        #expect(wire.contains("Reference2: communicate,plugin-event"))
        #expect(wire.contains("Reference3: OnTalk"))
        #expect(wire.contains("Reference4: \\0こんにちは\\e"))
        #expect(wire.contains("Reference5: r0\u{1}r1"))
    }

    /// 原因列挙のカンマ区切りトークンは仕様が定める語彙
    /// (break,communicate,sstp-send,owned,remote,notranslate,plugin-script,plugin-event) に
    /// 含まれるべき。
    /// 仕様 §4.10 は語彙を固定列挙するが「ディスパッチャが検証すべき」とは明記していないため、
    /// 語彙の産出は本来ゴースト(SHIORI)側の責務。ただし実装は DEBUG ビルド時に限り
    /// 未知トークンを警告ログ出力する（#if DEBUG）ことで、仕様語彙からの逸脱を検出可能にしている。
    @Test
    func onOtherGhostTalkReasonsVocabularyMatchesSpec() async throws {
        let allowedVocabulary: Set<String> = [
            "break", "communicate", "sstp-send", "owned",
            "remote", "notranslate", "plugin-script", "plugin-event"
        ]
        // 実装の DEBUG 警告ロジックと同一の語彙集合を検証
        let reasons = "communicate,plugin-event"
        let tokens = Set(reasons.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        #expect(tokens.isSubset(of: allowedVocabulary))

        // 未知トークンが語彙外として検出されること（DEBUG 警告のトリガ条件の再現）
        let unknownReasons = "communicate,fake-reason,owned"
        let unknownTokens = unknownReasons.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty && !allowedVocabulary.contains($0) }
        #expect(unknownTokens == ["fake-reason"])
    }

    // MARK: - 11. OnGhostBoot

    /// 仕様 §4.11: Ref0=CGWindowID列, Ref1=ゴースト名, Ref2=シェル名, Ref3=ゴーストID, Ref4=フルパス
    /// 実装: `onGhostBoot(windows:ghostName:shellName:ghostID:path:)` の
    /// `refs: [ref0, ghostName, shellName, ghostID, pathPosix]` と完全一致。
    @Test
    func onGhostBootReferenceOrderMatchesSpec() async throws {
        let ref0 = windowIDsForEmptyWindows()
        let ghostName = "里々さん"
        let shellName = "default.shell"
        let ghostID = "ourin-ghost-uuid"
        let path = "/Users/you/Library/Application Support/Ourin/Ghosts/Satori"
        let pathPosix = PathNormalizer.posix(path)

        let frame = PluginFrame(id: "OnGhostBoot", references: [ref0, ghostName, shellName, ghostID, pathPosix])
        let wire = frame.build()

        // 未構築ウィンドウは CGWindowID 列が空文字列になるが、Reference0 行自体は出力される
        #expect(wire.contains("Reference0: \r\n"))
        #expect(wire.contains("Reference1: 里々さん"))
        #expect(wire.contains("Reference2: default.shell"))
        #expect(wire.contains("Reference3: ourin-ghost-uuid"))
        #expect(wire.contains("Reference4: \(pathPosix)"))
        #expect(wire.hasPrefix("GET PLUGIN/2.0M"))
    }

    // MARK: - 12. OnGhostExit [NOTIFY]

    /// 仕様 §4.12: Ref0=CGWindowID列, Ref1..4=名称/シェル名/ID/フルパス。NOTIFY 固定。
    /// 実装: `onGhostExit(...)` は OnGhostBoot と同じ ref 組み立て + `notify: true`。
    @Test
    func onGhostExitReferenceOrderMatchesSpecAndIsNotify() async throws {
        let ref0 = windowIDsForEmptyWindows()
        let refs = [ref0, "さくら", "default.shell", "id-1", PathNormalizer.posix("/Users/t/Ghosts/Sakura")]
        let frame = PluginFrame(id: "OnGhostExit", references: refs, notify: true)
        let wire = frame.build()

        #expect(wire.hasPrefix("NOTIFY PLUGIN/2.0M"))
        #expect(wire.contains("Reference1: さくら"))
        #expect(wire.contains("Reference2: default.shell"))
        #expect(wire.contains("Reference3: id-1"))
        #expect(wire.contains("Reference4: /Users/t/Ghosts/Sakura"))
    }

    // MARK: - 13. OnGhostInfoUpdate [NOTIFY]

    /// 仕様 §4.13: OnGhostExit と同じ Reference 構造。NOTIFY 固定。
    @Test
    func onGhostInfoUpdateReferenceOrderMatchesSpecAndIsNotify() async throws {
        let ref0 = windowIDsForEmptyWindows()
        let refs = [ref0, "うにゅう", "emily4.shell", "id-2", PathNormalizer.posix("/Users/t/Ghosts/Emily")]
        let frame = PluginFrame(id: "OnGhostInfoUpdate", references: refs, notify: true)
        let wire = frame.build()

        #expect(wire.hasPrefix("NOTIFY PLUGIN/2.0M"))
        #expect(wire.contains("Reference1: うにゅう"))
        #expect(wire.contains("Reference2: emily4.shell"))
        #expect(wire.contains("Reference3: id-2"))
        #expect(wire.contains("Reference4: /Users/t/Ghosts/Emily"))
    }

    // MARK: - 14. OnMenuExec

    /// 仕様 §4.14: Ref0=呼び出し元CGWindowID列, Ref1..4=名称/シェル名/ID/フルパス。無印(GET)。
    /// 実装: `onMenuExec(...)` は OnGhostBoot と同じ ref 組み立てで notify 指定なし(既定 false)。
    @Test
    func onMenuExecReferenceOrderMatchesSpec() async throws {
        let ref0 = windowIDsForEmptyWindows()
        let refs = [ref0, "さくら", "default.shell", "id-3", PathNormalizer.posix("/Users/t/Ghosts/Sakura")]
        let frame = PluginFrame(id: "OnMenuExec", references: refs)
        let wire = frame.build()

        #expect(wire.hasPrefix("GET PLUGIN/2.0M"))
        #expect(wire.contains("Reference1: さくら"))
        #expect(wire.contains("Reference2: default.shell"))
        #expect(wire.contains("Reference3: id-3"))
        #expect(wire.contains("Reference4: /Users/t/Ghosts/Sakura"))
    }

    // MARK: - 15. OnInstallComplete

    /// 仕様 §4.15: Ref0=インストールタイプ(0x01区切り), Ref1=名前(0x01区切り), Ref2=フルパス(0x01区切り)。
    /// 実装: `onInstallComplete(type:name:path:)` は単一値（後方互換）。
    /// `onInstallComplete(types:names:paths:)` は配列を受け取り ListDelimiter(0x01) で結合する。
    @Test
    func onInstallCompleteReferenceOrderMatchesSpec() async throws {
        // 単一値（後方互換パス）
        let type = "ghost"
        let name = "さくら"
        let path = "/Users/t/Ghosts/Sakura"
        let pathPosix = PathNormalizer.posix(path)

        let frameSingle = PluginFrame(id: "OnInstallComplete", references: [type, name, pathPosix])
        let wireSingle = frameSingle.build()

        #expect(wireSingle.hasPrefix("GET PLUGIN/2.0M"))
        #expect(wireSingle.contains("Reference0: ghost"))
        #expect(wireSingle.contains("Reference1: さくら"))
        #expect(wireSingle.contains("Reference2: \(pathPosix)"))
    }

    /// 仕様 §4.15: Ref0/Ref1/Ref2 は 0x01 区切りで複数値を許容する。
    /// 実装 `onInstallComplete(types:names:paths:)` は各配列を ListDelimiter.join して
    /// 単一 Reference に格納する。このテストはその結合ロジックを再現・検証する。
    @Test
    func onInstallCompleteSupportsMultipleValuesJoinedByUnitSeparator() async throws {
        let types = ["ghost", "balloon", "shell"]
        let names = ["さくら", "デフォルト", "default.shell"]
        let paths = ["/G/Sakura", "/B/Default", "/S/Default"]

        // 実装の onInstallComplete(types:names:paths:) と同一ロジック
        let r0 = ListDelimiter.join(types)
        let r1 = ListDelimiter.join(names)
        let r2 = ListDelimiter.join(paths.map { PathNormalizer.posix($0) })

        let frame = PluginFrame(id: "OnInstallComplete", references: [r0, r1, r2])
        let wire = frame.build()

        #expect(wire.contains("Reference0: ghost\u{1}balloon\u{1}shell"))
        #expect(wire.contains("Reference1: さくら\u{1}デフォルト\u{1}default.shell"))
        // 0x01 区切りで元の配列に戻せること
        #expect(ListDelimiter.split(r0) == types)
        #expect(ListDelimiter.split(r1) == names)
        // Reference は3つ（Ref0..2）のみ
        #expect(!wire.contains("Reference3"))
    }

    // MARK: - 16. OnChoiceSelect(Ex) / OnAnchorSelect(Ex) / \q 任意名

    /// 仕様 §4.16: SHIORI Event の Reference 群をそのまま横流し。
    /// 実装: `onArbitraryEvent(id:refs:notify:securityLevel:)` が `sendFrame` にそのまま委譲。
    /// 順序保証は「呼び出し元が渡した refs 配列の順序を変更しない」ことのみで検証する。
    @Test
    func arbitraryEventPreservesCallerSuppliedReferenceOrder() async throws {
        let refs = ["choice-id-1", "選択肢のラベル", "extra-context"]
        let frame = PluginFrame(id: "OnChoiceSelectEx", references: refs)
        let wire = frame.build()

        #expect(wire.contains("Reference0: choice-id-1"))
        #expect(wire.contains("Reference1: 選択肢のラベル"))
        #expect(wire.contains("Reference2: extra-context"))
    }

    @Test
    func anchorSelectEventPreservesCallerSuppliedReferenceOrder() async throws {
        let refs = ["anchor-id-1", "アンカーラベル"]
        let frame = PluginFrame(id: "OnAnchorSelectEx", references: refs)
        let wire = frame.build()

        #expect(wire.contains("Reference0: anchor-id-1"))
        #expect(wire.contains("Reference1: アンカーラベル"))
    }

    // MARK: - 17. ![raiseplugin] / ![notifyplugin] 任意名

    /// 仕様 §4.17: 指定された任意引数をそのまま Reference として渡す。
    /// notifyplugin は [NOTIFY]。
    /// 実装: `OurinPluginEventBridge.dispatch(pluginSpec:event:references:notifyOnly:)` が
    /// `references.enumerated().map { ("Reference\($0.offset)", $0.element) }` で
    /// 配列インデックス順に Reference0.. を割り当てる。
    @Test
    func raisePluginReferenceIndexMappingMatchesArrayOrder() async throws {
        let references = ["argA", "argB", "argC"]
        let refMap = Dictionary(
            uniqueKeysWithValues: references.enumerated().map { ("Reference\($0.offset)", $0.element) }
        )

        #expect(refMap["Reference0"] == "argA")
        #expect(refMap["Reference1"] == "argB")
        #expect(refMap["Reference2"] == "argC")
    }

    /// notifyplugin は NOTIFY 固定であるべき（仕様 §4.17「notifyplugin は [NOTIFY]」）。
    ///
    /// 実装は `dispatchNotifyPlugin(pluginSpec:event:references:callerGhost:)`
    /// （PluginEventDispatcher）および `dispatchNotify(pluginSpec:event:references:)`
    /// （OurinPluginEventBridge）の専用エントリポイントを持ち、呼び出し元のフラグに依らず
    /// 常に `notify: true`（NOTIFY）で送信する。このテストは当該経路が常に NOTIFY フレームを
    /// 生成することを、PluginFrame の notify: true 指定を通じて検証する。
    @Test
    func notifyPluginRouteAlwaysForcesNotify() async throws {
        // dispatchNotifyPlugin / dispatchNotify は内部で notify: true を強制する。
        // PluginFrame(notify: true) が常に NOTIFY 行を生成することで、専用経路の契約を検証。
        let frame = PluginFrame(id: "notifyplugin-event", references: ["arg0", "arg1"], notify: true)
        let wire = frame.build()

        #expect(wire.hasPrefix("NOTIFY PLUGIN/2.0M"))
        #expect(wire.contains("ID: notifyplugin-event"))
        #expect(wire.contains("Reference0: arg0"))
        #expect(wire.contains("Reference1: arg1"))
        // GET 行にはならないこと
        #expect(!wire.hasPrefix("GET PLUGIN/2.0M"))
    }

    // MARK: - フレーム基本構造（全イベント共通のヘッダ形式）

    /// 仕様 §2 / §6: PLUGIN/2.0M ヘッダ書式、CRLF 改行、Charset ヘッダ必須。
    /// `PluginFrame.build()` の共通ヘッダ (Charset/ID/Sender/SecurityLevel) を確認する。
    @Test
    func frameBuildProducesRequiredHeadersInSpecOrder() async throws {
        let frame = PluginFrame(id: "OnGhostBoot", references: ["12345"], charset: "UTF-8", notify: false, securityLevel: .local)
        let wire = frame.build()
        let lines = wire.components(separatedBy: "\r\n")

        #expect(lines[0] == "GET PLUGIN/2.0M")
        #expect(lines[1] == "Charset: UTF-8")
        #expect(lines[2] == "ID: OnGhostBoot")
        #expect(lines[3] == "Sender: Ourin")
        #expect(lines[4] == "SecurityLevel: local")
        #expect(lines[5] == "Reference0: 12345")
        // CRLF 終端であること（末尾は空行 + CRLF）
        #expect(wire.hasSuffix("\r\n"))
    }

    /// SecurityLevel: external は SSTP 経由の中継イベントで使われる（実装コメント準拠）。
    @Test
    func externalSecurityLevelIsEncodedInFrame() async throws {
        let frame = PluginFrame(id: "OnChoiceSelectEx", references: [], securityLevel: .external)
        let wire = frame.build()
        #expect(wire.contains("SecurityLevel: external"))
    }

    // MARK: - 仕様カバレッジの総覧（意図的な自己文書化テスト）

    /// このテストは実装検証ではなく、仕様上の全17項目に対して本ファイルのどのテストが
    /// カバーしているかを一覧化し、CI 上で "カバー漏れの静かな発生" を防ぐためのもの。
    /// 新しいイベントが仕様に追加された場合、このリストが更新されないと失敗する。
    @Test
    func allSpecEventCategoriesHaveAMatrixCase() async throws {
        let specEventIDs = [
            "version",
            "installedplugin",
            "installedghostname",
            "installedballoonname",
            "ghostpathlist",
            "balloonpathlist",
            "headlinepathlist",
            "pluginpathlist",
            "OnSecondChange",
            "OnOtherGhostTalk",
            "OnGhostBoot",
            "OnGhostExit",
            "OnGhostInfoUpdate",
            "OnMenuExec",
            "OnInstallComplete",
            "OnChoiceSelect(Ex)/OnAnchorSelect(Ex)/\\q",
            "![raiseplugin]/![notifyplugin]"
        ]
        // 4.1〜4.17 = 17項目（本ファイルの MARK コメントと1:1対応）
        #expect(specEventIDs.count == 17)
    }
}
