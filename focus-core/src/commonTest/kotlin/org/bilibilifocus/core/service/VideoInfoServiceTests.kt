package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.CommentCursor
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class VideoInfoServiceTests {
    @Test
    fun `video detail includes server playback progress`() = runTest {
        val http = FixtureHttpClient(
            playerBody = """
                {"code":0,"data":{"last_play_cid":202,"last_play_time":87000}}
            """.trimIndent(),
        )

        val info = service(http).fetchVideoInfo("BV1TEST00001")

        assertEquals(202, info.lastPlaybackCid)
        assertEquals(87_000, info.lastPlaybackPositionMillis)
        val playerUrl = http.requestedUrls.first { "/x/player/wbi/v2" in it }
        assertTrue("aid=42" in playerUrl)
        assertTrue("cid=101" in playerUrl)
        assertTrue("isGaiaAvoided=false" in playerUrl)
        assertTrue("web_location=1315873" in playerUrl)
        assertTrue("w_rid=" in playerUrl)
    }

    @Test
    fun `video detail remains available when resume metadata is unavailable`() = runTest {
        val info = service(
            FixtureHttpClient(playerBody = """{"code":-101,"message":"账号未登录"}"""),
        ).fetchVideoInfo("BV1TEST00001")

        assertEquals("测试视频", info.title)
        assertNull(info.lastPlaybackCid)
        assertEquals(0, info.lastPlaybackPositionMillis)
    }

    @Test
    fun `comment cursor sends pagination string and decodes next offset`() = runTest {
        val http = CommentFixtureHttpClient()
        val page = service(http).fetchCommentPage(
            oid = 3_547_000_000_000_000L,
            cursor = CommentCursor("seed+/="),
        )

        assertEquals(1, page.comments.size)
        assertEquals(3_000_000_000L, page.totalCount)
        assertEquals("next-opaque-token", page.cursor.nextOffset)
        val commentUrl = http.requestedUrls.first { "/x/v2/reply/wbi/main" in it }
        assertTrue("mode=3" in commentUrl)
        assertTrue("pagination_str=%7B%22offset%22%3A%22seed%2B%2F%3D%22%7D" in commentUrl)
        assertTrue("web_location=1315875" in commentUrl)
        assertTrue("pn=" !in commentUrl)
    }

    private fun service(httpClient: HttpClient) = VideoInfoService(
        cookieProvider = object : CookieProvider {
            override suspend fun loadCookies(): List<Cookie> = listOf(
                Cookie("SESSDATA", "session-token", ".bilibili.com"),
            )
        },
        httpClient = httpClient,
    )

    private class FixtureHttpClient(
        private val playerBody: String,
    ) : HttpClient {
        val requestedUrls = mutableListOf<String>()

        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
            requestedUrls += url
            assertTrue(headers.containsKey("User-Agent"))
            val body = when {
                "/x/web-interface/view" in url -> VIDEO_DETAIL
                "/x/web-interface/nav" in url -> NAV_RESPONSE
                "/x/player/wbi/v2" in url -> playerBody
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

    private class CommentFixtureHttpClient : HttpClient {
        val requestedUrls = mutableListOf<String>()

        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
            requestedUrls += url
            return when {
                "/x/web-interface/nav" in url -> HttpResponse(200, NAV_RESPONSE)
                "/x/v2/reply/wbi/main" in url -> HttpResponse(
                    200,
                    """
                    {
                      "code":0,
                      "data":{
                        "cursor":{
                          "all_count":3000000000,
                          "pagination_reply":{"next_offset":"next-opaque-token"}
                        },
                        "replies":[{
                          "rpid":3547000000000001,
                          "mid":3547000000000002,
                          "member":{"uname":"测试用户","avatar":"https://i0.hdslb.com/a.jpg"},
                          "content":{"message":"测试评论"},
                          "like":3000000001,
                          "rcount":2,
                          "ctime":1700000000,
                          "replies":[]
                        }]
                      }
                    }
                    """.trimIndent(),
                )
                else -> error("Unexpected URL: $url")
            }
        }

        override suspend fun post(
            url: String,
            body: String,
            headers: Map<String, String>,
        ): HttpResponse = error("Unexpected POST: $url")
    }

    private companion object {
        val NAV_RESPONSE = """
            {"code":0,"data":{"wbi_img":{
              "img_url":"https://i0.hdslb.com/abcdefghijklmnopqrstuvwxyz012345.png",
              "sub_url":"https://i0.hdslb.com/ABCDEFGHIJKLMNOPQRSTUVWXYZ012345.png"
            }}}
        """.trimIndent()

        val VIDEO_DETAIL = """
            {
              "code":0,
              "data":{
                "bvid":"BV1TEST00001",
                "aid":42,
                "cid":101,
                "title":"测试视频",
                "desc":"简介",
                "pic":"https://i0.hdslb.com/video.jpg",
                "duration":180,
                "pubdate":1700000000,
                "owner":{"name":"测试UP","mid":7,"face":"https://i0.hdslb.com/avatar.jpg"},
                "stat":{"view":1,"like":2,"coin":3,"favorite":4,"share":5,"danmaku":6,"reply":7},
                "dimension":{"width":1920,"height":1080},
                "pages":[
                  {"page":1,"cid":101,"part":"P1","duration":90},
                  {"page":2,"cid":202,"part":"P2","duration":90}
                ]
              }
            }
        """.trimIndent()
    }
}
