package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class DynamicFeedCacheIntegrationTests {
    @Test
    fun `authentication rejection cannot become stale success or keep a fresh page`() = runTest {
        val client = FeedHttpClient(ArrayDeque(listOf(
            HttpResponse(200, feedBody("before-expiry")),
            HttpResponse(200, """{"code":-101}"""),
            HttpResponse(200, feedBody("new-page")),
        )))
        val service = DynamicFeedService(MutableCookieProvider("fixture"), client)
        assertEquals("before-expiry", service.fetchFollowingFeedPage().nextOffset)
        assertFailsWith<DynamicFeedService.ServiceError.LoginRequired> {
            service.refreshFollowingFeedPage()
        }
        assertEquals("new-page", service.fetchFollowingFeedPage().nextOffset)
        assertEquals(3, client.requests.size)
    }

    @Test
    fun `sessions with colliding string hashes never share a feed page`() = runTest {
        assertEquals("Aa".hashCode(), "BB".hashCode())
        val cookies = MutableCookieProvider("Aa")
        val client = FeedHttpClient(ArrayDeque(listOf(
            HttpResponse(200, feedBody("account-a")),
            HttpResponse(200, feedBody("account-b")),
        )))
        val service = DynamicFeedService(cookies, client)
        assertEquals("account-a", service.fetchFollowingFeedPage().nextOffset)
        cookies.session = "BB"
        assertEquals("account-b", service.fetchFollowingFeedPage().nextOffset)
        assertEquals(2, client.requests.size)
    }

    @Test
    fun `feed cache is session scoped and serves stale model after refresh error`() = runTest {
        val cookieProvider = MutableCookieProvider("session-one")
        val httpClient = FeedHttpClient(
            ArrayDeque(
                listOf(
                    HttpResponse(200, feedBody("cursor-a")),
                    HttpResponse(503, """{"code":-1}"""),
                    HttpResponse(200, feedBody("cursor-b")),
                ),
            ),
        )
        val service = DynamicFeedService(
            cookieProvider = cookieProvider,
            httpClient = httpClient,
            timezoneOffsetMinutes = -480,
        )

        assertEquals("cursor-a", service.fetchFollowingFeedPage().nextOffset)
        assertEquals("cursor-a", service.fetchFollowingFeedPage().nextOffset)
        assertEquals(1, httpClient.requests.size)

        assertEquals("cursor-a", service.refreshFollowingFeedPage().nextOffset)
        assertEquals(2, httpClient.requests.size)

        cookieProvider.session = "session-two"
        assertEquals("cursor-b", service.fetchFollowingFeedPage().nextOffset)
        assertEquals(3, httpClient.requests.size)
        assertEquals(
            listOf(
                "SESSDATA=session-one",
                "SESSDATA=session-one",
                "SESSDATA=session-two",
            ),
            httpClient.requests.map { it.headers["Cookie"] },
        )
    }

    private class MutableCookieProvider(
        var session: String,
    ) : CookieProvider {
        override suspend fun loadCookies(): List<Cookie> =
            listOf(Cookie("SESSDATA", session, ".bilibili.com"))
    }

    private class FeedHttpClient(
        private val responses: ArrayDeque<HttpResponse>,
    ) : HttpClient {
        val requests = mutableListOf<HttpRequest>()

        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
            requests += HttpRequest(url, headers)
            return responses.removeFirst()
        }

        override suspend fun post(
            url: String,
            body: String,
            headers: Map<String, String>,
        ): HttpResponse = error("Unexpected POST: $url")
    }

    private companion object {
        fun feedBody(offset: String): String =
            """{"code":0,"data":{"items":[],"offset":"$offset"}}"""
    }
}
