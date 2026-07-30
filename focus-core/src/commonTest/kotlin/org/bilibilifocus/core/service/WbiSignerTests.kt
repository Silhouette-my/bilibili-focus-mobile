package org.bilibilifocus.core.service

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

class WbiSignerTests {
    @Test
    fun `signing sanitizes and RFC3986 encodes Chinese values`() {
        val query = signWbiQuery(
            parameters = mapOf(
                "w_rid" to "stale",
                "wts" to "stale",
                "page" to "2",
                "keyword" to "哔哩 哔哩!'()*",
            ),
            mixinKey = "ea1db124af3c7062474693fa704f4ff8",
            wts = 1_700_000_000,
        )

        assertEquals(
            "keyword=%E5%93%94%E5%93%A9%20%E5%93%94%E5%93%A9" +
                "&page=2&wts=1700000000&w_rid=42c93e2a66ea1e27ca73e9884bd0d209",
            query,
        )
    }

    @Test
    fun `api minus 403 invalidates cached key and retries`() = runTest {
        val httpClient = NavHttpClient()
        val signer = WbiSigner(
            cookieProvider = EmptyCookieProvider,
            httpClient = httpClient,
            clock = { 1_700_000_000 },
        )
        val signedQueries = mutableListOf<String>()
        var attempts = 0

        val result = signer.execute(mapOf("keyword" to "测试")) { signedQuery ->
            signedQueries += signedQuery
            attempts += 1
            WbiRequestResult(
                value = attempts,
                httpStatusCode = 200,
                apiCode = if (attempts == 1) -403 else 0,
            )
        }

        assertEquals(2, result.value)
        assertEquals(2, attempts)
        assertEquals(2, httpClient.navRequests)
        assertNotEquals(signedQueries[0], signedQueries[1])
    }

    @Test
    fun `concurrent signing shares one nav key load`() = runTest {
        val httpClient = NavHttpClient()
        val signer = WbiSigner(
            cookieProvider = EmptyCookieProvider,
            httpClient = httpClient,
            clock = { 1_700_000_000 },
        )

        val queries = coroutineScope {
            List(20) { index ->
                async { signer.signedQuery(mapOf("index" to index.toString())) }
            }.awaitAll()
        }

        assertEquals(20, queries.size)
        assertEquals(1, httpClient.navRequests)
    }

    private data object EmptyCookieProvider : CookieProvider {
        override suspend fun loadCookies(): List<Cookie> = emptyList()
    }

    private class NavHttpClient : HttpClient {
        var navRequests = 0

        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
            require(url == "https://api.bilibili.com/x/web-interface/nav")
            navRequests += 1
            val prefix = if (navRequests == 1) "abcdefghijklmnopqrstuvwxyz012345" else "012345abcdefghijklmnopqrstuvwxyz"
            val suffix = if (navRequests == 1) "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345" else "012345ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            return HttpResponse(
                statusCode = 200,
                body = """
                    {"code":0,"data":{"wbi_img":{
                      "img_url":"https://i0.hdslb.com/$prefix.png",
                      "sub_url":"https://i0.hdslb.com/$suffix.png"
                    }}}
                """.trimIndent(),
            )
        }

        override suspend fun post(
            url: String,
            body: String,
            headers: Map<String, String>,
        ): HttpResponse = error("Unexpected POST: $url")
    }
}
