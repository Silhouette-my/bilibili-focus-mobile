package org.bilibilifocus.core.model

import org.bilibilifocus.core.routing.urlEncode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SearchQueryTests {

    @Test
    fun `keyword is trimmed`() {
        val query = SearchQuery("  原神 测试  ")
        assertEquals("原神 测试", query.keyword)
    }

    @Test
    fun `result URL encodes keyword`() {
        val query = SearchQuery("原神 测试")
        assertTrue(query.resultURL.startsWith("https://search.bilibili.com/all?keyword="))
        assertTrue(query.resultURL.contains("%")) // should be URL-encoded
    }

    @Test
    fun `urlEncode handles Chinese characters`() {
        val encoded = urlEncode("测试")
        assertTrue(encoded.all { it == '%' || it in '0'..'9' || it in 'A'..'F' })
    }
}
