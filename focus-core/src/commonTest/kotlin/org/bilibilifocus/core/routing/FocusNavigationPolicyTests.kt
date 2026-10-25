package org.bilibilifocus.core.routing

import kotlin.test.Test
import kotlin.test.assertEquals

class FocusNavigationPolicyTests {

    @Test
    fun `download blocking respects domain boundaries`() {
        val policy = FocusNavigationPolicy()
        for (host in listOf("bilibili.com", "www.bilibili.com", "static.hdslb.com")) {
            assertEquals(FocusNavigationPolicy.Decision.Cancel, policy.decision("https://$host/download"))
        }
        for (host in listOf("notbilibili.com", "bilibili.com.example.org", "nothdslb.com")) {
            assertEquals(FocusNavigationPolicy.Decision.Allow, policy.decision("https://$host/download"))
        }
    }

    @Test
    fun `canonicalize dynamic detail to desktop opus page`() {
        val url = "https://t.bilibili.com/123456789"
        val result = FocusNavigationPolicy.canonicalWebURL(url)
        assertEquals("https://www.bilibili.com/opus/123456789", result)
    }

    @Test
    fun `canonicalize mobile opus page to desktop host`() {
        val url = "https://m.bilibili.com/opus/987654321"
        val result = FocusNavigationPolicy.canonicalWebURL(url)
        assertEquals("https://www.bilibili.com/opus/987654321", result)
    }

    @Test
    fun `block bilibili custom scheme`() {
        val policy = FocusNavigationPolicy()
        val decision = policy.decision("bilibili://video/12345")
        assert(decision is FocusNavigationPolicy.Decision.Cancel)
    }

    @Test
    fun `normalize video page to www host`() {
        val url = "https://m.bilibili.com/video/BV1xx411c7mD"
        val result = FocusNavigationPolicy.canonicalWebURL(url)
        assertEquals("https://www.bilibili.com/video/BV1xx411c7mD", result)
    }

    @Test
    fun `preserve episode cid when canonicalizing player URL`() {
        val url = "https://www.bilibili.com/blackboard/html5player.html" +
            "?bvid=BV1xx411c7mD&cid=3000000088&start_progress=123&foo=bar"
        val result = FocusNavigationPolicy.canonicalWebURL(url)
        assertEquals(
            "https://www.bilibili.com/video/BV1xx411c7mD?cid=3000000088&start_progress=123",
            result,
        )
    }

    @Test
    fun `block openapp URL`() {
        val policy = FocusNavigationPolicy()
        val decision = policy.decision("https://www.bilibili.com/video/BV1xx/?openapp=1")
        assertEquals(FocusNavigationPolicy.Decision.Cancel::class, decision::class)
    }
}
