import Foundation

// SHIORI イベントパイプラインへのブリッジ実装。
// docs/OURIN_SHIORI_EVENTS_3.0M_SPEC.md に沿ったイベント名を使用する。
//
// 責務分離後の構成:
//   - BridgeToSHIORI（本ファイル）: public static API の薄いファサード。呼び出し元互換を保つ。
//   - ShioriBridgeContext: 可変状態とルーティングを保持する注入可能なインスタンス（境界5）。
//   - NativeShioriSource / BundleNativeShioriSource: ネイティブ SHIORI バンドル境界（境界1）。
//   - ShioriGhostResolver / ClosureShioriGhostResolver: 稼働中ゴースト境界（境界2）。
//   - ResourceTestStore: テスト用 Resource マップ境界（境界3）。
//   - ShioriBridgeWireCodec: SHIORI wire 変換の純関数群（境界4）。
//
// 実運用の全アクセスは ShioriBridgeContext.shared へ集約され、単一ロックで保護される。
// テストは ShioriBridgeContext を直接構築・注入するか、従来どおり public static API を使う。

/// SHIORI/3.0M 互換イベントへ橋渡しするブリッジ（public static facade）。
public enum BridgeToSHIORI {
    /// 稼働中ゴーストからの SHIORI 応答（構造化）。
    /// 文字列ワイヤへ一度直列化して再パースすると、Value に含まれる CRLF が
    /// 行注入・スクリプト切断を起こすため、ブリッジ内部では構造化したまま受け渡す。
    public struct BridgeShioriResponse {
        public let status: Int
        /// 応答ヘッダ（ReferenceN / Surface / Status / ValueNotify 等。Value は別途 `value` で保持）。
        public let headers: [String: String]
        /// 応答の値（スクリプト）。改行を含み得る。
        public let value: String?

        public init(status: Int, headers: [String: String], value: String?) {
            self.status = status
            self.headers = headers
            self.value = value
        }
    }

    /// 稼働中のゴースト（YAYA 等）へ SHIORI 要求を橋渡しするリゾルバ。
    /// ネイティブ SHIORI バンドルが未設定のとき、`handle` / `handleResponse` はこのリゾルバを通じて
    /// 実際にロードされたゴーストへ要求を送り、その応答を返す。アプリ起動時に AppDelegate が設定する。
    /// - 引数: (method, event, references, headers)
    /// - 戻り値: 構造化された SHIORI 応答。宛先ゴーストが無い／応答できない場合は nil。
    public static var liveGhostResolver: ((String, String, [String], [String: String]) -> BridgeShioriResponse?)? {
        get { ShioriBridgeContext.shared.liveGhostResolver }
        set { ShioriBridgeContext.shared.liveGhostResolver = newValue }
    }

    /// テスト用に返値を登録する
    /// - Parameters:
    ///   - key: Resource 名
    ///   - value: 応答として返す文字列
    public static func setResource(_ key: String, value: String) {
        ShioriBridgeContext.shared.setResource(key, value: value)
    }

    /// テスト用登録値をすべて消去し、環境変数ベースのホスト設定へ戻す
    public static func reset() {
        ShioriBridgeContext.shared.reset()
    }

    /// 明示的に SHIORI バンドルを設定する
    /// - Parameter bundlePath: SHIORI バンドルのパス。nil の場合はホストを無効化する
    /// - Returns: 設定に成功した場合 true
    @discardableResult
    public static func configure(bundlePath: String?) -> Bool {
        ShioriBridgeContext.shared.configure(bundlePath: bundlePath)
    }

    /// SHIORI 互換イベントを処理し、応答の「値」（Value / スクリプト）を返す。
    /// `GhostManager` / `ResourceBridge` / `WebHandler` など、応答を直接スクリプト値として使う呼び出し向け。
    /// - Parameters:
    ///   - event: イベント名
    ///   - references: 参照引数
    ///   - headers: 追加ヘッダー（例: SecurityLevel）
    ///   - method: SHIORI メソッド（既定 "GET"。NOTIFY イベントは "NOTIFY" を渡す）
    /// - Returns: 登録済み Resource 値、または応答の Value（無ければ空文字列）
    public static func handle(event: String, references: [String], headers: [String: String] = [:], method: String = "GET") -> String {
        ShioriBridgeContext.shared.handle(event: event, references: references, headers: headers, method: method)
    }

    /// SSTP ディスパッチャ向け: 完全な SHIORI/3.0 ワイヤ応答文字列を返す。
    /// `SSTPDispatcher.mapShioriResponse` が ReferenceN / Value / ValueNotify / Status / Surface 等を
    /// 保持できるよう、値だけでなく応答ヘッダを含む応答全体を返す。
    public static func handleResponse(event: String, references: [String], headers: [String: String] = [:], method: String = "GET") -> String {
        ShioriBridgeContext.shared.handleResponse(event: event, references: references, headers: headers, method: method)
    }
}
