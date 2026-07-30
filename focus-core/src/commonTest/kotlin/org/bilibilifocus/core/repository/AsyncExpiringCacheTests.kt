package org.bilibilifocus.core.repository

import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class AsyncExpiringCacheTests {
    @Test
    fun `coalesces concurrent misses and expires by ttl`() = runTest {
        var now = 1_000L
        var loads = 0
        val cache = AsyncExpiringCache<String, String>(nowMillis = { now })
        val policy = CachePolicy(freshForMillis = 100)

        val first = async { cache.value("video", policy) { loads += 1; "value-$loads" } }
        val second = async { cache.value("video", policy) { loads += 1; "value-$loads" } }

        assertEquals("value-1", first.await())
        assertEquals("value-1", second.await())
        assertEquals(1, loads)

        now += 101
        assertEquals("value-2", cache.value("video", policy) { loads += 1; "value-$loads" })
    }

    @Test
    fun `uses stale value only inside stale-if-error window`() = runTest {
        var now = 0L
        val cache = AsyncExpiringCache<String, String>(nowMillis = { now })
        val policy = CachePolicy(freshForMillis = 10, staleIfErrorForMillis = 20)

        cache.put("profile", "cached", policy)
        now = 11
        assertEquals(
            "cached",
            cache.value("profile", policy) { error("offline") },
        )

        now = 31
        assertFailsWith<IllegalStateException> {
            cache.value("profile", policy) { error("offline") }
        }
    }

    @Test
    fun `forced refresh bypasses fresh value but keeps it as error fallback`() = runTest {
        val cache = AsyncExpiringCache<String, String>()
        val policy = CachePolicy(freshForMillis = 10_000, staleIfErrorForMillis = 20_000)
        cache.put("feed", "cached", policy)
        var loads = 0

        assertEquals(
            "fresh",
            cache.value("feed", policy, forceRefresh = true) {
                loads += 1
                "fresh"
            },
        )
        assertEquals(
            "fresh",
            cache.value("feed", policy, forceRefresh = true) {
                loads += 1
                error("offline")
            },
        )
        assertEquals(2, loads)
    }

    @Test
    fun `evicts least recently used entry`() = runTest {
        val cache = AsyncExpiringCache<String, String>(maximumEntries = 2)
        val policy = CachePolicy(freshForMillis = 10_000)

        cache.put("a", "A", policy)
        cache.put("b", "B", policy)
        assertEquals("A", cache.cachedValue("a"))
        cache.put("c", "C", policy)

        assertEquals(null, cache.cachedValue("b"))
        assertEquals("A", cache.cachedValue("a"))
        assertEquals("C", cache.cachedValue("c"))
    }
}
