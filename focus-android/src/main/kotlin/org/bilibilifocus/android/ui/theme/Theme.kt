package org.bilibilifocus.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import org.bilibilifocus.core.model.FocusSettings
import org.bilibilifocus.core.model.FocusThemeMode

val BiliPink = Color(0xFFFB7299)

// 对齐 iOS 视觉：B 站粉强调色 + 白卡片浮于浅灰底（iOS grouped 背景）。
val BiliLightColorScheme = lightColorScheme(
    primary = BiliPink,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFFFE1EA), // 选中态浅粉
    onPrimaryContainer = Color(0xFF5A0021),
    secondary = Color(0xFFEF6A92),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFFFE1EA),
    onSecondaryContainer = Color(0xFF59121F),
    tertiary = Color(0xFF8E6BB0),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFEFD9FF),
    onTertiaryContainer = Color(0xFF2C0A45),
    error = Color(0xFFBA1A1A),
    onError = Color.White,
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    background = Color(0xFFF4F5F7), // 浅冷灰底
    onBackground = Color(0xFF1A1C1E),
    surface = Color(0xFFFFFFFF), // 白卡片 / 栏
    onSurface = Color(0xFF1A1C1E),
    surfaceVariant = Color(0xFFECEEF1), // 搜索框 / chip 底
    onSurfaceVariant = Color(0xFF5A6068),
    outline = Color(0xFFC2C7CE),
    outlineVariant = Color(0xFFE2E5E9),
    inverseSurface = Color(0xFF2F3033),
    inverseOnSurface = Color(0xFFF1F0F4),
    inversePrimary = Color(0xFFFFB1C6),
)

val BiliDarkColorScheme = darkColorScheme(
    primary = BiliPink,
    onPrimary = Color(0xFF470017),
    primaryContainer = Color(0xFF6D1730),
    onPrimaryContainer = Color(0xFFFFD9E2),
    secondary = Color(0xFFFFB2C8),
    onSecondary = Color(0xFF5F1123),
    secondaryContainer = Color(0xFF7C2740),
    onSecondaryContainer = Color(0xFFFFD9E2),
    tertiary = Color(0xFFD8B8F7),
    onTertiary = Color(0xFF41215E),
    tertiaryContainer = Color(0xFF583876),
    onTertiaryContainer = Color(0xFFF2DAFF),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF0F1115),
    onBackground = Color(0xFFE7E9EE),
    surface = Color(0xFF161A20),
    onSurface = Color(0xFFE7E9EE),
    surfaceVariant = Color(0xFF252B34),
    onSurfaceVariant = Color(0xFFC1C7D0),
    outline = Color(0xFF8B919B),
    outlineVariant = Color(0xFF3B414A),
    inverseSurface = Color(0xFFE7E9EE),
    inverseOnSurface = Color(0xFF2B3037),
    inversePrimary = Color(0xFF9C294D),
)

@Composable
fun BilibiliFocusTheme(
    themeMode: FocusThemeMode = FocusThemeMode.SYSTEM,
    accentColorHex: String = FocusSettings.DEFAULT_ACCENT_COLOR_HEX,
    content: @Composable () -> Unit,
) {
    val darkTheme = when (themeMode) {
        FocusThemeMode.SYSTEM -> isSystemInDarkTheme()
        FocusThemeMode.LIGHT -> false
        FocusThemeMode.DARK -> true
    }
    val accentColor = remember(accentColorHex) { focusAccentColor(accentColorHex) }
    val colorScheme = remember(darkTheme, accentColor) {
        focusColorScheme(darkTheme = darkTheme, accentColor = accentColor)
    }
    MaterialTheme(
        colorScheme = colorScheme,
        content = content,
    )
}

internal fun focusAccentColor(rawValue: String): Color {
    val normalized = FocusSettings.normalizedAccentColorHex(rawValue)
        ?: FocusSettings.DEFAULT_ACCENT_COLOR_HEX
    val rgb = normalized.drop(1).toLong(16)
    return Color((0xFF000000L or rgb).toInt())
}

private fun focusColorScheme(darkTheme: Boolean, accentColor: Color) =
    (if (darkTheme) BiliDarkColorScheme else BiliLightColorScheme).let { base ->
        val containerBase = if (darkTheme) base.surface else Color.White
        val container = lerp(containerBase, accentColor, if (darkTheme) 0.36f else 0.18f)
        base.copy(
            primary = accentColor,
            onPrimary = contrastingContentColor(accentColor),
            primaryContainer = container,
            onPrimaryContainer = contrastingContentColor(container),
            secondary = accentColor,
            onSecondary = contrastingContentColor(accentColor),
            secondaryContainer = container,
            onSecondaryContainer = contrastingContentColor(container),
            inversePrimary = accentColor,
        )
    }

private fun contrastingContentColor(background: Color): Color {
    val luminance = background.luminance()
    val blackContrast = (luminance + 0.05f) / 0.05f
    val whiteContrast = 1.05f / (luminance + 0.05f)
    return if (blackContrast >= whiteContrast) Color.Black else Color.White
}
