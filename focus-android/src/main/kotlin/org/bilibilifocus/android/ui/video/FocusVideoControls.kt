package org.bilibilifocus.android.ui.video

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.bilibilifocus.android.R
import org.bilibilifocus.core.model.VideoInfo
import org.bilibilifocus.core.model.VideoInteractionState

private val SPEEDS = floatArrayOf(1f, 1.25f, 1.5f, 2f)

@Composable
internal fun VideoControlDock(
    isPlaying: Boolean,
    playbackSpeed: Float,
    onTogglePlay: () -> Unit,
    onChangeSpeed: () -> Unit,
    danmakuEnabled: Boolean,
    onToggleDanmaku: () -> Unit,
    onToggleFullscreen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isDarkTheme = MaterialTheme.colorScheme.background.luminance() < 0.5f
    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(
                brush = Brush.verticalGradient(
                    colors = if (isDarkTheme) {
                        listOf(
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.10f),
                            Color.Black.copy(alpha = 0.22f),
                            Color.Black.copy(alpha = 0.34f),
                        )
                    } else {
                        listOf(
                            Color.Transparent,
                            Color.White.copy(alpha = 0.08f),
                            Color.White.copy(alpha = 0.20f),
                            Color.White.copy(alpha = 0.34f),
                        )
                    },
                ),
            )
            .navigationBarsPadding()
            .padding(start = 16.dp, end = 16.dp, top = 2.dp, bottom = 2.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(24.dp))
                .background(
                    if (isDarkTheme) {
                        Color(0xC8262C36)
                    } else {
                        Color.White.copy(alpha = 0.72f)
                    }
                )
                .border(
                    width = 1.dp,
                    color = if (isDarkTheme) {
                        Color.White.copy(alpha = 0.10f)
                    } else {
                        Color(0x241A1D24)
                    },
                    shape = RoundedCornerShape(24.dp),
                )
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            DockButton(
                icon = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                text = if (isPlaying) "暂停" else "播放",
                onClick = onTogglePlay,
                modifier = Modifier.weight(1f),
            )
            DockButton(
                icon = Icons.Outlined.Speed,
                text = "${trimSpeed(playbackSpeed)}x",
                onClick = onChangeSpeed,
                modifier = Modifier.weight(1f),
            )
            DockButton(
                icon = Icons.AutoMirrored.Outlined.Chat,
                text = if (danmakuEnabled) "开" else "关",
                onClick = onToggleDanmaku,
                active = danmakuEnabled,
                modifier = Modifier.weight(1f),
            )
            DockButton(
                icon = Icons.Filled.OpenInFull,
                text = "全屏",
                onClick = onToggleFullscreen,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
internal fun VideoActionBar(
    interactionState: VideoInteractionState,
    info: VideoInfo,
    onToggleLike: () -> Unit,
    onCoin: () -> Unit,
    onToggleFavorite: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(
                MaterialTheme.colorScheme.surfaceVariant.copy(
                    alpha = if (MaterialTheme.colorScheme.background.luminance() < 0.5f) 0.72f else 0.86f,
                )
            )
            .padding(horizontal = 6.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_like),
            value = formatVideoCount(info.stats.likes),
            active = interactionState.liked,
            onClick = onToggleLike,
            enabled = !interactionState.loading,
            modifier = Modifier.weight(1f),
        )
        VerticalDivider()
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_coin),
            value = formatVideoCount(info.stats.coins),
            active = interactionState.coined,
            onClick = onCoin,
            enabled = !interactionState.loading && !interactionState.coined,
            modifier = Modifier.weight(1f),
        )
        VerticalDivider()
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_fav),
            value = formatVideoCount(info.stats.favorites),
            active = interactionState.favorited,
            onClick = onToggleFavorite,
            enabled = !interactionState.loading,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun DockButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    active: Boolean = false,
) {
    val isDarkTheme = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val containerColor = when {
        active -> MaterialTheme.colorScheme.primary.copy(alpha = if (isDarkTheme) 0.22f else 0.18f)
        isDarkTheme -> Color(0xFF343A43)
        else -> Color.White.copy(alpha = 0.90f)
    }
    val contentColor = when {
        active -> MaterialTheme.colorScheme.primary
        isDarkTheme -> Color.White
        else -> Color(0xFF2E3138)
    }

    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(containerColor),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
        colors = ButtonDefaults.textButtonColors(
            contentColor = contentColor,
            disabledContentColor = if (isDarkTheme) Color.White.copy(alpha = 0.42f) else Color(0xFF8E95A1),
        ),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
            Text(
                text,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}


@Composable
private fun ActionMetricButton(
    painter: Painter,
    value: String,
    active: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
        colors = ButtonDefaults.textButtonColors(
            contentColor = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            disabledContentColor = MaterialTheme.colorScheme.outline,
        ),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                painter = painter,
                contentDescription = null,
                modifier = Modifier.size(22.dp),
            )
            Text(
                value,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun VerticalDivider() {
    Box(
        modifier = Modifier
            .width(1.dp)
            .height(20.dp)
            .background(MaterialTheme.colorScheme.outlineVariant),
    )
}


internal fun nextSpeed(current: Float): Float {
    val currentIndex = SPEEDS.indexOfFirst { kotlin.math.abs(it - current) < 0.01f }
    return if (currentIndex == -1 || currentIndex == SPEEDS.lastIndex) SPEEDS.first() else SPEEDS[currentIndex + 1]
}

private fun trimSpeed(speed: Float): String {
    return if (speed % 1f == 0f) speed.toInt().toString() else speed.toString()
}

internal fun formatVideoCount(count: Long): String = when {
    count >= 100_000_000L -> {
        "%.1f亿".format(count / 100_000_000.0).replace(".0亿", "亿")
    }
    count >= 10000L -> {
        "%.1f万".format(count / 10_000.0).replace(".0万", "万")
    }
    else -> count.toString()
}
