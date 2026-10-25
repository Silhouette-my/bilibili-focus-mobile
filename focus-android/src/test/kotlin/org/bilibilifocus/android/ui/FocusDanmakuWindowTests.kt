package org.bilibilifocus.android.ui

import org.bilibilifocus.android.ui.video.activeDanmakuRange
import kotlin.test.Test
import kotlin.test.assertEquals

class FocusDanmakuWindowTests {
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
