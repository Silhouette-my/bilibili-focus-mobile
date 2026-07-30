package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class VideoActionServiceTests {
    @Test
    fun `watch history report matches bilibili api contract`() = runTest {
        val http = RecordingHttpClient()
        val service = VideoActionService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = listOf(
                    Cookie("SESSDATA", "session-token", ".bilibili.com"),
                    Cookie("bili_jct", "csrf-token", ".bilibili.com"),
                )
            },
            httpClient = http,
        )

        service.reportWatchHistory(aid = 42, cid = 4201, progressSeconds = 87)

        assertEquals("https://api.bilibili.com/x/v2/history/report", http.lastUrl)
        assertTrue("aid=42" in http.lastBody)
        assertTrue("cid=4201" in http.lastBody)
        assertTrue("progress=87" in http.lastBody)
        assertTrue("csrf=csrf-token" in http.lastBody)
        assertTrue(http.lastHeaders["Cookie"]?.contains("SESSDATA=session-token") == true)
        assertEquals("https://www.bilibili.com", http.lastHeaders["Origin"])
    }

    @Test
    fun `explicit history cookie snapshot is used without a second provider read`() = runTest {
        val http = RecordingHttpClient()
        val service = VideoActionService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> =
                    error("CookieProvider must not be read after scope validation")
            },
            httpClient = http,
        )
        val validatedCookies = listOf(
            Cookie("SESSDATA", "validated-session", ".bilibili.com"),
            Cookie("bili_jct", "validated-csrf", ".bilibili.com"),
        )

        service.reportWatchHistory(
            aid = 42,
            cid = 4201,
            progressSeconds = 12,
            cookies = validatedCookies,
        )

        assertTrue(http.lastHeaders["Cookie"]?.contains("SESSDATA=validated-session") == true)
        assertTrue(http.lastHeaders["Cookie"]?.contains("bili_jct=validated-csrf") == true)
        assertTrue("csrf=validated-csrf" in http.lastBody)
    }

    private class RecordingHttpClient : HttpClient {
        var lastUrl = ""
        var lastBody = ""
        var lastHeaders: Map<String, String> = emptyMap()

        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse =
            error("Unexpected GET: $url")

        override suspend fun post(
            url: String,
            body: String,
            headers: Map<String, String>,
        ): HttpResponse {
            lastUrl = url
            lastBody = body
            lastHeaders = headers
            return HttpResponse(200, """{"code":0,"data":{}}""")
        }
    }
}
