package org.bilibilifocus.android.ui

import org.bilibilifocus.android.ui.video.activeDanmakuRange
import org.bilibilifocus.android.ui.video.DanmakuSegmentLayoutCache
import org.bilibilifocus.android.VideoDanmakuRenderSegment
import org.bilibilifocus.core.model.VideoDanmaku
import org.bilibilifocus.core.model.VideoDanmakuMode
import kotlin.test.Test
import kotlin.test.assertEquals

class FocusDanmakuWindowTests {
    private fun segment(index: Int) = VideoDanmakuRenderSegment(index, List(1_000) { offset ->
        VideoDanmaku(index * 10_000L + offset, (index - 1) * 360_000L + offset * 359L,
            if (offset % 3 == 0) VideoDanmakuMode.TOP else VideoDanmakuMode.SCROLLING,
            25, null, "fixture", 0, 0)
    })

    @Test
    fun `normal arrivals prepare each comment once and retain cached seek layouts`() {
        val source = (1..30).map(::segment)
        val cache = DanmakuSegmentLayoutCache<Pair<Long, Int>>(8)
        var result = emptyList<DanmakuSegmentLayoutCache.PreparedSegment<Pair<Long, Int>>>()
        var baselineWork = 0
        val incrementalStart = System.nanoTime()
        for (count in 1..source.size) {
            baselineWork += count * 1_000
            result = cache.update(source.take(count)) { comment, lane -> comment.id to lane }
        }
        assertEquals(30_000, cache.processedCommentCount)
        assertEquals(465_000, baselineWork)
        val incrementalNanos = System.nanoTime() - incrementalStart
        val baselineStart = System.nanoTime()
        for (count in 1..source.size) {
            val history = source.take(count).flatMap { it.danmakus }
                .sortedWith(compareBy<VideoDanmaku> { it.progressMillis }.thenByDescending { it.weight })
            DanmakuSegmentLayoutCache<Pair<Long, Int>>(8)
                .update(listOf(VideoDanmakuRenderSegment(1, history))) { comment, lane -> comment.id to lane }
        }
        println("danmaku-segments=30 comments=30000 incrementalNanos=$incrementalNanos baselineNanos=${System.nanoTime() - baselineStart} incrementalVisits=30000 baselineVisits=465000")
        val reference = DanmakuSegmentLayoutCache<Pair<Long, Int>>(8)
            .update(listOf(VideoDanmakuRenderSegment(1, source.flatMap { it.danmakus }))) { comment, lane -> comment.id to lane }
        assertEquals(reference.flatMap { it.items }, result.flatMap { it.items })
        for (position in listOf(0L, 359_999L, 360_000L, 360_001L, 10_450_000L, 5_000L)) {
            fun active(segments: List<DanmakuSegmentLayoutCache.PreparedSegment<Pair<Long, Int>>>) =
                segments.flatMap { segment -> activeDanmakuRange(segment.progressTimes, position).map { segment.items[it] } }
            assertEquals(active(reference), active(result))
        }
        cache.update(source) { comment, lane -> comment.id to lane }
        assertEquals(30_000, cache.processedCommentCount)
    }

    @Test
    fun `out of order arrivals preserve lane assignments`() {
        val source = (1..3).map(::segment)
        val cache = DanmakuSegmentLayoutCache<Pair<Long, Int>>(3)
        cache.update(listOf(source[0], source[2])) { comment, lane -> comment.id to lane }
        val actual = cache.update(source) { comment, lane -> comment.id to lane }
        val reference = DanmakuSegmentLayoutCache<Pair<Long, Int>>(3)
            .update(listOf(VideoDanmakuRenderSegment(1, source.flatMap { it.danmakus }))) { comment, lane -> comment.id to lane }
        assertEquals(reference.flatMap { it.items }, actual.flatMap { it.items })
    }

    @Test
    fun `window includes repeated starts and excludes fully elapsed comments`() {
        val times = longArrayOf(0, 0, 4_999, 5_000, 5_000, 10_000)
        assertEquals(0..1, activeDanmakuRange(times, 0))
        assertEquals(2..4, activeDanmakuRange(times, 5_000))
        assertEquals(5..5, activeDanmakuRange(times, 10_000))
        assertEquals(IntRange.EMPTY, activeDanmakuRange(longArrayOf(), 10_000))
    }

    @Test
    fun `indexed window matches complete scan during forward and backward seeks`() {
        val times = LongArray(10_000) { it * 137L }
        for (position in listOf(0L, 4_999L, 500_000L, 20_000L, 1_400_000L, 5_000L)) {
            val scanned = times.indices.filter { position - times[it] in 0L until 5_000L }
            assertEquals(scanned, activeDanmakuRange(times, position).toList(), "position=$position")
        }
    }
}
