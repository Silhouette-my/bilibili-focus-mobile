package org.bilibilifocus.core.cookie

import kotlin.test.Test
import kotlin.test.assertEquals

class CookieRequestPolicyTests {
    @Test
    fun `domain cookies match subdomains without matching deceptive suffixes`() {
        val cookies = listOf(
            Cookie("session", "domain", ".bilibili.com"),
            Cookie("host", "only", "api.bilibili.com"),
        )

        assertEquals(
            "session=domain; host=only",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://api.bilibili.com/x/player/playurl",
                nowEpochSeconds = 1_000,
            ),
        )
        assertEquals(
            "session=domain",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://www.bilibili.com/video/BV1",
                nowEpochSeconds = 1_000,
            ),
        )
        assertEquals(
            "",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://bilibili.com.attacker.example/video",
                nowEpochSeconds = 1_000,
            ),
        )
        assertEquals(
            "",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://evilbilibili.com/video",
                nowEpochSeconds = 1_000,
            ),
        )
    }

    @Test
    fun `path matching honors segment boundaries and orders longest path first`() {
        val cookies = listOf(
            Cookie("root", "1", ".bilibili.com", path = "/"),
            Cookie("video", "2", ".bilibili.com", path = "/video"),
            Cookie("episode", "3", ".bilibili.com", path = "/video/episode"),
        )

        assertEquals(
            "episode=3; video=2; root=1",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://www.bilibili.com/video/episode/1",
                nowEpochSeconds = 1_000,
            ),
        )
        assertEquals(
            "root=1",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://www.bilibili.com/videotest",
                nowEpochSeconds = 1_000,
            ),
        )
    }

    @Test
    fun `secure and expired cookies are excluded`() {
        val cookies = listOf(
            Cookie("secure", "1", ".bilibili.com", secure = true),
            Cookie("expired", "2", ".bilibili.com", expiresAtEpochSeconds = 999),
            Cookie("valid", "3", ".bilibili.com", expiresAtEpochSeconds = 1_001),
        )

        assertEquals(
            "valid=3",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "http://www.bilibili.com/video",
                nowEpochSeconds = 1_000,
            ),
        )
        assertEquals(
            "secure=1; valid=3",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://www.bilibili.com/video",
                nowEpochSeconds = 1_000,
            ),
        )
    }

    @Test
    fun `attach replaces stale cookie headers and clears them for cross origin targets`() {
        val provider = object : CookieProvider {
            override suspend fun loadCookies(): List<Cookie> = emptyList()
        }
        val headers = provider.attachCookies(
            requestHeaders = mapOf("cookie" to "stale=credential", "Accept" to "*/*"),
            cookies = listOf(Cookie("session", "domain", ".bilibili.com")),
            targetUrl = "https://media.example/video.m4s",
            nowEpochSeconds = 1_000,
        )

        assertEquals(mapOf("Accept" to "*/*"), headers)
    }
}
