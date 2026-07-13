package org.bilibilifocus.core.service

import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.DynamicCard
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DynamicArticleTests {
    @Test
    fun `feed endpoint requests opus style payload`() {
        val endpoint = service().buildEndpoint(offset = "next-page")

        assertTrue("features=itemOpusStyle" in endpoint)
        assertTrue("offset=next-page" in endpoint)
    }

    @Test
    fun `article dynamic prefers cvid over opus fallback`() {
        val service = DynamicFeedService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = emptyList()
            },
            httpClient = object : HttpClient {
                override suspend fun get(url: String, headers: Map<String, String>): HttpResponse = error("unused")
                override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse = error("unused")
            },
        )
        val payload = """
            {"code":0,"data":{"items":[{
              "id_str":"999","type":"DYNAMIC_TYPE_ARTICLE",
              "basic":{"jump_url":"https://www.bilibili.com/opus/999"},
              "modules":{"module_author":{"name":"作者"},"module_dynamic":{"major":{
                "type":"MAJOR_TYPE_ARTICLE",
                "article":{"id":"123","title":"专栏","jump_url":"https://www.bilibili.com/opus/999"}
              }}}
            }]}}
        """.trimIndent()

        val card = service.decodeFeedPage(payload).cards.single()

        assertEquals(DynamicCard.Kind.ARTICLE_LIKE, card.kind)
        assertEquals("https://www.bilibili.com/read/cv123", card.targetURL)
    }

    @Test
    fun `image dynamic inline link does not replace its own detail target`() {
        val payload = """
            {"code":0,"data":{"items":[{
              "id_str":"777","type":"DYNAMIC_TYPE_DRAW",
              "modules":{"module_author":{"name":"作者"},"module_dynamic":{"major":{
                "type":"MAJOR_TYPE_OPUS",
                "opus":{
                  "summary":{"text":"带话题的图文","rich_text_nodes":[
                    {"text":"#话题#","jump_url":"https://search.bilibili.com/all?keyword=topic"}
                  ]},
                  "pics":[{"url":"https://i0.hdslb.com/bfs/new_dyn/pic.jpg"}]
                }
              }}}
            }]}}
        """.trimIndent()

        val card = service().decodeFeedPage(payload).cards.single()

        assertEquals(DynamicCard.Kind.IMAGE, card.kind)
        assertEquals("https://www.bilibili.com/opus/777", card.targetURL)
    }

    @Test
    fun `image dynamic canonicalizes native detail scheme`() {
        val payload = """
            {"code":0,"data":{"items":[{
              "id_str":"888","type":"DYNAMIC_TYPE_DRAW",
              "basic":{"jump_url":"bilibili://following/detail/888"},
              "modules":{"module_author":{"name":"作者"},"module_dynamic":{"major":{
                "type":"MAJOR_TYPE_DRAW",
                "draw":{"items":[{"src":"https://i0.hdslb.com/bfs/new_dyn/pic.jpg"}]}
              }}}
            }]}}
        """.trimIndent()

        val card = service().decodeFeedPage(payload).cards.single()

        assertEquals("https://www.bilibili.com/opus/888", card.targetURL)
    }

    @Test
    fun `image dynamic builds complete text from opus rich text nodes`() {
        val payload = """
            {"code":0,"data":{"items":[{
              "id_str":"889","type":"DYNAMIC_TYPE_DRAW",
              "modules":{"module_author":{"name":"作者"},"module_dynamic":{"major":{
                "type":"MAJOR_TYPE_OPUS",
                "opus":{
                  "summary":{"rich_text_nodes":[
                    {"text":"第一段"},
                    {"text":"[doge]","emoji":{"icon_url":"https://i0.hdslb.com/bfs/emote/doge.png"}},
                    {"text":"\n第二段完整文本"}
                  ]},
                  "pics":[{"url":"https://i0.hdslb.com/bfs/new_dyn/pic.jpg"}]
                }
              }}}
            }]}}
        """.trimIndent()

        val card = service().decodeFeedPage(payload).cards.single()

        assertEquals("第一段[doge]\n第二段完整文本", card.text)
        assertEquals(1, card.coverURLs.size)
    }

    private fun service() = DynamicFeedService(
        cookieProvider = object : CookieProvider {
            override suspend fun loadCookies(): List<Cookie> = emptyList()
        },
        httpClient = object : HttpClient {
            override suspend fun get(url: String, headers: Map<String, String>): HttpResponse = error("unused")
            override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse = error("unused")
        },
    )
}
