package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.VideoSubtitleTrack
import kotlin.test.*

class VideoPlaybackExperienceTests {
    private val account = object : CookieProvider {
        override suspend fun loadCookies() = listOf(
            Cookie("DedeUserID", "42", ".bilibili.com"), Cookie("SESSDATA", "fixture-session", ".bilibili.com"), Cookie("bili_jct", "fixture-csrf", ".bilibili.com"),
        )
    }

    @Test fun `requested quality selects matching AVC and retains alternate CDN routes`() = runTest {
        val client = FixtureClient(play = """{"code":0,"data":{"quality":64,"accept_quality":[80,64],"accept_description":["1080P","720P"],"dash":{"video":[{"id":80,"codecid":7,"baseUrl":"https://cdn/video1080"},{"id":64,"codecid":12,"baseUrl":"https://cdn/hevc"},{"id":64,"codecid":7,"baseUrl":"https://mcdn.example/video","backupUrl":["https://cdn/video720","https://backup/video720"]}],"audio":[]}}}""")
        val result = PlayUrlService(account, client).fetchPlayUrl("BV1xx411c7mD", 1, 64)
        assertEquals(64, result.quality)
        assertEquals("https://cdn/video720", result.videoUrl)
        assertEquals(listOf("https://backup/video720", "https://mcdn.example/video"), result.backupVideoUrls)
        assertEquals(listOf(80, 64), result.availableQualities.map { it.id })
        assertTrue(client.gets.last().contains("qn=64"))
    }

    @Test fun `subtitle BCC requests never forward cookies and discard malformed intervals`() = runTest {
        val client = FixtureClient(bcc = """{"body":[{"from":2,"to":3,"content":"后一句"},{"from":0,"to":1,"content":"第一句"},{"from":4,"to":2,"content":"invalid"}]}""")
        val service = VideoInfoService(account, client)
        val document = service.fetchSubtitleDocument(VideoSubtitleTrack(1, "zh-CN", "中文", "https://aisubtitle.hdslb.com/fixture.json"))
        assertEquals("第一句", document.textAt(500))
        assertEquals(2, document.cues.size)
        assertFalse(client.headers.last().keys.any { it.equals("Cookie", true) })
    }

    @Test fun `subtitle external hosts are rejected before fetching`() = runTest {
        val client = FixtureClient()
        val service = VideoInfoService(account, client)
        assertFailsWith<VideoInfoService.ServiceError.InvalidResponse> {
            service.fetchSubtitleDocument(VideoSubtitleTrack(1, "en", "English", "https://hdslb.com.attacker.example/bcc"))
        }
        assertTrue(client.gets.isEmpty())
    }

    @Test fun `comment writes reject a changed account before posting`() = runTest {
        val client = FixtureClient()
        assertFailsWith<VideoInfoService.ServiceError.LoginRequired> { VideoInfoService(account, client).setCommentLiked(1, 2, true, 99) }
        assertTrue(client.posts.isEmpty())
    }

    @Test fun `comment like accepts null data and uses account-bound form`() = runTest {
        val client = FixtureClient(postResponse = """{"code":0,"data":null}""")
        VideoInfoService(account, client).setCommentLiked(1, 2, true, 42)
        assertEquals(1, client.posts.size)
        assertTrue(client.posts.single().second.contains("csrf=fixture-csrf"))
        assertTrue(client.posts.single().second.contains("action=1"))
    }

    @Test fun `ambiguous comment send failure is not automatically retried`() = runTest {
        val client = FixtureClient(postResponse = """{"code":-403,"message":"rejected"}""")
        assertFailsWith<VideoInfoService.ServiceError.Api> { VideoInfoService(account, client).sendComment(1, "你好 & world", expectedMid = 42) }
        assertEquals(1, client.posts.size)
        assertTrue(client.posts.single().first.contains("w_rid="))
        assertTrue(client.posts.single().second.contains("message=%E4%BD%A0%E5%A5%BD%20%26%20world"))
    }

    private class FixtureClient(
        private val play: String = "",
        private val bcc: String = "",
        private val postResponse: String = """{"code":0,"data":{}}""",
    ) : HttpClient {
        val gets = mutableListOf<String>()
        val headers = mutableListOf<Map<String, String>>()
        val posts = mutableListOf<Pair<String, String>>()
        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
            gets += url; this.headers += headers
            return HttpResponse(200, when {
                "/x/web-interface/nav" in url -> """{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/abcdefghijklmnopqrstuvwxyz012345.png","sub_url":"https://i0.hdslb.com/ABCDEFGHIJKLMNOPQRSTUVWXYZ012345.png"}}}"""
                "/playurl" in url -> play
                "hdslb.com" in url -> bcc
                else -> error("Unexpected GET")
            })
        }
        override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse {
            posts += url to body; this.headers += headers
            return HttpResponse(200, postResponse)
        }
    }
}
