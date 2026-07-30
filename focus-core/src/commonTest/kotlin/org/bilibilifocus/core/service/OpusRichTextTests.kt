package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.OpusBlock
import org.bilibilifocus.core.model.RichTextRun
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class OpusRichTextTests {
    @Test
    fun `dynamic detail fallback keeps emoji node order dimensions animation and images`() = runTest {
        val service = OpusService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = emptyList()
            },
            httpClient = object : HttpClient {
                override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
                    val body = when {
                        url.contains("/opus/detail") ->
                            """{"code":0,"data":{"item":{"basic":{"comment_id_str":"123"},"modules":{"module_author":{"name":"作者"}}}}}"""
                        url.contains("/x/web-interface/nav") ->
                            """{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/abcdefghijklmnopqrstuvwxyz012345.png","sub_url":"https://i0.hdslb.com/ABCDEFGHIJKLMNOPQRSTUVWXYZ012345.png"}}}"""
                        else -> """
                        {"code":0,"data":{"item":{"modules":{
                          "module_author":{"name":"作者","mid":42,"face":"//i0.hdslb.com/a.jpg"},
                          "module_dynamic":{
                            "desc":{"text":"文字[doge]结尾","rich_text_nodes":[
                              {"text":"文字"},
                              {"orig_text":"[doge]","emoji":{"icon_url":"//i0.hdslb.com/doge.gif","meta":{"size":3}}},
                              {"text":"结尾","jump_url":"https://www.bilibili.com/read/cv1"}
                            ]},
                            "major":{"draw":{"items":[{"src":"//i0.hdslb.com/pic.jpg","width":800,"height":600}]}}
                          }
                        }}}}
                        """.trimIndent()
                    }
                    return HttpResponse(200, body)
                }

                override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse =
                    error("Unexpected POST: $url")
            },
        )

        val detail = service.fetchOpusDetail("123")
        val blocks = detail.paragraphs.single().blocks
        val runs = assertIs<OpusBlock.Text>(blocks[0]).nodes

        assertEquals(listOf("文字", "[doge]", "结尾"), runs.map {
            when (it) {
                is RichTextRun.Text -> it.text
                is RichTextRun.Emote -> it.alt
                is RichTextRun.Resource -> it.label
            }
        })
        val emote = assertIs<RichTextRun.Emote>(runs[1])
        assertEquals(3, emote.width)
        assertEquals(3, emote.height)
        assertTrue(emote.animated)
        assertEquals("https://www.bilibili.com/read/cv1", assertIs<RichTextRun.Text>(runs[2]).linkUrl)
        assertEquals("https://i0.hdslb.com/pic.jpg", assertIs<OpusBlock.Image>(blocks[1]).pics.single().url)
    }
}
