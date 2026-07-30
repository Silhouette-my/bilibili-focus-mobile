package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import kotlin.test.Test
import kotlin.test.assertEquals

class PlayUrlServiceTests {
    @Test
    fun `cross-origin media does not receive bilibili session cookies`() = runTest {
        val client = PlayUrlHttpClient("https://media.example/video.m4s")
        val service = PlayUrlService(
            cookieProvider = FixtureCookieProvider,
            httpClient = client,
        )

        val result = service.fetchPlayUrl("BV1xx411c7mD", 4201)

        assertEquals("https://media.example/video.m4s", result.videoUrl)
        @Suppress("DEPRECATION")
        assertEquals("", result.cookie)
        assertEquals(
            listOf("SESSDATA=session-token", "SESSDATA=session-token"),
            client.requestHeaders.map { it["Cookie"] },
        )
    }

    @Test
    fun `same-domain media also omits login cookies to close redirect inheritance`() = runTest {
        val service = PlayUrlService(
            cookieProvider = FixtureCookieProvider,
            httpClient = PlayUrlHttpClient("https://api.bilibili.com/video/stream.m4s"),
        )

        val result = service.fetchPlayUrl("BV1xx411c7mD", 4201)

        @Suppress("DEPRECATION")
        assertEquals("", result.cookie)
    }

    private data object FixtureCookieProvider : CookieProvider {
        override suspend fun loadCookies(): List<Cookie> = listOf(
            Cookie("SESSDATA", "session-token", ".bilibili.com"),
        )
    }

    private class PlayUrlHttpClient(
        private val mediaUrl: String,
    ) : HttpClient {
        val requestHeaders = mutableListOf<Map<String, String>>()

        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
            requestHeaders += headers
            if (url.contains("/x/web-interface/nav")) {
                return HttpResponse(
                    200,
                    """
                    {"code":0,"data":{"wbi_img":{
                      "img_url":"https://i0.hdslb.com/abcdefghijklmnopqrstuvwxyz012345.png",
                      "sub_url":"https://i0.hdslb.com/ABCDEFGHIJKLMNOPQRSTUVWXYZ012345.png"
                    }}}
                    """.trimIndent(),
                )
            }
            if (url.contains("/x/player/wbi/playurl")) {
                return HttpResponse(
                    200,
                    """
                    {"code":0,"data":{"dash":{
                      "video":[{"codecid":7,"baseUrl":"$mediaUrl","backupUrl":[]}],
                      "audio":[]
                    }}}
                    """.trimIndent(),
                )
            }
            error("Unexpected GET: $url")
        }

        override suspend fun post(
            url: String,
            body: String,
            headers: Map<String, String>,
        ): HttpResponse = error("Unexpected POST: $url")
    }
}
