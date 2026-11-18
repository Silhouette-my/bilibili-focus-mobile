package org.bilibilifocus.core.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class VideoSubtitleTests {
    @Test fun `subtitles use half-open intervals and preserve overlapping lines`() {
        val document = VideoSubtitleDocument(listOf(
            VideoSubtitleCue(1_000, 3_000, "中文"),
            VideoSubtitleCue(1_500, 2_000, "English"),
            VideoSubtitleCue(3_000, 4_000, "下一句"),
        ))
        assertEquals("", document.textAt(999))
        assertEquals("中文\nEnglish", document.textAt(1_500))
        assertEquals("中文", document.textAt(2_000))
        assertEquals("下一句", document.textAt(3_000))
        assertEquals("", document.textAt(4_000))
        assertEquals("中文", document.textAt(1_000))
    }

    @Test fun `legacy settings preserve playback defaults without opting into autoplay`() {
        val settings = kotlinx.serialization.json.Json.decodeFromString<FocusSettings>("{}")
        assertFalse(settings.playbackPreferences.autoPlayNextPart)
        assertEquals(1f, settings.playbackPreferences.preferredRate)
        assertEquals(0.72f, settings.playbackPreferences.subtitleBackgroundOpacity)
    }

    @Test fun `stored playback settings are normalized at the read boundary`() {
        val preferences = FocusPlaybackPreferences(preferredRate = 12f, danmakuOpacity = -1f, subtitleFontScale = 10f).normalized()
        assertEquals(3f, preferences.preferredRate)
        assertEquals(0.1f, preferences.danmakuOpacity)
        assertEquals(1.75f, preferences.subtitleFontScale)
    }
}
