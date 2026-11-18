import Foundation
@testable import FocusCore
import Testing

struct FocusPlaybackPreferencesTests {
    @Test func upgradingSettingsPreservesPlaybackDefaults() throws {
        let settings = try JSONDecoder().decode(FocusSettings.self, from: Data("{}".utf8))
        #expect(settings.playbackPreferences == .defaults)
        #expect(settings.playbackPreferences.preferredRate == 1)
        #expect(!settings.playbackPreferences.autoPlayNextPart)
        #expect(settings.playbackPreferences.danmakuOpacity == 0.94)
        #expect(settings.playbackPreferences.subtitleBackgroundOpacity == 0.72)
    }

    @Test func preferencesRoundTripAndValidatePersistedValues() throws {
        var settings = FocusSettings()
        settings.playbackPreferences = FocusPlaybackPreferences(preferredRate: 1.5, autoPlayNextPart: true,
            danmakuOpacity: 0.6, danmakuArea: 0.5, danmakuDensity: 0.25, subtitleFontScale: 1.25)
        let restored = try JSONDecoder().decode(FocusSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored == settings)
        let invalid = try JSONDecoder().decode(FocusPlaybackPreferences.self,
            from: Data(#"{"preferredRate":20,"danmakuArea":0,"danmakuDensity":-1,"subtitleBackgroundOpacity":3}"#.utf8))
        #expect(invalid.preferredRate == 3)
        #expect(invalid.danmakuArea == 0.25)
        #expect(invalid.danmakuDensity == 0.25)
        #expect(invalid.subtitleBackgroundOpacity == 1)
    }

    @Test func densitySamplingIsStableAndDefaultsKeepEveryComment() {
        let complete = FocusPlaybackPreferences.defaults
        let sparse = FocusPlaybackPreferences(danmakuDensity: 0.25)
        #expect((0..<100).allSatisfy { complete.includesDanmaku(id: Int64($0)) })
        #expect((0..<100).filter { sparse.includesDanmaku(id: Int64($0)) }.count == 25)
        #expect(sparse.includesDanmaku(id: 10) == sparse.includesDanmaku(id: 110))
    }
}
