package org.bilibilifocus.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class FocusSettings(
    val redirectEnabled: Boolean = true,
    val playerMaskEnabled: Boolean = true,
    val nativeDanmakuEnabled: Boolean = true,
    val nativeSubtitleEnabled: Boolean = true,
    val nativeSubtitleLanguageCode: String = "",
    val playbackPreferences: FocusPlaybackPreferences = FocusPlaybackPreferences(),
    val searchMaskEnabled: Boolean = true,
    val dynamicMaskEnabled: Boolean = true,
    val debugMode: Boolean = false,
    val defaultEntry: FocusEntry = FocusEntry.DYNAMIC,
    val themeMode: FocusThemeMode = FocusThemeMode.SYSTEM,
    val accentColorHex: String = DEFAULT_ACCENT_COLOR_HEX,
    val dynamicVisibleKinds: Set<FocusDynamicFilterKind> = FocusDynamicFilterKind.entries.toSet(),
    val perAuthorDynamicFilters: Map<String, Set<FocusDynamicFilterKind>> = emptyMap(),
) {
    companion object {
        const val STORAGE_KEY = "focus.settings"
        const val DEFAULT_ACCENT_COLOR_HEX = "#FB7299"
        val DEFAULTS = FocusSettings()

        fun normalizedAccentColorHex(rawValue: String): String? {
            val digits = rawValue.trim().removePrefix("#")
            if (digits.length != 6 || digits.any { it.digitToIntOrNull(16) == null }) {
                return null
            }
            return "#${digits.uppercase()}"
        }
    }
}

@Serializable
data class FocusPlaybackPreferences(
    val preferredRate: Float = 1f,
    val autoPlayNextPart: Boolean = false,
    val danmakuOpacity: Float = 0.94f,
    val danmakuFontScale: Float = 1f,
    val danmakuArea: Float = 1f,
    val danmakuDensity: Float = 1f,
    val subtitleFontScale: Float = 1f,
    val subtitleBackgroundOpacity: Float = 0.72f,
) {
    /** Stored settings are a trust boundary; old versions omit all these fields. */
    fun normalized() = copy(
        preferredRate = preferredRate.finiteOr(1f).coerceIn(0.5f, 3f),
        danmakuOpacity = danmakuOpacity.finiteOr(0.94f).coerceIn(0.1f, 1f),
        danmakuFontScale = danmakuFontScale.finiteOr(1f).coerceIn(0.75f, 1.5f),
        danmakuArea = danmakuArea.finiteOr(1f).coerceIn(0.25f, 1f),
        danmakuDensity = danmakuDensity.finiteOr(1f).coerceIn(0.25f, 1f),
        subtitleFontScale = subtitleFontScale.finiteOr(1f).coerceIn(0.75f, 1.75f),
        subtitleBackgroundOpacity = subtitleBackgroundOpacity.finiteOr(0.72f).coerceIn(0f, 1f),
    )

    private fun Float.finiteOr(default: Float) = if (isFinite()) this else default
}

@Serializable
enum class FocusDynamicFilterKind {
    @SerialName("all") ALL,
    @SerialName("video") VIDEO,
    @SerialName("articleLike") ARTICLE_LIKE;

    val title: String
        get() = when (this) {
            ALL -> "综合"
            VIDEO -> "视频"
            ARTICLE_LIKE -> "图文"
        }
}

@Serializable
enum class FocusThemeMode {
    @SerialName("system") SYSTEM,
    @SerialName("light") LIGHT,
    @SerialName("dark") DARK;

    val title: String
        get() = when (this) {
            SYSTEM -> "跟随系统"
            LIGHT -> "浅色"
            DARK -> "深色"
        }
}
