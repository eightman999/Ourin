import Testing
@testable import Ourin

struct SystemNotificationDataTests {
    @Test
    func userInfoUsesDistinctAddressAndFullNameAndExplicitUndefinedGender() {
        let info = SystemUserInfo(addressName: "呼び名", fullName: "本名", birthday: "", gender: "undef")

        #expect(info.parameters == [
            "Reference0": "呼び名",
            "Reference1": "本名",
            "Reference2": "",
            "Reference3": "undef"
        ])
    }

    @Test
    func osInfoUsesFourReferenceColumns() {
        let info = SystemOSInfo(
            system: "macOS",
            version: "26.5.1",
            displayName: "macOS Tahoe",
            cpuType: "Apple M2 Max",
            clockMHz: "",
            cpuAdditionalInfo: "12 cores",
            physicalMemoryKB: 33_554_432,
            virtualMemoryKB: 41_943_040,
            uptimeMinutes: 123
        )

        #expect(info.parameters["Reference0"] == "macOS,26.5.1,macOS Tahoe")
        #expect(info.parameters["Reference1"] == "Apple M2 Max,,12 cores")
        #expect(info.parameters["Reference2"] == "33554432,41943040")
        #expect(info.parameters["Reference3"] == "123")
    }

    @Test
    func fontParametersAreSortedUniqueAndUseReferenceStar() {
        let params = SystemNotificationData.fontParameters(["  Hiragino Sans ", "Arial", "Arial", ""])

        #expect(params == [
            "Reference0": "Arial",
            "Reference1": "Hiragino Sans"
        ])
    }

    @Test
    func internationalInfoUsesUkadocOffsetSignAndWireValues() {
        let info = SystemInternationalInfo(
            utcOffsetMinutes: -540,
            daylightSavingTime: false,
            countryCode: "JP",
            languageCode: "ja"
        )

        #expect(info.parameters == [
            "Reference0": "-540",
            "Reference1": "0",
            "Reference2": "JP",
            "Reference3": "ja"
        ])
    }

    @Test
    func currentSystemNotificationDataDoesNotReturnSyntheticEmptySystemValues() {
        let os = SystemNotificationData.currentOSInfo()
        #expect(os.system == "macOS")
        #expect(!os.version.isEmpty)
        #expect(os.physicalMemoryKB > 0)
        #expect(os.virtualMemoryKB >= os.physicalMemoryKB)
        #expect(os.uptimeMinutes >= 0)

        let international = SystemNotificationData.currentInternationalInfo()
        #expect(international.utcOffsetMinutes >= -24 * 60)
        #expect(international.utcOffsetMinutes <= 24 * 60)
    }
}
