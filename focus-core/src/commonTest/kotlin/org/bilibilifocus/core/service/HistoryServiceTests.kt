package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class HistoryServiceTests {
    @Test
    fun `history keeps long timestamps progress and cursors`() = runTest {
        val service = HistoryService(
            cookieProvider = EmptyCookieProvider,
            httpClient = FixtureHttpClient,
        )

        val page = service.fetchHistory()

        assertEquals(3_000_000_001L, page.items.single().viewAt)
        assertEquals(3_000_000_002L, page.items.single().progress)
        assertEquals(3_000_000_003L, page.items.single().duration)
        assertEquals(9_223_372_036_854_770_000L, page.nextMax)
        assertEquals(3_000_000_004L, page.nextViewAt)
    }

    @Test
    fun `history preserves opaque business cursor bytes`() = runTest {
        var requestedURL = ""
        val client = object : HttpClient {
            override suspend fun get(
                url: String,
                headers: Map<String, String>,
            ): HttpResponse {
                requestedURL = url
                return FixtureHttpClient.get(url, headers)
            }

            override suspend fun post(
                url: String,
                body: String,
                headers: Map<String, String>,
            ): HttpResponse = error("Unexpected POST: $url")
        }
        HistoryService(EmptyCookieProvider, client).fetchHistory(
            business = "archive+/= 中文",
        )

        assertTrue("business=archive%2B%2F%3D%20%E4%B8%AD%E6%96%87" in requestedURL)
    }

    private data object EmptyCookieProvider : CookieProvider {
        override suspend fun loadCookies(): List<Cookie> = emptyList()
    }

    private data object FixtureHttpClient : HttpClient {
        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse =
            HttpResponse(
                200,
                """
                {
                  "code":0,
                  "data":{
                    "list":[{
                      "title":"测试视频",
                      "cover":"https://i0.hdslb.com/video.jpg",
                      "author_name":"测试UP",
                      "view_at":3000000001,
                      "progress":"3000000002",
                      "duration":3000000003,
                      "history":{"bvid":"BV1TEST00001"}
                    }],
                    "cursor":{
                      "max":"9223372036854770000",
                      "view_at":3000000004,
                      "business":"archive"
                    }
                  }
                }
                """.trimIndent(),
            )

        override suspend fun post(
            url: String,
            body: String,
            headers: Map<String, String>,
        ): HttpResponse = error("Unexpected POST: $url")
    }
}
