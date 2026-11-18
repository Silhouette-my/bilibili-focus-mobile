package org.bilibilifocus.android.images

import coil.size.Scale
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class FocusDynamicImagePrefetcherTests {
    @Test
    fun boundsBackgroundWorkAndRetainsOverlappingRequestsDuringScroll() = runTest {
        val started = mutableListOf<FocusDynamicImageRequest>()
        val cancelled = mutableListOf<FocusDynamicImageRequest>()
        val prefetcher = FocusDynamicImagePrefetcher(backgroundScope) { request ->
            started += request
            try { awaitCancellation() } finally { cancelled += request }
        }
        val (a, b, c, d) = (0..3).map(::request)
        prefetcher.update(listOf(a, b, c))
        runCurrent()
        assertEquals(listOf(a, b), started)
        prefetcher.update(listOf(b, c, d))
        runCurrent()
        assertEquals(listOf(a, b, c), started)
        assertEquals(listOf(a), cancelled)
        assertFalse(d in started)
        prefetcher.clear()
        runCurrent()
        assertTrue(b in cancelled && c in cancelled)
        assertFalse(d in started)
        prefetcher.close()
    }

    @Test
    fun completedPrefetchIsNotRestartedForAnOverlappingOrAppendedWindow() = runTest {
        val started = mutableListOf<FocusDynamicImageRequest>()
        val prefetcher = FocusDynamicImagePrefetcher(backgroundScope) { started += it }
        val (a, b, c) = (0..2).map(::request)
        prefetcher.update(listOf(a, a, b))
        runCurrent()
        prefetcher.update(listOf(a, b, c))
        runCurrent()
        assertEquals(listOf(a, b, c), started)
        prefetcher.close()
    }

    @Test
    fun changedURLOrSizeReplacesOnlyTheChangedConsumerAndClearStopsQueuedWork() = runTest {
        val started = mutableListOf<FocusDynamicImageRequest>()
        val finished = mutableListOf<FocusDynamicImageRequest>()
        val release = CompletableDeferred<Unit>()
        val prefetcher = FocusDynamicImagePrefetcher(backgroundScope) {
            started += it
            try { release.await() } finally { finished += it }
        }
        val a = request(0)
        val resized = a.copy(width = 256, height = 256)
        prefetcher.update(listOf(a))
        runCurrent()
        prefetcher.update(listOf(resized))
        runCurrent()
        assertEquals(listOf(a, resized), started)
        assertEquals(listOf(a), finished)
        prefetcher.close()
        runCurrent()
        assertEquals(listOf(a, resized), finished)
    }

    private fun request(index: Int) = FocusDynamicImageRequest("https://i0.hdslb.com/bfs/face/$index.jpg", 128, 128, Scale.FILL)
}
