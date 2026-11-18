package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.CancellationException
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.CommentTarget
import org.bilibilifocus.core.model.OpusBlock
import org.bilibilifocus.core.model.RichTextRun
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class OpusRichTextTests {
    @Test
    fun `dynamic detail fallback preserves cancellation`() = runTest {
        val service = OpusService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = emptyList()
            },
            httpClient = object : HttpClient {
                override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
                    if ("/opus/detail" in url) return HttpResponse(200, """{"code":0,"data":{"item":{"modules":{}}}}""")
                    throw CancellationException("cancel dynamic fallback")
                }
                override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse =
                    error("Unexpected POST")
            },
        )
        assertFailsWith<CancellationException> { service.fetchOpusDetail("123") }
    }

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

    @Test
    fun `opus detail parses array modules normalizes image urls and resolves comment target`() = runTest {
        val requestedCommentTypes = mutableListOf<String>()
        val service = OpusService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = emptyList()
            },
            httpClient = object : HttpClient {
                override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
                    val body = when {
                        "/opus/detail" in url -> """
                            {
                              "code": 0,
                              "data": {
                                "item": {
                                  "basic": {"comment_id_str": "5566", "comment_type": 11},
                                  "modules": [
                                    {"module_type": "MODULE_TYPE_TITLE", "module_title": {"text": "标题"}},
                                    {"module_type": "MODULE_TYPE_AUTHOR", "module_author": {"name": "画师", "mid": 9, "face": "http://i0.hdslb.com/bfs/face/avatar.jpg"}},
                                    {"module_type": "MODULE_TYPE_TOP", "module_top": {"display": {"album": {"pics": [{"url": "//i1.hdslb.com/bfs/new_dyn/top.jpg", "width": 1200, "height": 800}]}}}},
                                    {"module_type": "MODULE_TYPE_CONTENT", "module_content": {"paragraphs": [{"para_type": 1, "text": {"nodes": [{"word": {"words": "正文内容"}}]}}, {"para_type": 2, "pic": {"pics": [{"url": "http://i2.hdslb.com/bfs/opus/inline.png", "width": 800, "height": 600}]}}]}}
                                  ]
                                }
                              }
                            }
                        """.trimIndent()
                        "/x/web-interface/nav" in url ->
                            """{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/abcdefghijklmnopqrstuvwxyz012345.png","sub_url":"https://i0.hdslb.com/ABCDEFGHIJKLMNOPQRSTUVWXYZ012345.png"}}}"""
                        "/x/v2/reply/wbi/main" in url -> {
                            val type = url.substringAfter("type=").substringBefore("&")
                            requestedCommentTypes += type
                            if (type == "11") {
                                """{"code":0,"data":{"cursor":{"all_count":2},"replies":[{"rpid":1,"mid":2,"member":{"uname":"路人","avatar":""},"content":{"message":"好看"},"like":3,"rcount":0,"ctime":1700000000}]}}"""
                            } else {
                                """{"code":0,"data":{"cursor":{"all_count":0},"replies":[]}}"""
                            }
                        }
                        else -> error("Unexpected GET: $url")
                    }
                    return HttpResponse(200, body)
                }

                override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse =
                    error("Unexpected POST: $url")
            },
        )

        val detail = service.fetchOpusDetail("5566")
        assertEquals("https://i0.hdslb.com/bfs/face/avatar.jpg", detail.author.avatarURL)
        assertEquals(5566L, detail.commentId)
        assertEquals(11, detail.commentType)
        assertEquals(
            "https://i1.hdslb.com/bfs/new_dyn/top.jpg",
            assertIs<OpusBlock.Image>(detail.paragraphs[1].blocks.single()).pics.single().url,
        )
        assertEquals(
            "https://i2.hdslb.com/bfs/opus/inline.png",
            assertIs<OpusBlock.Image>(detail.paragraphs[3].blocks.single()).pics.single().url,
        )

        // When commentType is already present, no probe request is needed.
        assertEquals(CommentTarget(5566L, 11), service.resolveCommentTarget(detail))
        assertTrue(requestedCommentTypes.isEmpty())

        // When commentType == 0, resolveCommentTarget probes 17 -> 11 -> 12 and stops on 11.
        val probed = service.resolveCommentTarget(detail.copy(commentType = 0))
        assertEquals(CommentTarget(5566L, 11), probed)
        assertEquals(listOf("17", "11"), requestedCommentTypes)
    }

    @Test
    fun `opus detail parses blockquote and link_card reference blocks`() = runTest {
        val service = OpusService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = emptyList()
            },
            httpClient = object : HttpClient {
                override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
                    val body = """
                        {
                          "code": 0,
                          "data": {
                            "item": {
                              "id_str": "7788",
                              "basic": {"comment_id_str": "7788", "comment_type": 11},
                              "modules": [
                                {
                                  "module_type": "MODULE_TYPE_AUTHOR",
                                  "module_author": {"name": "专栏作者", "mid": 1001, "pub_time": "今天"}
                                },
                                {
                                  "module_type": "MODULE_TYPE_CONTENT",
                                  "module_content": {
                                    "paragraphs": [
                                      {
                                        "para_type": 4,
                                        "blockquote": {
                                          "children": [
                                            {
                                              "text": {
                                                "nodes": [
                                                  {"type": "TEXT_NODE_TYPE_WORD", "word": {"words": "第一句引用"}},
                                                  {"type": "TEXT_NODE_TYPE_WORD", "word": {"words": "第二句引用"}}
                                                ]
                                              }
                                            }
                                          ]
                                        }
                                      },
                                      {
                                        "para_type": 6,
                                        "link_card": {
                                          "card": {
                                            "card_type": "LINK_CARD_TYPE_OPUS",
                                            "jump_url": "//www.bilibili.com/opus/8801",
                                            "opus": {
                                              "title": "关联动态标题",
                                              "author": {"name": "原作者", "mid": 42, "face": "//i0.hdslb.com/a.jpg"},
                                              "summary": {"text": "关联动态摘要"},
                                              "jump_url": "//www.bilibili.com/opus/8801"
                                            }
                                          }
                                        }
                                      },
                                      {
                                        "para_type": 6,
                                        "link_card": {
                                          "card": {
                                            "card_type": "LINK_CARD_TYPE_UGC",
                                            "ugc": {
                                              "title": "关联视频标题",
                                              "bvid": "BV1zz411c7xy",
                                              "desc_second": "05:20",
                                              "cover": "//i0.hdslb.com/v.jpg",
                                              "jump_url": "//www.bilibili.com/video/BV1zz411c7xy"
                                            }
                                          }
                                        }
                                      },
                                      {
                                        "para_type": 6,
                                        "link_card": {
                                          "card": {
                                            "card_type": "LINK_CARD_TYPE_ITEM_NULL",
                                            "item_null": {"text": "源内容已被删除"}
                                          }
                                        }
                                      }
                                    ]
                                  }
                                }
                              ]
                            }
                          }
                        }
                    """.trimIndent()
                    return HttpResponse(200, body)
                }

                override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse =
                    error("Unexpected POST")
            },
        )

        val detail = service.fetchOpusDetail("7788")
        val blocks = detail.paragraphs.flatMap { it.blocks }

        val quotes = blocks.filterIsInstance<org.bilibilifocus.core.model.OpusBlock.Quote>()
        assertEquals(1, quotes.size)
        val quoteText = quotes.single().nodes
            .filterIsInstance<org.bilibilifocus.core.model.RichTextRun.Text>()
            .joinToString("") { it.text }
        assertTrue(quoteText.contains("第一句引用"))
        assertTrue(quoteText.contains("第二句引用"))

        val refs = blocks.filterIsInstance<org.bilibilifocus.core.model.OpusBlock.Reference>().map { it.reference }
        assertEquals(3, refs.size)
        assertEquals("原作者", refs[0].authorName)
        assertEquals("关联动态标题", refs[0].title)
        assertEquals("https://www.bilibili.com/opus/8801", refs[0].targetURL)
        assertEquals("关联视频标题", refs[1].title)
        assertEquals("https://www.bilibili.com/video/BV1zz411c7xy", refs[1].targetURL)
        assertEquals("源内容已被删除", refs[2].unavailableTip)
    }

    @Test
    fun `opus detail falls back to dynamic detail when opus endpoint returns error on forwarded post`() = runTest {
        val service = OpusService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = emptyList()
            },
            httpClient = object : HttpClient {
                override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
                    val body = when {
                        "/opus/detail" in url ->
                            """{"code":-404,"message":"nothing found"}"""
                        "/x/web-interface/nav" in url ->
                            """{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/abcdefghijklmnopqrstuvwxyz012345.png","sub_url":"https://i0.hdslb.com/ABCDEFGHIJKLMNOPQRSTUVWXYZ012345.png"}}}"""
                        else -> """
                            {
                              "code": 0,
                              "data": {
                                "item": {
                                  "id_str": "9001",
                                  "type": "DYNAMIC_TYPE_FORWARD",
                                  "basic": {"comment_id_str": "9001", "comment_type": 17},
                                  "modules": {
                                    "module_author": {"name": "外层转发作者", "mid": 11, "pub_time": "10分钟前"},
                                    "module_dynamic": {
                                      "desc": {"text": "转发附言"}
                                    }
                                  },
                                  "orig": {
                                    "id_str": "8001",
                                    "type": "DYNAMIC_TYPE_AV",
                                    "modules": {
                                      "module_author": {"name": "原动态作者", "mid": 22, "pub_time": "1小时前"},
                                      "module_dynamic": {
                                        "major": {
                                          "type": "MAJOR_TYPE_ARCHIVE",
                                          "archive": {
                                            "bvid": "BV1ab411c7cd",
                                            "title": "原视频",
                                            "desc": "视频简介",
                                            "cover": "//i0.hdslb.com/bfs/archive/orig.jpg",
                                            "jump_url": "//www.bilibili.com/video/BV1ab411c7cd"
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                        """.trimIndent()
                    }
                    return HttpResponse(200, body)
                }

                override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse =
                    error("Unexpected POST")
            },
        )

        val detail = service.fetchOpusDetail("9001")
        assertEquals("外层转发作者", detail.author.name)
        assertEquals(9001L, detail.commentId)
        assertEquals(17, detail.commentType)

        val blocks = detail.paragraphs.flatMap { it.blocks }
        val textContent = blocks.filterIsInstance<org.bilibilifocus.core.model.OpusBlock.Text>()
            .flatMap { it.nodes }
            .filterIsInstance<org.bilibilifocus.core.model.RichTextRun.Text>()
            .joinToString("") { it.text }
        assertTrue(textContent.contains("转发附言"))

        val ref = blocks.filterIsInstance<org.bilibilifocus.core.model.OpusBlock.Reference>()
            .single()
            .reference
        assertEquals("原动态作者", ref.authorName)
        assertEquals("原视频", ref.title)
        assertEquals("https://www.bilibili.com/video/BV1ab411c7cd", ref.targetURL)
    }
}
