package org.bilibilifocus.core.model

data class VideoSubtitleTrack(
    val id: Long,
    val languageCode: String,
    val displayName: String,
    val url: String,
    val isLocked: Boolean = false,
)

data class VideoSubtitleCue(val fromMillis: Long, val toMillis: Long, val content: String)

data class VideoSubtitleDocument(val cues: List<VideoSubtitleCue>) {
    private val latestEnd = LongArray(cues.size).also { ends ->
        var maximum = 0L
        cues.forEachIndexed { index, cue -> maximum = maxOf(maximum, cue.toMillis); ends[index] = maximum }
    }
    fun textAt(positionMillis: Long): String {
        var low = 0
        var high = cues.size
        while (low < high) {
            val middle = (low + high) ushr 1
            if (cues[middle].fromMillis <= positionMillis) low = middle + 1 else high = middle
        }
        val upper = low
        low = 0
        high = upper
        while (low < high) {
            val middle = (low + high) ushr 1
            if (latestEnd[middle] <= positionMillis) low = middle + 1 else high = middle
        }
        // BCC permits overlapping cues, including bilingual lines. The prefix
        // end index skips expired history without rescanning the whole document.
        return cues.subList(low, upper).filter { positionMillis < it.toMillis }.joinToString("\n") { it.content }
    }
}
