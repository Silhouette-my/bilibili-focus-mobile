package org.bilibilifocus.core.service

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WatchLaterServiceTests {
    @Test
    fun `list preserves long identifiers and scopes cookies to endpoint`() = runTest {
        val http = RecordingHttpClient(listResponse = LIST_PAYLOAD)
        val service = WatchLaterService(ScopedCookieProvider, http)

        val result = service.fetchList()

        assertEquals(1, result.totalCount)
        val item = result.items.single()
        assertEquals(4_294_967_296L, item.aid)
        assertEquals(8_589_934_592L, item.cid)
        assertEquals("BV1xx411c7mD", item.bvid)
        assertEquals("https://i0.hdslb.com/cover.jpg", item.coverURL)
        assertEquals(9_223_372_036L, item.viewCount)
        assertEquals("https://www.bilibili.com/video/BV1xx411c7mD/", item.targetURL)

        val request = http.getRequests.single()
        assertEquals(BiliApiContractCatalog.require("toview.info.list").url, request.url)
        assertTrue(request.headers["Cookie"]?.contains("SESSDATA=session-token") == true)
        assertTrue(request.headers["Cookie"]?.contains("bili_jct=csrf-token") == true)
        assertFalse(request.headers["Cookie"]?.contains("wrong-domain") == true)
        assertFalse(request.headers["Cookie"]?.contains("wrong-path") == true)
    }

    @Test
    fun `mutations use catalog endpoints csrf and long aid forms`() = runTest {
        val http = RecordingHttpClient()
        val service = WatchLaterService(ScopedCookieProvider, http)
        val aid = 4_294_967_296L

        service.add(aid)
        service.remove(aid)
        service.deleteViewed()
        service.clear()

        assertEquals(
            listOf(
                BiliApiContractCatalog.require("toview.operate.add").url,
                BiliApiContractCatalog.require("toview.operate.del").url,
                BiliApiContractCatalog.require("toview.operate.del").url,
                BiliApiContractCatalog.require("toview.operate.clear").url,
            ),
            http.postRequests.map { it.url },
        )
        assertTrue("aid=4294967296" in http.postRequests[0].body)
        assertTrue("viewed=false" in http.postRequests[1].body)
        assertTrue("viewed=true" in http.postRequests[2].body)
        http.postRequests.forEach { request ->
            assertTrue("csrf=csrf-token" in request.body)
            assertTrue("csrf_token=csrf-token" in request.body)
            assertEquals(
                "application/x-www-form-urlencoded; charset=UTF-8",
                request.headers["Content-Type"],
            )
            assertEquals("https://www.bilibili.com", request.headers["Origin"])
            assertFalse(request.headers["Cookie"]?.contains("wrong-domain") == true)
        }
    }

    @Test
    fun `mutation fails before network when matching csrf is absent`() = runTest {
        val http = RecordingHttpClient()
        val service = WatchLaterService(
            cookieProvider = FixtureCookieProvider(
                listOf(Cookie("SESSDATA", "session-token", ".bilibili.com")),
            ),
            httpClient = http,
        )

        val error = assertFailsWith<WatchLaterService.ServiceError> {
            service.add(42)
        }

        assertEquals(WatchLaterService.ServiceError.MissingCsrf, error)
        assertTrue(http.postRequests.isEmpty())
    }

    @Test
    fun `cancellation propagates without conversion`() = runTest {
        val service = WatchLaterService(
            cookieProvider = ScopedCookieProvider,
            httpClient = object : HttpClient {
                override suspend fun get(
                    url: String,
                    headers: Map<String, String>,
                ): HttpResponse = throw CancellationException("cancel watch-later")

                override suspend fun post(
                    url: String,
                    body: String,
                    headers: Map<String, String>,
                ): HttpResponse = error("Unexpected POST")
            },
        )

        assertFailsWith<CancellationException> {
            service.fetchList()
        }
    }

    private data class RecordedRequest(
        val url: String,
        val body: String = "",
        val headers: Map<String, String>,
    )

    private class RecordingHttpClient(
        private val listResponse: String = """{"code":0,"data":{}}""",
    ) : HttpClient {
        val getRequests = mutableListOf<RecordedRequest>()
        val postRequests = mutableListOf<RecordedRequest>()

        override suspend fun get(
            url: String,
            headers: Map<String, String>,
        ): HttpResponse {
            getRequests += RecordedRequest(url = url, headers = headers)
            return HttpResponse(200, listResponse)
        }

        override suspend fun post(
            url: String,
            body: String,
            headers: Map<String, String>,
        ): HttpResponse {
            postRequests += RecordedRequest(url = url, body = body, headers = headers)
            return HttpResponse(200, """{"code":0,"data":{}}""")
        }
    }

    private class FixtureCookieProvider(
        private val cookies: List<Cookie>,
    ) : CookieProvider {
        override suspend fun loadCookies(): List<Cookie> = cookies
    }

    private companion object {
        val ScopedCookieProvider = FixtureCookieProvider(
            listOf(
                Cookie("bili_jct", "wrong-domain", ".example.com"),
                Cookie("path-only", "wrong-path", ".bilibili.com", path = "/account"),
                Cookie("SESSDATA", "session-token", ".bilibili.com", secure = true),
                Cookie("bili_jct", "csrf-token", ".bilibili.com", secure = true),
            ),
        )

        val LIST_PAYLOAD = """
            {
              "code": 0,
              "message": "0",
              "data": {
                "count": 1,
                "list": [{
                  "aid": 4294967296,
                  "bvid": "BV1xx411c7mD",
                  "cid": 8589934592,
                  "title": "稍后再看的视频",
                  "pic": "//i0.hdslb.com/cover.jpg",
                  "duration": 600,
                  "progress": 87,
                  "add_at": 1700000000,
                  "pubdate": 1690000000,
                  "owner": {
                    "mid": 4294967297,
                    "name": "UP 主",
                    "face": "//i0.hdslb.com/avatar.jpg"
                  },
                  "stat": {
                    "view": 9223372036
                  }
                }]
              }
            }
        """.trimIndent()
    }
}
