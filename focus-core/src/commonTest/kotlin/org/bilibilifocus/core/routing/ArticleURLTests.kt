package org.bilibilifocus.core.routing

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ArticleURLTests {
    @Test
    fun `accepted article variants normalize to canonical desktop URL`() {
        val variants = listOf(
            "https://www.bilibili.com/read/cv123?from=search",
            "https://m.bilibili.com/read/cv123",
            "https://www.bilibili.com/read/mobile?id=123&from=app",
            "bilibili://article/123",
            "bilibili://article/cv123",
        )

        variants.forEach { raw ->
            assertEquals(123, ArticleURL.extractCvid(raw), raw)
            assertEquals("https://www.bilibili.com/read/cv123", ArticleURL.canonicalURL(raw), raw)
        }
    }

    @Test
    fun `ordinary id queries and foreign read paths are not articles`() {
        listOf(
            "https://www.bilibili.com/video/BV1TEST?id=123",
            "https://www.bilibili.com/opus/456?id=123",
            "https://example.com/read/cv123",
            "https://www.bilibili.com/read/mobile?foo=1",
        ).forEach { assertNull(ArticleURL.extractCvid(it), it) }
    }
}
