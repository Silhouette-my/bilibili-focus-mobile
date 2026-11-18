package org.bilibilifocus.core.model

import org.bilibilifocus.core.storage.SettingsRepository
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FocusSettingsTests {

    @Test
    fun `defaults match expected contract`() {
        val settings = FocusSettings.DEFAULTS

        assertTrue(settings.redirectEnabled)
        assertTrue(settings.playerMaskEnabled)
        assertTrue(settings.nativeDanmakuEnabled)
        assertTrue(settings.nativeSubtitleEnabled)
        assertTrue(settings.nativeSubtitleLanguageCode.isEmpty())
        assertTrue(settings.searchMaskEnabled)
        assertTrue(settings.dynamicMaskEnabled)
        assertFalse(settings.debugMode)
        assertEquals(FocusEntry.DYNAMIC, settings.defaultEntry)
        assertEquals(FocusThemeMode.SYSTEM, settings.themeMode)
        assertEquals("#FB7299", settings.accentColorHex)
        assertEquals(FocusDynamicFilterKind.entries.toSet(), settings.dynamicVisibleKinds)
        assertTrue(settings.perAuthorDynamicFilters.isEmpty())
    }

    @Test
    fun `serialization round-trip preserves values`() {
        val settings = FocusSettings(
            redirectEnabled = false,
            playerMaskEnabled = false,
            nativeDanmakuEnabled = false,
            nativeSubtitleEnabled = false,
            nativeSubtitleLanguageCode = "zh-CN",
            searchMaskEnabled = true,
            dynamicMaskEnabled = false,
            debugMode = true,
            defaultEntry = FocusEntry.SEARCH,
            themeMode = FocusThemeMode.DARK,
            accentColorHex = "#34C759",
            dynamicVisibleKinds = setOf(FocusDynamicFilterKind.VIDEO),
            perAuthorDynamicFilters = mapOf(
                "mid:42" to setOf(FocusDynamicFilterKind.ARTICLE_LIKE),
            ),
        )

        val json = kotlinx.serialization.json.Json.encodeToString(FocusSettings.serializer(), settings)
        val restored = kotlinx.serialization.json.Json.decodeFromString(FocusSettings.serializer(), json)

        assertEquals(settings, restored)
    }

    @Test
    fun `legacy payload receives new setting defaults`() {
        val legacy = """{"redirectEnabled":false,"defaultEntry":"search"}"""

        val restored = kotlinx.serialization.json.Json {
            ignoreUnknownKeys = true
        }.decodeFromString(FocusSettings.serializer(), legacy)

        assertFalse(restored.redirectEnabled)
        assertEquals(FocusEntry.SEARCH, restored.defaultEntry)
        assertEquals(FocusThemeMode.SYSTEM, restored.themeMode)
        assertEquals("#FB7299", restored.accentColorHex)
        assertTrue(restored.nativeDanmakuEnabled)
        assertTrue(restored.nativeSubtitleEnabled)
        assertTrue(restored.nativeSubtitleLanguageCode.isEmpty())
        assertEquals(FocusDynamicFilterKind.entries.toSet(), restored.dynamicVisibleKinds)
        assertTrue(restored.perAuthorDynamicFilters.isEmpty())
    }

    @Test
    fun `accent color hex is normalized and validated`() {
        assertEquals("#34C759", FocusSettings.normalizedAccentColorHex("34c759"))
        assertEquals("#00A1D6", FocusSettings.normalizedAccentColorHex(" #00a1d6 "))
        assertEquals(null, FocusSettings.normalizedAccentColorHex("#12345"))
        assertEquals(null, FocusSettings.normalizedAccentColorHex("not-a-color"))
    }
}
