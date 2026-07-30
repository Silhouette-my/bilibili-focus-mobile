package org.bilibilifocus.android

import org.bilibilifocus.core.cookie.CookieRequestPolicy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AndroidCookieProviderTests {
    @Test
    fun `snapshot keeps login cookies for each Bilibili API origin only`() {
        val cookies = buildAndroidCookieSnapshot(
            listOf(
                AndroidCookieHeaderSnapshot(
                    url = "https://api.bilibili.com/",
                    cookieHeader = "SESSDATA=shared-session; bili_jct=api-csrf",
                ),
                AndroidCookieHeaderSnapshot(
                    url = "https://t.bilibili.com/",
                    cookieHeader = "SESSDATA=shared-session; bili_jct=dynamic-csrf",
                ),
                AndroidCookieHeaderSnapshot(
                    url = "https://evilbilibili.com/",
                    cookieHeader = "SESSDATA=attacker-session; bili_jct=attacker-csrf",
                ),
            ),
        )

        assertEquals(
            setOf("api.bilibili.com", "t.bilibili.com"),
            cookies.filter { it.name == "SESSDATA" }.mapTo(mutableSetOf(), { it.domain }),
        )
        assertEquals(
            "SESSDATA=shared-session; bili_jct=api-csrf",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all",
                nowEpochSeconds = 1_000,
            ),
        )
        assertEquals(
            "SESSDATA=shared-session; bili_jct=dynamic-csrf",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://t.bilibili.com/opus/123",
                nowEpochSeconds = 1_000,
            ),
        )
        assertEquals(
            "",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://evilbilibili.com/x",
                nowEpochSeconds = 1_000,
            ),
        )
    }

    @Test
    fun `snapshot deduplicates only identical scope and preserves same-name rules`() {
        val cookies = buildAndroidCookieSnapshot(
            listOf(
                AndroidCookieHeaderSnapshot(
                    url = "https://api.bilibili.com/",
                    cookieHeader = "SID=root-value; SID=second-root-value",
                ),
                AndroidCookieHeaderSnapshot(
                    url = "https://api.bilibili.com/x",
                    cookieHeader = "SID=path-value",
                ),
                AndroidCookieHeaderSnapshot(
                    url = "https://api.bilibili.com/x",
                    cookieHeader = "SID=path-value",
                ),
                AndroidCookieHeaderSnapshot(
                    url = "https://t.bilibili.com/",
                    cookieHeader = "SID=dynamic-value",
                ),
            ),
        )

        assertEquals(4, cookies.count { it.name == "SID" })
        assertEquals(
            "SID=path-value; SID=root-value; SID=second-root-value",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://api.bilibili.com/x/child",
                nowEpochSeconds = 1_000,
            ),
        )
        assertEquals(
            "SID=root-value; SID=second-root-value",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://api.bilibili.com/other",
                nowEpochSeconds = 1_000,
            ),
        )
        assertEquals(
            "SID=dynamic-value",
            CookieRequestPolicy.cookieHeader(
                cookies,
                "https://t.bilibili.com/",
                nowEpochSeconds = 1_000,
            ),
        )
    }

    @Test
    fun `trusted URL check rejects deceptive hosts and non-web schemes`() {
        assertTrue(isTrustedBilibiliCookieUrl("https://bilibili.com/"))
        assertTrue(isTrustedBilibiliCookieUrl("https://api.bilibili.com/x"))
        assertTrue(isTrustedBilibiliCookieUrl("https://t.bilibili.com/"))

        assertFalse(isTrustedBilibiliCookieUrl("https://evilbilibili.com/"))
        assertFalse(isTrustedBilibiliCookieUrl("https://bilibili.com.attacker.example/"))
        assertFalse(isTrustedBilibiliCookieUrl("https://api.bilibili.com@attacker.example/"))
        assertFalse(isTrustedBilibiliCookieUrl("javascript:https://api.bilibili.com/"))
    }
}
