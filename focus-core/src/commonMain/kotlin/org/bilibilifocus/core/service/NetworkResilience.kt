package org.bilibilifocus.core.service

import io.ktor.http.parseUrl
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.time.TimeMark
import kotlin.time.TimeSource

data class NetworkEvent(
    val method: String,
    val target: String,
    val statusCode: Int?,
    val durationMillis: Long,
    val responseBytes: Int?,
    val failureType: String? = null,
)

interface NetworkEventSink {
    suspend fun record(event: NetworkEvent)
}

object NoOpNetworkEventSink : NetworkEventSink {
    override suspend fun record(event: NetworkEvent) = Unit
}

class InMemoryNetworkEventSink(
    private val capacity: Int = 100,
) : NetworkEventSink {
    init {
        require(capacity > 0) { "capacity must be positive" }
    }

    private val mutex = Mutex()
    private val events = ArrayDeque<NetworkEvent>()

    override suspend fun record(event: NetworkEvent) {
        mutex.withLock {
            while (events.size >= capacity) {
                events.removeFirst()
            }
            events.addLast(event)
        }
    }

    suspend fun snapshot(): List<NetworkEvent> = mutex.withLock { events.toList() }

    suspend fun clear() {
        mutex.withLock { events.clear() }
    }
}

data class HttpRetryPolicy(
    val maxAttempts: Int = 3,
    val initialDelayMillis: Long = 250,
    val maximumDelayMillis: Long = 2_000,
) {
    init {
        require(maxAttempts >= 1) { "maxAttempts must be at least one" }
        require(initialDelayMillis >= 0) { "initialDelayMillis must not be negative" }
        require(maximumDelayMillis >= initialDelayMillis) {
            "maximumDelayMillis must be at least initialDelayMillis"
        }
    }

    fun shouldRetry(statusCode: Int): Boolean =
        statusCode == 408 || statusCode == 425 || statusCode == 429 || statusCode in 500..599

    fun delayBeforeAttempt(attempt: Int): Long {
        if (attempt <= 1 || initialDelayMillis == 0L) return 0
        var result = initialDelayMillis
        repeat(attempt - 2) {
            result = (result * 2).coerceAtMost(maximumDelayMillis)
        }
        return result
    }
}

/**
 * Retries idempotent reads only. Mutating POST calls deliberately bypass the
 * policy so likes, coins, favorites, and history reports cannot be duplicated.
 */
class ResilientHttpClient(
    private val delegate: HttpClient,
    private val policy: HttpRetryPolicy = HttpRetryPolicy(),
    private val sleeper: suspend (Long) -> Unit = { millis -> delay(millis) },
) : HttpClient {
    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse =
        executeRead(statusCode = HttpResponse::statusCode) {
            delegate.get(url, headers)
        }

    override suspend fun getBytes(
        url: String,
        headers: Map<String, String>,
    ): BinaryHttpResponse = executeRead(statusCode = BinaryHttpResponse::statusCode) {
        delegate.getBytes(url, headers)
    }

    override suspend fun post(
        url: String,
        body: String,
        headers: Map<String, String>,
    ): HttpResponse = delegate.post(url, body, headers)

    override fun close() {
        delegate.close()
    }

    private suspend fun <Response> executeRead(
        statusCode: (Response) -> Int,
        request: suspend () -> Response,
    ): Response {
        var attempt = 1
        while (true) {
            try {
                val response = request()
                if (attempt >= policy.maxAttempts || !policy.shouldRetry(statusCode(response))) {
                    return response
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (attempt >= policy.maxAttempts) throw error
            }

            attempt += 1
            sleeper(policy.delayBeforeAttempt(attempt))
        }
    }
}

/**
 * Records a local-only, redacted ring-buffer event for each logical request.
 * Query strings and fragments are removed so WBI signatures, keywords, IDs,
 * and other private parameters never enter diagnostics.
 */
class ObservingHttpClient(
    private val delegate: HttpClient,
    private val sink: NetworkEventSink,
) : HttpClient {
    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse =
        observe("GET", url) { delegate.get(url, headers) }

    override suspend fun getBytes(
        url: String,
        headers: Map<String, String>,
    ): BinaryHttpResponse = observeBytes("GET", url) { delegate.getBytes(url, headers) }

    override suspend fun post(
        url: String,
        body: String,
        headers: Map<String, String>,
    ): HttpResponse = observe("POST", url) { delegate.post(url, body, headers) }

    override fun close() {
        delegate.close()
    }

    private suspend fun observe(
        method: String,
        url: String,
        request: suspend () -> HttpResponse,
    ): HttpResponse {
        val mark = TimeSource.Monotonic.markNow()
        try {
            val response = request()
            sink.record(
                NetworkEvent(
                    method = method,
                    target = redactedTarget(url),
                    statusCode = response.statusCode,
                    durationMillis = mark.elapsedNow().inWholeMilliseconds,
                    responseBytes = response.body.encodeToByteArray().size,
                ),
            )
            return response
        } catch (error: CancellationException) {
            recordFailure(method, url, mark, "cancelled")
            throw error
        } catch (error: Exception) {
            recordFailure(method, url, mark, error::class.simpleName ?: "Exception")
            throw error
        }
    }

    private suspend fun observeBytes(
        method: String,
        url: String,
        request: suspend () -> BinaryHttpResponse,
    ): BinaryHttpResponse {
        val mark = TimeSource.Monotonic.markNow()
        try {
            val response = request()
            sink.record(
                NetworkEvent(
                    method = method,
                    target = redactedTarget(url),
                    statusCode = response.statusCode,
                    durationMillis = mark.elapsedNow().inWholeMilliseconds,
                    responseBytes = response.body.size,
                ),
            )
            return response
        } catch (error: CancellationException) {
            recordFailure(method, url, mark, "cancelled")
            throw error
        } catch (error: Exception) {
            recordFailure(method, url, mark, error::class.simpleName ?: "Exception")
            throw error
        }
    }

    private suspend fun recordFailure(
        method: String,
        url: String,
        mark: TimeMark,
        failureType: String,
    ) {
        sink.record(
            NetworkEvent(
                method = method,
                target = redactedTarget(url),
                statusCode = null,
                durationMillis = mark.elapsedNow().inWholeMilliseconds,
                responseBytes = null,
                failureType = failureType,
            ),
        )
    }

    internal fun redactedTarget(url: String): String = redactedNetworkTarget(url)
}

/**
 * Keeps only the HTTP(S) origin and encoded path. Parsing and rebuilding the
 * target also strips URL user-info in addition to query strings and fragments.
 */
internal fun redactedNetworkTarget(url: String): String {
    val parsed = parseUrl(url) ?: return ""
    val scheme = parsed.protocol.name.lowercase()
    if (scheme != "http" && scheme != "https") return ""
    val host = parsed.host.takeIf(String::isNotEmpty) ?: return ""
    val renderedHost = if (':' in host && !host.startsWith("[")) "[$host]" else host
    return "$scheme://$renderedHost${parsed.encodedPath}"
}
