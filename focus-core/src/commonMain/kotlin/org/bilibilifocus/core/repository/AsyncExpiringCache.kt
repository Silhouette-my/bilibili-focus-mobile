package org.bilibilifocus.core.repository

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.bilibilifocus.core.service.currentEpochSeconds

data class CachePolicy(
    val freshForMillis: Long,
    val staleIfErrorForMillis: Long = 0,
) {
    init {
        require(freshForMillis >= 0) { "freshForMillis must not be negative" }
        require(staleIfErrorForMillis >= 0) { "staleIfErrorForMillis must not be negative" }
    }
}

/**
 * Account-local, memory-only cache for decoded domain models.
 *
 * Concurrent misses for the same key share one loader. A stale value can be
 * returned only when a refresh fails and the caller explicitly configured a
 * stale-if-error window. Cookies and request headers are never stored.
 */
class AsyncExpiringCache<Key : Any, Value : Any>(
    private val maximumEntries: Int = 100,
    private val nowMillis: () -> Long = { currentEpochSeconds() * 1_000 },
) {
    init {
        require(maximumEntries > 0) { "maximumEntries must be positive" }
    }

    private data class Entry<Value>(
        val value: Value,
        val freshUntilMillis: Long,
        val staleUntilMillis: Long,
    )

    private val mutex = Mutex()
    private val entries = LinkedHashMap<Key, Entry<Value>>()
    private val inFlight = mutableMapOf<Key, CompletableDeferred<Value>>()

    suspend fun value(
        key: Key,
        policy: CachePolicy,
        forceRefresh: Boolean = false,
        canUseStaleOnError: (Exception) -> Boolean = { true },
        loader: suspend () -> Value,
    ): Value {
        val now = nowMillis()
        var leader = false
        val deferred = mutex.withLock {
            val cached = entries[key]
            if (!forceRefresh && cached != null && now < cached.freshUntilMillis) {
                touch(key, cached)
                return cached.value
            }
            inFlight[key] ?: CompletableDeferred<Value>().also {
                inFlight[key] = it
                leader = true
            }
        }

        if (!leader) {
            return deferred.await()
        }

        try {
            val loaded = loader()
            val loadedAt = nowMillis()
            mutex.withLock {
                put(
                    key,
                    Entry(
                        value = loaded,
                        freshUntilMillis = loadedAt + policy.freshForMillis,
                        staleUntilMillis = loadedAt +
                            policy.freshForMillis +
                            policy.staleIfErrorForMillis,
                    ),
                )
                inFlight.remove(key)
            }
            deferred.complete(loaded)
            return loaded
        } catch (error: CancellationException) {
            // The cancelled loader must still unlink and settle its shared
            // deferred, including when another cache operation holds the lock.
            withContext(NonCancellable) {
                mutex.withLock { inFlight.remove(key) }
                deferred.completeExceptionally(error)
            }
            throw error
        } catch (error: Exception) {
            val acceptsStale = canUseStaleOnError(error)
            val stale = withContext(NonCancellable) {
                val fallback = mutex.withLock {
                    inFlight.remove(key)
                    if (!acceptsStale) {
                        entries.remove(key)
                        null
                    } else {
                        // Read and touch atomically: never resurrect a value
                        // invalidated or replaced while this loader was running.
                        entries[key]?.takeIf { nowMillis() < it.staleUntilMillis }
                            ?.also { touch(key, it) }
                    }
                }
                if (fallback != null) deferred.complete(fallback.value)
                else deferred.completeExceptionally(error)
                fallback
            }
            if (stale != null) return stale.value
            throw error
        }
    }

    suspend fun cachedValue(key: Key, allowStale: Boolean = false): Value? =
        mutex.withLock {
            val entry = entries[key] ?: return@withLock null
            val deadline = if (allowStale) entry.staleUntilMillis else entry.freshUntilMillis
            if (nowMillis() >= deadline) return@withLock null
            touch(key, entry)
            entry.value
        }

    suspend fun put(key: Key, value: Value, policy: CachePolicy) {
        val now = nowMillis()
        mutex.withLock {
            put(
                key,
                Entry(
                    value = value,
                    freshUntilMillis = now + policy.freshForMillis,
                    staleUntilMillis = now + policy.freshForMillis + policy.staleIfErrorForMillis,
                ),
            )
        }
    }

    suspend fun invalidate(key: Key) {
        mutex.withLock { entries.remove(key) }
    }

    suspend fun clear() {
        mutex.withLock { entries.clear() }
    }

    private fun put(key: Key, entry: Entry<Value>) {
        entries.remove(key)
        entries[key] = entry
        while (entries.size > maximumEntries) {
            entries.remove(entries.keys.first())
        }
    }

    private fun touch(key: Key, entry: Entry<Value>) {
        entries.remove(key)
        entries[key] = entry
    }
}
