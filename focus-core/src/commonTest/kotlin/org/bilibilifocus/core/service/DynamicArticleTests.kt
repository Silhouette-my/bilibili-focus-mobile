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
    fun `feed endpoint preserves opaque cursor bytes`() {
        val endpoint = service().buildEndpoint(offset = "seed+/= 中文")

        assertTrue("offset=seed%2B%2F%3D%20%E4%B8%AD%E6%96%87" in endpoint)
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

    @kotlin.test.Test
    fun `decodes forwarded video dynamic with quoted card and clears outer videoURL`() = kotlinx.coroutines.test.runTest {
        val payload = """
            {
              "code": 0,
              "data": {
                "has_more": false,
                "offset": "",
                "items": [
                  {
                    "id_str": "9001",
                    "type": "DYNAMIC_TYPE_FORWARD",
                    "visible": true,
                    "modules": {
                      "module_author": {
                        "name": "转发作者",
                        "pub_time": "1小时前"
                      },
                      "module_dynamic": {
                        "desc": {
                          "text": "转发推荐"
                        }
                      }
                    },
                    "orig": {
                      "id_str": "8001",
                      "type": "DYNAMIC_TYPE_AV",
                      "modules": {
                        "module_author": {
                          "name": "原视频作者",
                          "pub_time": "2小时前"
                        },
                        "module_dynamic": {
                          "major": {
                            "type": "MAJOR_TYPE_ARCHIVE",
                            "archive": {
                              "bvid": "BV1xx411c7mD",
                              "title": "原视频标题",
                              "desc": "原视频简介",
                              "cover": "https://i0.hdslb.com/bfs/archive/orig.jpg",
                              "jump_url": "//www.bilibili.com/video/BV1xx411c7mD"
                            }
                          }
                        }
                      }
                    }
                  }
                ]
              }
            }
        """.trimIndent()

        val card = service().decodeFeedPage(payload).cards.single()

        assertEquals("https://www.bilibili.com/opus/9001", card.targetURL)
        assertEquals(null, card.videoURL)
        val quoted = kotlin.test.assertNotNull(card.quotedCard)
        assertEquals("8001", quoted.id)
        assertEquals("原视频作者", quoted.author.name)
        assertEquals("原视频标题", quoted.title)
        assertEquals("https://www.bilibili.com/video/BV1xx411c7mD", quoted.videoURL)
        assertEquals(listOf("https://i0.hdslb.com/bfs/archive/orig.jpg"), quoted.coverURLs)
    }

    @kotlin.test.Test
    fun `decodes forwarded opus dynamic and deleted orig tip and additional ugc`() = kotlinx.coroutines.test.runTest {
        val payload = """
            {
              "code": 0,
              "data": {
                "has_more": false,
                "offset": "",
                "items": [
                  {
                    "id_str": "9002",
                    "type": "DYNAMIC_TYPE_FORWARD",
                    "visible": true,
                    "modules": {
                      "module_author": { "name": "转发甲", "pub_time": "刚刚" },
                      "module_dynamic": { "desc": { "text": "看看原图文" } }
                    },
                    "orig": {
                      "id_str": "8002",
                      "type": "DYNAMIC_TYPE_DRAW",
                      "modules": {
                        "module_author": { "name": "原画师", "pub_time": "昨天" },
                        "module_dynamic": {
                          "major": {
                            "type": "MAJOR_TYPE_OPUS",
                            "opus": {
                              "title": "原图文标题",
                              "jump_url": "//www.bilibili.com/opus/8002",
                              "summary": { "text": "原图文正文" },
                              "pics": [
                                { "url": "https://i0.hdslb.com/bfs/new_dyn/pic1.jpg" }
                              ]
                            }
                          }
                        }
                      }
                    }
                  },
                  {
                    "id_str": "9003",
                    "type": "DYNAMIC_TYPE_FORWARD",
                    "visible": true,
                    "modules": {
                      "module_author": { "name": "转发乙", "pub_time": "刚刚" },
                      "module_dynamic": { "desc": { "text": "已失效原动态" } }
                    },
                    "orig": {
                      "id_str": "8003",
                      "type": "DYNAMIC_TYPE_NONE",
                      "modules": {
                        "module_dynamic": {
                          "major": {
                            "type": "MAJOR_TYPE_NONE",
                            "none": {
                              "tips": "源动态已被作者删除"
                            }
                          }
                        }
                      }
                    }
                  },
                  {
                    "id_str": "9004",
                    "type": "DYNAMIC_TYPE_WORD",
                    "visible": true,
                    "modules": {
                      "module_author": { "name": "附加作者", "pub_time": "刚刚" },
                      "module_dynamic": {
                        "desc": { "text": "附上相关视频" },
                        "additional": {
                          "type": "ADDITIONAL_TYPE_UGC",
                          "ugc": {
                            "head_text": "相关视频",
                            "title": "附加视频标题",
                            "desc_second": "10万播放",
                            "cover": "https://i0.hdslb.com/bfs/archive/ugc.jpg",
                            "jump_url": "//www.bilibili.com/video/BV1yy411c7ab"
                          }
                        }
                      }
                    }
                  }
                ]
              }
            }
        """.trimIndent()

        val cards = service().decodeFeedPage(payload).cards

        assertEquals(3, cards.size)

        val opusQuoted = kotlin.test.assertNotNull(cards[0].quotedCard)
        assertEquals("原画师", opusQuoted.author.name)
        assertEquals("原图文标题", opusQuoted.title)
        assertEquals("原图文正文", opusQuoted.text)
        assertEquals(listOf("https://i0.hdslb.com/bfs/new_dyn/pic1.jpg"), opusQuoted.coverURLs)
        assertEquals("https://www.bilibili.com/opus/8002", opusQuoted.targetURL)

        val deletedQuoted = kotlin.test.assertNotNull(cards[1].quotedCard)
        assertEquals("源动态已被作者删除", deletedQuoted.unavailableTip)

        val ugcQuoted = kotlin.test.assertNotNull(cards[2].quotedCard)
        assertEquals("附加视频标题", ugcQuoted.title)
        assertEquals("https://www.bilibili.com/video/BV1yy411c7ab", ugcQuoted.targetURL)
        assertEquals("https://www.bilibili.com/video/BV1yy411c7ab", ugcQuoted.videoURL)
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
