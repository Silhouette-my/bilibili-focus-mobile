package org.bilibilifocus.android.images

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Shares only unfinished work. Coil remains responsible for every cached result. */
internal class FocusImageInFlightRequests<Key : Any, Value>(private val scope: CoroutineScope) {
    private class Flight<Value>(val result: Deferred<Value>, var consumers: Int = 1)
    private val mutex = Mutex()
    private val flights = mutableMapOf<Key, Flight<Value>>()

    suspend fun execute(key: Key, load: suspend () -> Value): Value {
        val flight = mutex.withLock {
            flights[key]?.also { it.consumers++ } ?: Flight(scope.async(start = CoroutineStart.LAZY) { load() })
                .also { flights[key] = it }
        }
        try {
            flight.result.start()
            return flight.result.await()
        } finally {
            withContext(NonCancellable) {
                mutex.withLock {
                    flight.consumers--
                    if (flight.consumers == 0) {
                        flights.remove(key)
                        flight.result.cancel()
                    }
                }
            }
        }
    }
}
