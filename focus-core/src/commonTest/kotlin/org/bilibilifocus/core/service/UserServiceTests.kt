package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.UserContentCollection
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class UserServiceTests {
    private val service = UserService(
        cookieProvider = object : CookieProvider {
            override suspend fun loadCookies(): List<Cookie> = emptyList()
        },
        httpClient = FixtureHttpClient(),
    )

    @Test
    fun `user space endpoints map profile and content sections`() = runTest {
        val profile = service.fetchUserInfo(42)
        val relation = service.fetchRelationInfo(42)
        val videos = service.fetchUserVideoPage(42, pageSize = 1)
        val collections = service.fetchUserCollections(42)
        val articles = service.fetchUserArticles(42)

        assertEquals("测试UP", profile.name)
        assertEquals(12, profile.videoCount)
        assertEquals(3, profile.articleCount)
        assertEquals(9L to 88_888L, relation)
        assertEquals(12, videos.totalCount)
        assertEquals("BV1TEST", videos.items.single().bvid)
        assertEquals(2, videos.nextPage)
        assertEquals(2, collections.size)
        assertEquals(UserContentCollection.Kind.SEASON, collections.first().kind)
        assertEquals("原生合集", collections.first().title)
        assertEquals("专栏标题", articles.single().title)
        assertEquals("https://www.bilibili.com/read/cv77", articles.single().targetURL)
    }

    @Test
    fun `collection page maps videos and pagination`() = runTest {
        val collection = service.fetchUserCollections(42).first()
        val page = service.fetchUserCollectionPage(collection, pageSize = 1)

        assertEquals(collection, page.collection)
        assertEquals("BV1COLLECTION", page.videos.single().bvid)
        assertNotNull(page.nextPage)
    }

    private class FixtureHttpClient : HttpClient {
        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
            val body = when {
                url.contains("/x/web-interface/nav") -> """
                    {"code":0,"data":{"wbi_img":{
                      "img_url":"https://i0.hdslb.com/bfs/wbi/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png",
                      "sub_url":"https://i0.hdslb.com/bfs/wbi/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png"
                    }}}
                """.trimIndent()
                url.contains("/x/space/wbi/acc/info") -> """
                    {"code":0,"data":{
                      "mid":42,"name":"测试UP","face":"//i0.hdslb.com/avatar.jpg","sign":"简介",
                      "level":6,"archive_count":12,"article_count":3
                    }}
                """.trimIndent()
                url.contains("/x/relation/stat") -> """
                    {"code":0,"data":{"following":9,"follower":88888}}
                """.trimIndent()
                url.contains("/x/space/wbi/arc/search") -> """
                    {"code":0,"data":{"page":{"count":12},"list":{"vlist":[{
                      "aid":1,"bvid":"BV1TEST","title":"视频标题","pic":"//i0.hdslb.com/video.jpg",
                      "play":12345,"video_review":6,"length":"1:23","created":1700000000
                    }]}}}
                """.trimIndent()
                url.contains("/x/polymer/web-space/seasons_series_list") -> """
                    {"code":0,"data":{"items_lists":{
                      "seasons_list":[{"meta":{"season_id":11,"name":"原生合集","total":2,"cover":"//i0.hdslb.com/season.jpg"}}],
                      "series_list":[{"meta":{"series_id":22,"name":"视频系列","total":1,"cover":"//i0.hdslb.com/series.jpg"}}]
                    }}}
                """.trimIndent()
                url.contains("/x/space/wbi/article") -> """
                    {"code":0,"data":{"articles":[{
                      "id":77,"title":"专栏标题","summary":"摘要","image_url":"//i0.hdslb.com/article.jpg",
                      "publish_time":1700000000,"stats":{"view":321}
                    }]}}
                """.trimIndent()
                url.contains("/x/polymer/web-space/seasons_archives_list") -> """
                    {"code":0,"data":{"page":{"total":2},"archives":[{
                      "aid":2,"bvid":"BV1COLLECTION","title":"合集视频","pic":"//i0.hdslb.com/item.jpg",
                      "stat":{"view":200},"duration":90,"pubdate":1700000000
                    }]}}
                """.trimIndent()
                else -> error("Unexpected URL: $url")
            }
            assertTrue(headers.containsKey("User-Agent"))
            return HttpResponse(200, body)
        }

        override suspend fun post(
            url: String,
            body: String,
            headers: Map<String, String>,
        ): HttpResponse = error("Unexpected POST: $url")
    }
}
