package org.bilibilifocus.core.repository

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class AsyncExpiringCacheContentionTests {
    @Test
    fun `cancelled leader completes followers even when cleanup must wait for mutex`() = runTest {
        val cache = AsyncExpiringCache<String, String>()
        val policy = CachePolicy(freshForMillis = 100)
        val started = CompletableDeferred<Unit>()
        val leader = async {
            cache.value("feed", policy) {
                started.complete(Unit)
                awaitCancellation()
            }
        }
        started.await()
        val follower = async { cache.value("feed", policy) { error("Unexpected second loader") } }
        runCurrent()

        // Hold the actual private mutex to make the cancellation interleaving
        // deterministic without adding a production scheduling/test hook.
        val mutexField = cache.javaClass.getDeclaredField("mutex").apply { isAccessible = true }
        val mutex = mutexField.get(cache) as Mutex
        mutex.lock()
        try {
            leader.cancel()
            runCurrent()
        } finally {
            mutex.unlock()
        }
        try {
            advanceUntilIdle()
            assertTrue(follower.isCompleted, "Followers must not retain an abandoned deferred")
            assertTrue(follower.isCancelled)
            assertEquals("fresh", withTimeout(1_000) { cache.value("feed", policy) { "fresh" } })
        } finally {
            leader.cancelAndJoin()
            follower.cancelAndJoin()
        }
    }
}
