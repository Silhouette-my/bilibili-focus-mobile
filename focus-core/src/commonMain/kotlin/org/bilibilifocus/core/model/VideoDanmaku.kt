package org.bilibilifocus.core.model

enum class VideoDanmakuMode(val rawValue: Int) {
    SCROLLING(1),
    BOTTOM(4),
    TOP(5);

    companion object {
        fun fromRawValue(value: Int): VideoDanmakuMode? = entries.firstOrNull { it.rawValue == value }
    }
}

data class VideoDanmaku(
    val id: Long,
    val progressMillis: Long,
    val mode: VideoDanmakuMode,
    val fontSize: Int,
    val colorRgb: Int?,
    val content: String,
    val weight: Int,
    val pool: Int,
)

data class VideoDanmakuView(
    val state: Int,
    val segmentDurationMillis: Long,
    val totalSegments: Int,
    val count: Long,
) {
    val isClosed: Boolean get() = state != 0
}

data class VideoDanmakuSegment(
    val danmakus: List<VideoDanmaku>,
    val isClosed: Boolean = false,
)

object VideoDanmakuSegmentScheduler {
    const val DEFAULT_SEGMENT_DURATION_MILLIS = 360_000L
    const val DEFAULT_PREFETCH_WINDOW_MILLIS = 30_000L

    fun segmentIndexes(
        playbackPositionMillis: Long,
        segmentDurationMillis: Long,
        totalSegments: Int,
        prefetchWindowMillis: Long = DEFAULT_PREFETCH_WINDOW_MILLIS,
    ): List<Int> {
        val position = playbackPositionMillis.coerceAtLeast(0)
        val duration = segmentDurationMillis.takeIf { it > 0 }
            ?: DEFAULT_SEGMENT_DURATION_MILLIS
        val quotient = position / duration
        val calculated = if (quotient >= Int.MAX_VALUE.toLong()) {
            Int.MAX_VALUE
        } else {
            quotient.toInt() + 1
        }
        val current = if (totalSegments > 0) calculated.coerceAtMost(totalSegments) else calculated
        if (current <= 0) return emptyList()

        val result = mutableListOf(current)
        val segmentEnd = if (duration > Long.MAX_VALUE / current.toLong()) {
            Long.MAX_VALUE
        } else {
            current.toLong() * duration
        }
        val remaining = segmentEnd - position
        val next = current + 1
        if (remaining <= prefetchWindowMillis.coerceAtLeast(0) &&
            (totalSegments <= 0 || next <= totalSegments)
        ) {
            result += next
        }
        return result
    }
}
