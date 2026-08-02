import Foundation

/// SSTPDispatcher が SHIORI 応答／EXECUTE 拡張コマンドから生成する UI 効果の値型。
/// AppKit / UIKit に依存しない（＝SSTPDispatcher.swift から import AppKit を除去するための境界）。
/// 生成（解析・検証・ルーティング）は SSTPDispatcher、適用は SstpDispatcherHost の実装が担う。
struct SstpUIEffect: Sendable, Equatable {
    /// 効果の種別。associated value は検証済みの値のみを保持する。
    enum Kind: Sendable, Equatable {
        /// SHIORI 応答ヘッダ Surface。id は Int 変換に成功した値のみ。
        case updateSurface(id: Int)
        /// SHIORI 応答ヘッダ Balloon。空白以外の名前のみ。
        case switchBalloon(name: String)
        /// SHIORI 応答ヘッダ BalloonOffset。"x,y" を 2 要素以上でパースした結果。
        case balloonOffset(x: String, y: String, isRelative: Bool)
        /// SHIORI 応答ヘッダ Icon / EXECUTE settrayicon(settasktrayicon)。
        /// "filename,text" を最初のカンマで分割した結果。
        case setTaskTrayIcon(filename: String, text: String)
        /// EXECUTE dumpsurface。
        case dumpSurface(params: [String])
        /// EXECUTE moveasync。引数検証済みの値のみ。
        case moveWindowAsync(scope: Int, x: Int, y: Int, time: Int, method: String, ignoreSticky: Bool)
        /// EXECUTE settrayballoon。
        case setTrayBalloon(options: [String])
    }

    /// 効果の種別。
    let kind: Kind
    /// 宛先ゴースト解決用のリクエストヘッダ（ReceiverGhostName 等）。
    /// live adapter は AppDelegate.ghostManagerForShioriRequest(headers:) で解決する。
    let requestHeaders: [String: String]

    init(_ kind: Kind, requestHeaders: [String: String]) {
        self.kind = kind
        self.requestHeaders = requestHeaders
    }
}
