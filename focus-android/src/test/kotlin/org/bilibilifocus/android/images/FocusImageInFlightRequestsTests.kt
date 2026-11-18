package org.bilibilifocus.android.images

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.assertNotEquals
import coil.size.Scale

@OptIn(ExperimentalCoroutinesApi::class)
class FocusImageInFlightRequestsTests {
    @Test
    fun sameKeySharesOneLoadAndCancellingPrefetchDoesNotCancelVisibleConsumer() = runTest {
        val flights = flights()
        val response = CompletableDeferred<String>()
        var calls = 0
        var cancelled = false
        val prefetch = async {
            flights.execute("cover-512-fill") {
                calls++
                try { response.await() } finally { cancelled = !response.isCompleted }
            }
        }
        runCurrent()
        val visible = async { flights.execute("cover-512-fill") { error("Must join the active request") } }
        runCurrent()
        prefetch.cancel()
        runCurrent()
        assertEquals(1, calls)
        assertFalse(cancelled)
        assertTrue(visible.isActive)
        response.complete("decoded image")
        assertEquals("decoded image", visible.await())
    }

    @Test
    fun lastConsumerCancellationReleasesTheFlightAndAllowsAReplacement() = runTest {
        val flights = flights()
        var calls = 0
        var cancelled = 0
        val first = async {
            flights.execute("cover") {
                calls++
                try { awaitCancellation() } finally { cancelled++ }
            }
        }
        runCurrent()
        val second = async { flights.execute("cover") { error("Must share") } }
        runCurrent()
        first.cancel()
        runCurrent()
        assertEquals(0, cancelled)
        second.cancel()
        runCurrent()
        assertEquals(1, cancelled)
        assertEquals("replacement", flights.execute("cover") { calls++; "replacement" })
        assertEquals(2, calls)
    }

    @Test
    fun failedFlightIsSharedThenRemovedSoAVisibleRetryCanProceed() = runTest {
        val flights = flights()
        val finish = CompletableDeferred<Unit>()
        var calls = 0
        val first = async {
            runCatching { flights.execute("failed") { calls++; finish.await(); error("HTTP failure") } }
        }
        runCurrent()
        val second = async { runCatching { flights.execute("failed") { error("Must share failure") } } }
        runCurrent()
        finish.complete(Unit)
        assertEquals("HTTP failure", first.await().exceptionOrNull()?.message)
        assertEquals("HTTP failure", second.await().exceptionOrNull()?.message)
        assertEquals(1, calls)
        assertEquals("recovered", flights.execute("failed") { calls++; "recovered" })
        assertEquals(2, calls)
    }

    @Test
    fun distinctURLSizeAndScaleKeysRunConcurrentlyAndCompletedResultsAreNotCachedHere() = runTest {
        val flights = flights()
        val release = CompletableDeferred<Unit>()
        val started = mutableListOf<String>()
        val jobs = listOf("a-512-fill", "a-768-fill", "a-512-fit", "b-512-fill").map { key ->
            async { flights.execute(key) { started += key; release.await(); key } }
        }
        runCurrent()
        assertEquals(4, started.size)
        release.complete(Unit)
        jobs.forEach { it.await() }
        assertEquals("fresh call", flights.execute("a-512-fill") { "fresh call" })
    }

    @Test
    fun equalDerivedURLsDoNotShareDifferentOriginalFallbacks() = runTest {
        fun key(source: String): FocusImageCDNInterceptor.FlightKey {
            val canonical = FocusImageCDNRequest.canonicalURL(source)
            return FocusImageCDNInterceptor.FlightKey(
                checkNotNull(FocusImageCDNRequest.thumbnailURL(canonical, 512)), 512, 288, Scale.FILL, canonical,
            )
        }
        val original = key("http://i0.hdslb.com/bfs/archive/cover.jpg")
        val previouslySized = key("https://i0.hdslb.com/bfs/archive/cover.jpg@100w.webp")
        assertEquals(original.url, previouslySized.url)
        assertNotEquals(original, previouslySized)
        assertEquals(original, key("https://i0.hdslb.com/bfs/archive/cover.jpg"))

        val flights = FocusImageInFlightRequests<FocusImageCDNInterceptor.FlightKey, String>(supervisedScope())
        val release = CompletableDeferred<Unit>()
        val started = mutableListOf<String>()
        val requests = listOf(original, previouslySized).map { requestKey ->
            async {
                flights.execute(requestKey) {
                    started += requestKey.fallbackURL
                    release.await()
                    requestKey.fallbackURL // The response when the shared derivative returns 403/404.
                }
            }
        }
        runCurrent()
        assertEquals(2, started.size)
        release.complete(Unit)
        assertEquals(original.fallbackURL, requests[0].await())
        assertEquals(previouslySized.fallbackURL, requests[1].await())
    }

    private fun TestScope.supervisedScope() = CoroutineScope(backgroundScope.coroutineContext + SupervisorJob(backgroundScope.coroutineContext[Job]))
    private fun TestScope.flights() = FocusImageInFlightRequests<String, String>(supervisedScope())
}
