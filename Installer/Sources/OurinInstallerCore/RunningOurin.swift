import AppKit

/// 起動中の Ourin を見つけて終了してもらう。
///
/// 強制終了はしない。ゴーストの終了トーク（OnClose）とデータ保存を待つため、
/// 通常の終了要求を出してから一定時間待つ。
public enum RunningOurin {
    public static func instances() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: OurinPreferences.bundleIdentifier)
    }

    public static var isRunning: Bool { !instances().isEmpty }

    /// 終了を要求し、全インスタンスが終わるまで最大 `timeout` 秒待つ。終わったら true。
    public static func requestQuit(timeout: TimeInterval = 60) async -> Bool {
        let apps = instances()
        guard !apps.isEmpty else { return true }
        apps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if apps.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return apps.allSatisfy(\.isTerminated)
    }
}
