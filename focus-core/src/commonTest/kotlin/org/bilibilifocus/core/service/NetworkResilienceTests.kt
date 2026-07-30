package org.bilibilifocus.core.service

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

class NetworkResilienceTests {
    @Test
    fun `idempotent GET retries transient statuses`() = runTest {
        val delegate = SequenceHttpClient(
            responses = ArrayDeque(
                listOf(
                    HttpResponse(503, "busy"),
                    HttpResponse(429, "slow down"),
                    HttpResponse(200, "ok"),
                ),
            ),
        )
        val delays = mutableListOf<Long>()
        val client = ResilientHttpClient(
            delegate = delegate,
            policy = HttpRetryPolicy(maxAttempts = 3, initialDelayMillis = 10),
            sleeper = { delays += it },
        )

        assertEquals(200, client.get("https://api.bilibili.com/test").statusCode)
        assertEquals(3, delegate.getCalls)
        assertEquals(listOf(10L, 20L), delays)
    }

    @Test
    fun `POST is never retried`() = runTest {
        val delegate = SequenceHttpClient(
            responses = ArrayDeque(),
            postResponse = HttpResponse(503, "busy"),
        )
        val client = ResilientHttpClient(delegate)

        assertEquals(503, client.post("https://api.bilibili.com/write").statusCode)
        assertEquals(1, delegate.postCalls)
    }

    @Test
    fun `cancellation is never converted into retry`() = runTest {
        val delegate = SequenceHttpClient(
            responses = ArrayDeque(),
            getFailure = CancellationException("cancel"),
        )
        val client = ResilientHttpClient(delegate)

        assertFailsWith<CancellationException> {
            client.get("https://api.bilibili.com/test")
        }
        assertEquals(1, delegate.getCalls)
    }

    @Test
    fun `diagnostics redact query and retain bounded newest events`() = runTest {
        val sink = InMemoryNetworkEventSink(capacity = 2)
        val client = ObservingHttpClient(
            delegate = SequenceHttpClient(
                responses = ArrayDeque(
                    listOf(
                        HttpResponse(200, "one"),
                        HttpResponse(404, "two"),
                        HttpResponse(200, "three"),
                    ),
                ),
            ),
            sink = sink,
        )

        client.get("https://api.bilibili.com/one?keyword=秘密&w_rid=signature")
        client.get("https://api.bilibili.com/two?SESSDATA=secret")
        client.get("https://api.bilibili.com/three#private")

        val events = sink.snapshot()
        assertEquals(2, events.size)
        assertEquals("https://api.bilibili.com/two", events[0].target)
        assertEquals("https://api.bilibili.com/three", events[1].target)
        assertEquals(404, events[0].statusCode)
        assertNull(events[1].failureType)
    }
}

private class SequenceHttpClient(
    private val responses: ArrayDeque<HttpResponse>,
    private val postResponse: HttpResponse = HttpResponse(200, "ok"),
    private val getFailure: Exception? = null,
) : HttpClient {
    var getCalls = 0
    var postCalls = 0

    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
        getCalls += 1
        getFailure?.let { throw it }
        return responses.removeFirst()
    }

    override suspend fun post(
        url: String,
        body: String,
        headers: Map<String, String>,
    ): HttpResponse {
        postCalls += 1
        return postResponse
    }
}
