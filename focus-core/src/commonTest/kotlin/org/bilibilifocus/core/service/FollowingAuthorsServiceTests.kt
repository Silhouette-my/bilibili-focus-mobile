package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.CancellationException
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith

class FollowingAuthorsServiceTests {
    @Test
    fun `cancelled attention request does not start fallback pagination`() = runTest {
        var requests = 0
        val service = FollowingAuthorsService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = emptyList()
            },
            httpClient = object : HttpClient {
                override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
                    requests += 1
                    return when {
                        url.contains("/x/web-interface/nav") -> HttpResponse(200, """{"code":0,"data":{"isLogin":true,"mid":99}}""")
                        url.contains("/x/web-interface/attentions") -> throw CancellationException("screen disposed")
                        else -> HttpResponse(200, """{"code":0,"data":{"total":0,"list":[]}}""")
                    }
                }
                override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse = error("Unexpected POST")
            },
        )
        assertFailsWith<CancellationException> { service.fetchFollowingAuthors() }
        assertEquals(2, requests)
    }

    @Test
    fun `following list merges attention authors and reads every page`() = runTest {
        val httpClient = FollowingFixtureHttpClient()
        val service = FollowingAuthorsService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = listOf(
                    Cookie("SESSDATA", "fixture", ".bilibili.com"),
                )
            },
            httpClient = httpClient,
            pageSize = 2,
        )

        val authors = service.fetchFollowingAuthors()

        assertEquals(listOf(1L, 2L, 3L), authors.map { it.mid })
        assertEquals("https://i0.hdslb.com/three.jpg", authors.last().avatarURL)
        assertTrue(httpClient.requestedUrls.any { "pn=2" in it })
    }

    private class FollowingFixtureHttpClient : HttpClient {
        val requestedUrls = mutableListOf<String>()

        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
            requestedUrls += url
            assertTrue(headers["Cookie"]?.contains("SESSDATA=fixture") == true)
            val body = when {
                url.contains("/x/web-interface/nav") -> """
                    {"code":0,"data":{"isLogin":true,"mid":99}}
                """.trimIndent()
                url.contains("/x/web-interface/attentions") -> """
                    {"code":0,"data":{"list":[
                      {"mid":1,"uname":"一号","face":"//i0.hdslb.com/one.jpg"}
                    ]}}
                """.trimIndent()
                url.contains("pn=1") -> """
                    {"code":0,"data":{"total":3,"list":[
                      {"mid":1,"uname":"一号","face":"//i0.hdslb.com/one.jpg"},
                      {"mid":2,"uname":"二号","face":"//i0.hdslb.com/two.jpg"}
                    ]}}
                """.trimIndent()
                url.contains("pn=2") -> """
                    {"code":0,"data":{"total":3,"list":[
                      {"mid":3,"uname":"三号","face":"//i0.hdslb.com/three.jpg"}
                    ]}}
                """.trimIndent()
                else -> error("Unexpected URL: $url")
            }
            return HttpResponse(200, body)
        }

        override suspend fun post(
            url: String,
            body: String,
            headers: Map<String, String>,
        ): HttpResponse = error("Unexpected POST: $url")
    }
}
