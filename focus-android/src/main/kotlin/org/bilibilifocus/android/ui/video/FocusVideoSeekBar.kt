package org.bilibilifocus.android.ui.video

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp

internal val BilibiliPink = Color(0xFFFB7299)

internal fun seekFraction(x: Float, width: Float): Float = if (width <= 0f) 0f else (x / width).coerceIn(0f, 1f)

internal fun fractionOf(value: Long, total: Long): Float =
    if (total <= 0L) 0f else (value.toFloat() / total.toFloat()).coerceIn(0f, 1f)

/** Bilibili-style scrubber: translucent track, lighter buffered segment, pink played segment and white thumb. */
@Composable
internal fun VideoSeekBar(
    positionMillis: Long,
    bufferedMillis: Long,
    durationMillis: Long,
    enabled: Boolean,
    onScrubStart: (Long) -> Unit,
    onScrub: (Long) -> Unit,
    onScrubEnd: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    val duration by rememberUpdatedState(durationMillis)
    var active by remember { mutableStateOf(false) }
    val played = fractionOf(positionMillis, durationMillis)
    val buffered = fractionOf(bufferedMillis, durationMillis).coerceAtLeast(played)
    Box(
        modifier
            .height(44.dp)
            .semantics {
                contentDescription = "播放进度"
                stateDescription = "${formatPlaybackTime(positionMillis)} / ${formatPlaybackTime(durationMillis)}"
            }
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                detectTapGestures(onTap = { offset ->
                    val target = (seekFraction(offset.x, size.width.toFloat()) * duration).toLong()
                    onScrubStart(target); onScrubEnd(target)
                })
            }
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                var last = 0L
                detectDragGestures(
                    onDragStart = { offset ->
                        active = true
                        last = (seekFraction(offset.x, size.width.toFloat()) * duration).toLong()
                        onScrubStart(last)
                    },
                    onDrag = { change, _ ->
                        change.consume()
                        last = (seekFraction(change.position.x, size.width.toFloat()) * duration).toLong()
                        onScrub(last)
                    },
                    onDragEnd = { active = false; onScrubEnd(last) },
                    onDragCancel = { active = false; onScrubEnd(last) },
                )
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val trackHeight = 3.dp.toPx()
            val top = (size.height - trackHeight) / 2f
            val radius = CornerRadius(trackHeight / 2f)
            drawRoundRect(Color.White.copy(alpha = 0.28f), Offset(0f, top), Size(size.width, trackHeight), radius)
            drawRoundRect(Color.White.copy(alpha = 0.45f), Offset(0f, top), Size(size.width * buffered, trackHeight), radius)
            drawRoundRect(BilibiliPink, Offset(0f, top), Size(size.width * played, trackHeight), radius)
            val thumbRadius = (if (active) 8.dp else 5.dp).toPx()
            val cx = (size.width * played).coerceIn(thumbRadius, (size.width - thumbRadius).coerceAtLeast(thumbRadius))
            drawCircle(Color.White, thumbRadius, Offset(cx, size.height / 2f))
        }
    }
}

/** Thin progress line shown at the bottom edge while the controls are hidden (as in the official app). */
@Composable
internal fun VideoMiniProgress(positionMillis: Long, bufferedMillis: Long, durationMillis: Long, modifier: Modifier = Modifier) {
    val played = fractionOf(positionMillis, durationMillis)
    val buffered = fractionOf(bufferedMillis, durationMillis).coerceAtLeast(played)
    Canvas(modifier.fillMaxWidth().height(2.dp)) {
        drawRect(Color.White.copy(alpha = 0.2f), size = size)
        drawRect(Color.White.copy(alpha = 0.4f), size = Size(size.width * buffered, size.height))
        drawRect(BilibiliPink, size = Size(size.width * played, size.height))
    }
}
