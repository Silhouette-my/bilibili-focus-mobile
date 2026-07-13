package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.ArticleBlock
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

class ArticleServiceTests {
    @Test
    fun `fetch article uses complete endpoint once and maps metadata plus modern body`() = runTest {
        val client = ArticleFixtureHttpClient()
        val service = ArticleService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = listOf(Cookie("SESSDATA", "fixture", ".bilibili.com"))
            },
            httpClient = client,
        )

        val article = service.fetchArticle(123)

        assertEquals(1, client.requestedURLs.size)
        assertEquals("https://api.bilibili.com/x/article/view?id=123&mobi_app=pc&from=web", client.requestedURLs.single())
        assertEquals("完整专栏", article.title)
        assertEquals("作者", article.author.name)
        assertEquals("https://i0.hdslb.com/avatar.jpg", article.author.avatarURL)
        assertEquals(88, article.stats.views)
        assertEquals(listOf("测试", "KMP", "开发"), article.tags)
        assertEquals("https://www.bilibili.com/read/cv123", article.originalURL)
        assertIs<ArticleBlock.Paragraph>(article.blocks.single())
        assertTrue(client.lastHeaders["Cookie"]?.contains("SESSDATA=fixture") == true)
        assertEquals(article.originalURL, client.lastHeaders["Referer"])
    }

    @Test
    fun `empty or unsupported body is reported as failure instead of success`() = runTest {
        val service = ArticleService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = emptyList()
            },
            httpClient = ArticleFixtureHttpClient(content = ""),
        )

        assertFailsWith<ArticleService.ServiceError.EmptyContent> { service.fetchArticle(123) }
    }

    private class ArticleFixtureHttpClient(
        private val content: String = "{\"ops\":[{\"insert\":\"正文\\n\"}]}",
    ) : HttpClient {
        val requestedURLs = mutableListOf<String>()
        var lastHeaders: Map<String, String> = emptyMap()

        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
            requestedURLs += url
            lastHeaders = headers
            val escapedContent = content
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
            return HttpResponse(
                200,
                """
                {"code":0,"data":{
                  "title":"完整专栏","publish_time":1700000000,
                  "author":{"mid":42,"name":"作者","face":"//i0.hdslb.com/avatar.jpg"},
                  "stats":{"view":88,"like":7,"coin":6,"favorite":5,"reply":4},
                  "banner_url":"//i0.hdslb.com/banner.jpg",
                  "tags":[{"name":"测试"}],"keywords":"KMP, 开发",
                  "content":"$escapedContent"
                }}
                """.trimIndent(),
            )
        }

        override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse =
            error("Unexpected POST: $url")
    }
}
