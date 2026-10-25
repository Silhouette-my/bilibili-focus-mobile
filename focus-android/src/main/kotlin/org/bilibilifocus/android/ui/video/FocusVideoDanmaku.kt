package org.bilibilifocus.android.ui.video

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.bilibilifocus.android.VideoDanmakuLoadStatus
import org.bilibilifocus.android.VideoDanmakuUiState
import org.bilibilifocus.core.model.VideoDanmaku
import org.bilibilifocus.core.model.VideoDanmakuMode

private const val DANMAKU_DISPLAY_MILLIS = 5_000L

@Composable
internal fun VideoDanmakuOverlay(
    state: VideoDanmakuUiState,
    enabled: Boolean,
    playbackPositionMillis: () -> Long,
    modifier: Modifier = Modifier,
) {
    if (!enabled || state.danmakus.isEmpty()) return
    val textMeasurer = rememberTextMeasurer()
    val density = LocalDensity.current

    BoxWithConstraints(modifier = modifier) {
        val lineHeightPx = with(density) { 32.dp.toPx() }
        val usableHeightPx = with(density) { maxHeight.toPx() } * 0.75f
        val laneCount = (usableHeightPx / lineHeightPx).toInt().coerceAtLeast(1)
        val prepared = remember(state.danmakus, laneCount, textMeasurer) {
            val availableAt = VideoDanmakuMode.entries.associateWith { LongArray(laneCount) }.toMutableMap()
            state.danmakus.mapNotNull { danmaku ->
                val lanes = availableAt.getValue(danmaku.mode)
                val lane = lanes.indexOfFirst { it <= danmaku.progressMillis }
                if (lane < 0) return@mapNotNull null
                lanes[lane] = danmaku.progressMillis + DANMAKU_DISPLAY_MILLIS
                val color = danmakuColor(danmaku.colorRgb)
                val shadowColor = if (color.luminance() < 0.28f) Color.White else Color.Black
                val scale = (danmaku.fontSize / 25f).coerceIn(0.72f, 1.44f)
                val layout = textMeasurer.measure(
                    text = AnnotatedString(danmaku.content),
                    style = TextStyle(
                        color = color.copy(alpha = 0.94f),
                        fontSize = (18f * scale).sp,
                        fontWeight = FontWeight.SemiBold,
                        shadow = Shadow(
                            color = shadowColor.copy(alpha = 0.95f),
                            offset = Offset(1.5f, 1.5f),
                            blurRadius = 2.5f,
                        ),
                    ),
                    maxLines = 1,
                )
                PreparedDanmaku(danmaku, lane, layout)
            }
        }
        val progressTimes = remember(prepared) {
            LongArray(prepared.size) { prepared[it].danmaku.progressMillis }
        }

        Canvas(modifier = Modifier.fillMaxSize()) {
            val time = playbackPositionMillis()
            for (index in activeDanmakuRange(progressTimes, time)) {
                val preparedDanmaku = prepared[index]
                val elapsed = time - preparedDanmaku.danmaku.progressMillis
                val textWidth = preparedDanmaku.layout.size.width.toFloat()
                val x = when (preparedDanmaku.danmaku.mode) {
                    VideoDanmakuMode.SCROLLING -> {
                        val progress = elapsed.toFloat() / DANMAKU_DISPLAY_MILLIS
                        size.width - progress * (size.width + textWidth)
                    }
                    VideoDanmakuMode.TOP, VideoDanmakuMode.BOTTOM -> (size.width - textWidth) / 2f
                }
                val y = when (preparedDanmaku.danmaku.mode) {
                    VideoDanmakuMode.BOTTOM -> usableHeightPx - (preparedDanmaku.lane + 1) * lineHeightPx
                    VideoDanmakuMode.SCROLLING, VideoDanmakuMode.TOP -> preparedDanmaku.lane * lineHeightPx
                }
                drawText(
                    textLayoutResult = preparedDanmaku.layout,
                    topLeft = Offset(x, y.coerceAtLeast(0f)),
                )
            }
        }
    }
}

/** Input follows the view model's ascending progress order; seeks need no retained cursor. */
internal fun activeDanmakuRange(progressTimes: LongArray, positionMillis: Long): IntRange {
    fun insertionIndex(target: Long, afterEqual: Boolean): Int {
        var low = 0
        var high = progressTimes.size
        while (low < high) {
            val middle = low + (high - low) / 2
            val progress = progressTimes[middle]
            if (progress < target || (afterEqual && progress == target)) low = middle + 1
            else high = middle
        }
        return low
    }
    val start = insertionIndex((positionMillis - DANMAKU_DISPLAY_MILLIS + 1).coerceAtLeast(0), false)
    val end = insertionIndex(positionMillis, true)
    return start until end
}

@Composable
internal fun VideoDanmakuStatusBanner(
    state: VideoDanmakuUiState,
    enabled: Boolean,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (!enabled) return
    when (state.status) {
        VideoDanmakuLoadStatus.FAILED -> TextButton(
            onClick = onRetry,
            modifier = modifier
                .padding(top = 8.dp)
                .background(Color.Black.copy(alpha = 0.62f), RoundedCornerShape(14.dp)),
        ) {
            Text("弹幕加载失败 · 重试", color = Color.White)
        }
        VideoDanmakuLoadStatus.CLOSED -> Text(
            text = state.message ?: "该视频未开启弹幕",
            color = Color.White,
            style = MaterialTheme.typography.labelMedium,
            modifier = modifier
                .padding(top = 12.dp)
                .background(Color.Black.copy(alpha = 0.62f), RoundedCornerShape(12.dp))
                .padding(horizontal = 12.dp, vertical = 7.dp),
        )
        else -> Unit
    }
}

@Composable
internal fun DanmakuFullscreenButton(
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.52f), CircleShape),
    ) {
        Icon(
            imageVector = Icons.AutoMirrored.Outlined.Chat,
            contentDescription = if (enabled) "关闭弹幕" else "开启弹幕",
            tint = if (enabled) MaterialTheme.colorScheme.primary else Color.White,
        )
    }
}

private data class PreparedDanmaku(
    val danmaku: VideoDanmaku,
    val lane: Int,
    val layout: TextLayoutResult,
)

private fun danmakuColor(rgb: Int?): Color {
    val value = rgb ?: 0xffffff
    return Color(
        red = ((value shr 16) and 0xff) / 255f,
        green = ((value shr 8) and 0xff) / 255f,
        blue = (value and 0xff) / 255f,
        alpha = 1f,
    )
}
