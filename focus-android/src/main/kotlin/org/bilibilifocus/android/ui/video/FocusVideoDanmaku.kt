package org.bilibilifocus.android.ui.video

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.clipToBounds
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
import org.bilibilifocus.android.VideoDanmakuRenderSegment
import org.bilibilifocus.core.model.VideoDanmaku
import org.bilibilifocus.core.model.VideoDanmakuMode
import org.bilibilifocus.core.model.FocusPlaybackPreferences

private const val DANMAKU_DISPLAY_MILLIS = 5_000L

@Composable
internal fun VideoDanmakuOverlay(
    state: VideoDanmakuUiState,
    enabled: Boolean,
    playbackPositionMillis: () -> Long,
    modifier: Modifier = Modifier,
    preferences: FocusPlaybackPreferences = FocusPlaybackPreferences(),
) {
    if (!enabled || state.segments.isEmpty()) return
    val textMeasurer = rememberTextMeasurer()
    val density = LocalDensity.current

    BoxWithConstraints(modifier = modifier.clipToBounds()) {
        val lineHeightPx = with(density) { 32.dp.toPx() } * preferences.danmakuFontScale * density.fontScale
        val usableHeightPx = with(density) { maxHeight.toPx() } * 0.75f * preferences.danmakuArea
        val laneCount = (usableHeightPx / lineHeightPx).toInt().coerceAtLeast(1)
        val layoutCache = remember(laneCount, textMeasurer, density, preferences.danmakuOpacity, preferences.danmakuFontScale, preferences.danmakuDensity) {
            DanmakuSegmentLayoutCache<PreparedDanmaku>(laneCount) { danmaku ->
                (danmaku.id and Long.MAX_VALUE) % 100 < preferences.danmakuDensity * 100
            }
        }
        val prepared = remember(state.segments, layoutCache) {
            layoutCache.update(state.segments) { danmaku, lane ->
                val color = danmakuColor(danmaku.colorRgb)
                val shadowColor = if (color.luminance() < 0.28f) Color.White else Color.Black
                val scale = (danmaku.fontSize / 25f).coerceIn(0.72f, 1.44f)
                val layout = textMeasurer.measure(
                    text = AnnotatedString(danmaku.content),
                    style = TextStyle(
                        color = color.copy(alpha = preferences.danmakuOpacity),
                        fontSize = (18f * scale * preferences.danmakuFontScale).sp,
                        fontWeight = FontWeight.SemiBold,
                        shadow = Shadow(
                            color = shadowColor.copy(alpha = preferences.danmakuOpacity),
                            offset = Offset(1.5f, 1.5f),
                            blurRadius = 2.5f,
                        ),
                    ),
                    maxLines = 1,
                )
                PreparedDanmaku(danmaku, lane, layout)
            }
        }
        Canvas(modifier = Modifier.fillMaxSize()) {
            val time = playbackPositionMillis()
            for (segment in prepared) {
                for (index in activeDanmakuRange(segment.progressTimes, time)) {
                    val preparedDanmaku = segment.items[index]
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
}

/** Immutable segments share both lane assignments and measured text across arrivals. */
internal class DanmakuSegmentLayoutCache<T>(private val laneCount: Int, private val shouldInclude: (VideoDanmaku) -> Boolean = { true }) {
    internal data class PreparedSegment<T>(
        val source: VideoDanmakuRenderSegment,
        val incoming: Map<VideoDanmakuMode, List<Long>>,
        val outgoing: Map<VideoDanmakuMode, List<Long>>,
        val items: List<T>,
        val progressTimes: LongArray,
    )
    private var segments = emptyList<PreparedSegment<T>>()
    var processedCommentCount = 0
        private set

    fun update(source: List<VideoDanmakuRenderSegment>, prepare: (VideoDanmaku, Int) -> T): List<PreparedSegment<T>> {
        val previous = segments.associateBy { it.source.index }
        var lanes = VideoDanmakuMode.entries.associateWith { List(laneCount) { 0L } }
        segments = source.map { segment ->
            val cached = previous[segment.index]
            if (cached != null && cached.source === segment && cached.incoming == lanes) {
                lanes = cached.outgoing
                cached
            } else {
                val incoming = lanes
                val availableAt = lanes.mapValues { it.value.toMutableList() }
                val times = mutableListOf<Long>()
                val items = segment.danmakus.mapNotNull { danmaku ->
                    if (!shouldInclude(danmaku)) return@mapNotNull null
                    val available = availableAt.getValue(danmaku.mode)
                    val lane = available.indexOfFirst { it <= danmaku.progressMillis }
                    processedCommentCount++
                    if (lane < 0) return@mapNotNull null
                    available[lane] = danmaku.progressMillis + DANMAKU_DISPLAY_MILLIS
                    times += danmaku.progressMillis
                    prepare(danmaku, lane)
                }
                lanes = availableAt.mapValues { it.value.toList() }
                PreparedSegment(segment, incoming, lanes, items, times.toLongArray())
            }
        }
        return segments
    }
}

/** Input follows the view model's ascending progress order; seeks need no retained cursor. */
internal fun activeDanmakuRange(progressTimes: LongArray, positionMillis: Long): IntRange {
    if (progressTimes.isEmpty() || positionMillis < progressTimes.first() ||
        progressTimes.last() <= positionMillis - DANMAKU_DISPLAY_MILLIS) return IntRange.EMPTY
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
