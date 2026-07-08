import Foundation
import Testing
@testable import Ourin

/// "OurinEnableFileLogging" / "OurinLogOutputPath" に基づくファイルログ出力を検証する。
/// LogFileSink.shared（プロセス共有シングルトン）と UserDefaults.standard の同一キーを
/// 全テストが共有するため、並列実行すると enable/disable 状態が交差してフレークする。直列化必須。
@Suite(.serialized)
struct LogFileSinkTests {
    private let enableKey = "OurinEnableFileLogging"
    private let pathKey = "OurinLogOutputPath"

    @Test
    func writesToConfiguredPathWhenEnabled() throws {
        let tempPath = NSTemporaryDirectory() + "OurinLogFileSinkTests-\(UUID().uuidString).log"
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
            UserDefaults.standard.removeObject(forKey: enableKey)
            UserDefaults.standard.removeObject(forKey: pathKey)
            LogFileSink.shared.resetForTesting()
        }

        UserDefaults.standard.set(true, forKey: enableKey)
        UserDefaults.standard.set(tempPath, forKey: pathKey)
        LogFileSink.shared.resetForTesting()

        LogFileSink.shared.write(level: "INFO", message: "hello file sink")

        let contents = try String(contentsOfFile: tempPath, encoding: .utf8)
        #expect(contents.contains("hello file sink"))
        #expect(contents.contains("[INFO]"))
    }

    @Test
    func doesNotWriteWhenDisabled() throws {
        let tempPath = NSTemporaryDirectory() + "OurinLogFileSinkTests-\(UUID().uuidString).log"
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
            UserDefaults.standard.removeObject(forKey: enableKey)
            UserDefaults.standard.removeObject(forKey: pathKey)
            LogFileSink.shared.resetForTesting()
        }

        UserDefaults.standard.set(false, forKey: enableKey)
        UserDefaults.standard.set(tempPath, forKey: pathKey)
        LogFileSink.shared.resetForTesting()

        LogFileSink.shared.write(level: "INFO", message: "should not appear")

        #expect(FileManager.default.fileExists(atPath: tempPath) == false)
    }

    @Test
    func createsParentDirectoryIfMissing() throws {
        let tempDir = NSTemporaryDirectory() + "OurinLogFileSinkTests-dir-\(UUID().uuidString)"
        let tempPath = tempDir + "/nested/ourin.log"
        defer {
            try? FileManager.default.removeItem(atPath: tempDir)
            UserDefaults.standard.removeObject(forKey: enableKey)
            UserDefaults.standard.removeObject(forKey: pathKey)
            LogFileSink.shared.resetForTesting()
        }

        UserDefaults.standard.set(true, forKey: enableKey)
        UserDefaults.standard.set(tempPath, forKey: pathKey)
        LogFileSink.shared.resetForTesting()

        LogFileSink.shared.write(level: "ERROR", message: "nested dir test")

        #expect(FileManager.default.fileExists(atPath: tempPath) == true)
    }

    @Test
    func defaultLogPathUsedWhenUnset() throws {
        UserDefaults.standard.removeObject(forKey: pathKey)
        defer { UserDefaults.standard.removeObject(forKey: pathKey) }

        #expect(LogFileSink.currentLogPath() == LogFileSink.defaultLogPath)
        #expect(LogFileSink.defaultLogPath.contains("/Library/Logs/Ourin/ourin.log"))
    }
}
