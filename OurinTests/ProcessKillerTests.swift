import Foundation
import Testing
@testable import Ourin

struct ProcessKillerTests {
    @Test
    func onlyTheMainExecutableCountsAsAnOurinInstance() {
        #expect(ProcessKiller.isOurinMainExecutable(path: "/Applications/Ourin.app/Contents/MacOS/Ourin"))
        #expect(ProcessKiller.isOurinMainExecutable(path: "/Users/x/dev/Ourin/.build/DerivedData/Build/Products/Debug/Ourin.app/Contents/MacOS/Ourin"))
        // 自バンドル内の XPC ヘルパーや別アプリは別インスタンス扱いしない
        #expect(!ProcessKiller.isOurinMainExecutable(path: "/Applications/Ourin.app/Contents/XPCServices/OurinShioriXPCService.xpc/Contents/MacOS/OurinShioriXPCService"))
        #expect(!ProcessKiller.isOurinMainExecutable(path: "/Applications/OurinTool.app/Contents/MacOS/OurinTool"))
    }

    @Test
    func xctestHostsAreRecognizedFromTheirEnvironment() {
        #expect(ProcessKiller.isTestHost(argumentsAndEnvironment: ["/path/Ourin", "-NSTreatUnknownArgumentsAsOpen", "NO", "XCTestConfigurationFilePath=/tmp/x.xctestconfiguration"]))
        #expect(ProcessKiller.isTestHost(argumentsAndEnvironment: ["/path/Ourin", "XCTestSessionIdentifier=ABC"]))
        #expect(!ProcessKiller.isTestHost(argumentsAndEnvironment: ["/path/Ourin", "HOME=/Users/x", "PATH=/usr/bin"]))
    }

    @Test
    func thisTestHostIsNeverReportedAsAnotherInstance() {
        // テストはテストホスト（Ourin.app）上で動く。自分自身は「他の稼働中インスタンス」に含めない。
        #expect(!ProcessKiller.otherRunningOurinInstances().contains(getpid()))
    }
}
