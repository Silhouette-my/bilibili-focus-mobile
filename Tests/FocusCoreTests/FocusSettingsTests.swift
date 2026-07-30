import FocusCore
import Foundation
import Testing

struct FocusSettingsTests {
    @Test
    func defaultsMatchExpectedContract() {
        let settings = FocusSettings.defaults

        #expect(settings.redirectEnabled)
        #expect(settings.playerMaskEnabled)
        #expect(settings.nativeDanmakuEnabled)
        #expect(settings.nativeSubtitleEnabled)
        #expect(settings.nativeSubtitleLanguageCode.isEmpty)
        #expect(settings.searchMaskEnabled)
        #expect(settings.dynamicMaskEnabled)
        #expect(!settings.debugMode)
        #expect(settings.defaultEntry == .dynamic)
        #expect(settings.accentColorHex == "#FB7299")
    }

    @Test
    func settingsPersistAndReload() {
        let suiteName = "FocusSettingsTests.settingsPersistAndReload"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = FocusSettings(
            redirectEnabled: false,
            playerMaskEnabled: false,
            nativeDanmakuEnabled: false,
            nativeSubtitleEnabled: false,
            nativeSubtitleLanguageCode: "zh-CN",
            searchMaskEnabled: true,
            dynamicMaskEnabled: false,
            debugMode: true,
            defaultEntry: .search,
            accentColorHex: "#34c759"
        )

        settings.save(to: defaults)

        #expect(FocusSettings.load(from: defaults) == settings)
    }

    @Test
    func legacySettingsKeepValuesAndEnableNativeMediaOverlaysByDefault() throws {
        let legacy = Data(#"{"redirectEnabled":false,"defaultEntry":"search"}"#.utf8)
        let settings = try JSONDecoder().decode(FocusSettings.self, from: legacy)

        #expect(!settings.redirectEnabled)
        #expect(settings.defaultEntry == .search)
        #expect(settings.nativeDanmakuEnabled)
        #expect(settings.nativeSubtitleEnabled)
        #expect(settings.nativeSubtitleLanguageCode.isEmpty)
        #expect(settings.accentColorHex == "#FB7299")
    }

    @Test
    func accentColorNormalizesHexAndRejectsInvalidValues() {
        #expect(FocusSettings.normalizedAccentColorHex("34c759") == "#34C759")
        #expect(FocusSettings.normalizedAccentColorHex(" #00a1d6 ") == "#00A1D6")
        #expect(FocusSettings.normalizedAccentColorHex("#12345") == nil)
        #expect(FocusSettings(accentColorHex: "invalid").accentColorHex == "#FB7299")
    }
}
