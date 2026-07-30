package org.bilibilifocus.core.service

import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.SearchQuery
import org.bilibilifocus.core.model.SearchResultFilter
import kotlin.test.Test
import kotlin.test.assertEquals

class SearchResultServicePortabilityTests {
    @Test
    fun `count abbreviations and duration padding remain deterministic`() {
        val page = service.decodePage(
            rawJson = """
                {
                  "code": 0,
                  "data": {
                    "page": 1,
                    "numPages": 1,
                    "result": [
                      {
                        "bvid": "BV1portable",
                        "arcurl": "https://www.bilibili.com/video/BV1portable",
                        "title": "跨平台格式",
                        "play": "12345",
                        "duration": "3661"
                      },
                      {
                        "bvid": "BV1whole",
                        "arcurl": "https://www.bilibili.com/video/BV1whole",
                        "title": "整数缩写",
                        "play": "100000000",
                        "duration": "61"
                      }
                    ]
                  }
                }
            """.trimIndent(),
            query = SearchQuery("跨平台"),
            filter = SearchResultFilter.VIDEO,
        )

        val items = page.sections.single().items
        assertEquals("1.2万播放", items[0].metadataText)
        assertEquals("1:01:01", items[0].badgeText)
        assertEquals("1亿播放", items[1].metadataText)
        assertEquals("01:01", items[1].badgeText)
    }

    private val service = SearchResultService(
        cookieProvider = object : CookieProvider {
            override suspend fun loadCookies(): List<Cookie> = emptyList()
        },
        httpClient = object : HttpClient {
            override suspend fun get(
                url: String,
                headers: Map<String, String>,
            ): HttpResponse = error("decode-only test must not use GET")

            override suspend fun post(
                url: String,
                body: String,
                headers: Map<String, String>,
            ): HttpResponse = error("decode-only test must not use POST")
        },
    )
}
