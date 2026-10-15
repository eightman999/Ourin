import Testing
@testable import Ourin

struct LaunchSettingsWindowTests {
    @Test
    func onlyWindowGroupSettingsWindowsAreTreatedAsAutoOpened() {
        // WindowGroup("Settings") が起動時に自動生成・復元する窓
        #expect(AppDelegate.isAutoOpenedSettingsWindow(identifier: "Settings-AppWindow-1"))
        #expect(AppDelegate.isAutoOpenedSettingsWindow(identifier: "Settings-AppWindow-3"))
        // メニュー・ゴーストから開く設定画面やほかの窓は閉じない
        #expect(!AppDelegate.isAutoOpenedSettingsWindow(identifier: "SettingsWindow"))
        #expect(!AppDelegate.isAutoOpenedSettingsWindow(identifier: "DevTools-AppWindow-1"))
        #expect(!AppDelegate.isAutoOpenedSettingsWindow(identifier: "GhostCharacterWindow_0"))
        #expect(!AppDelegate.isAutoOpenedSettingsWindow(identifier: nil))
    }
}
