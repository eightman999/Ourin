import Foundation

/// SSTPDispatcher が依存するアプリ環境への委譲先。
///
/// SSTPDispatcher はプロトコル解析・ルーティングと「型付き効果（SstpUIEffect）の生成」までを担い、
/// NSApp / AppDelegate / GhostManager のような具体 UI API を直接参照しない。
/// UI 副作用の適用と GetFMO 用データの読み取りはこの protocol の実装（通常は LiveSstpDispatcherHost）へ委譲する。
///
/// - note: default 実装（LiveSstpDispatcherHost）は不変・ステートレスであり、新たな可変 global singleton ではない。
///   テストでは spy/fake を注入し、AppDelegate 無しに効果生成・順序・値を検証できる。
protocol SstpDispatcherHost: Sendable {
    /// UI 効果を適用する。実装は適切なスレッド（通常はメイン）へディスパッチしてよい。
    /// 不正な値は SSTPDispatcher 側で弾かれるため、ここへは検証済みの効果のみ届く。
    func apply(_ effect: SstpUIEffect)

    /// GetFMO 用に現在起動中のゴーストレコードを収集する（ローカルセキュリティ時のみ呼ばれる）。
    func collectFmoRecords() -> [FmoGhostRecord]
}
