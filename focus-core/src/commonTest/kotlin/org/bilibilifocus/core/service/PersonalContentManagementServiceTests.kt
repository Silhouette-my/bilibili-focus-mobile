package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class PersonalContentManagementServiceTests {
    @Test
    fun `history search encodes keyword page and business without interpreting unknown cursor`() = runTest {
        val transport = PersonalManagementTransport()
        val items = HistoryService(PersonalManagementCookies(), transport).searchHistory("图形 + shader", 2)
        val url = transport.gets.single()
        assertTrue(url.contains("/x/web-interface/history/search?"))
        assertTrue(url.contains("keyword=${rfc3986Encode("图形 + shader")}"))
        assertTrue(url.contains("pn=2"))
        assertTrue(url.contains("business=all"))
        assertEquals("BV-REMOTE", items.single().bvid)
        assertEquals(101L, items.single().cid)
    }

    @Test
    fun `numeric favorite duration is formatted as minutes and seconds`() = runTest {
        val items = FavoriteService(PersonalManagementCookies(), PersonalManagementTransport()).fetchFolderContents(1)
        assertEquals("10:00", items.single().duration)
    }

    @Test
    fun `rename preserves introduction cover and private status`() = runTest {
        val transport = PersonalManagementTransport()
        FavoriteService(PersonalManagementCookies(), transport).renameFolder(1, "New title", 10001)
        assertEquals(1, transport.posts.size)
        val (url, body) = transport.posts.single()
        assertTrue(url.endsWith("/x/v3/fav/folder/edit"))
        assertTrue(body.contains("title=New%20title"))
        assertTrue(body.contains("intro=Original%20intro"))
        assertTrue(body.contains("privacy=1"))
        assertTrue(body.contains("cover=original-cover"))
        assertTrue(body.contains("csrf=synthetic-csrf"))
    }

    @Test
    fun `mutations reject account switch before issuing any post`() = runTest {
        val transport = PersonalManagementTransport()
        val cookies = PersonalManagementCookies(mid = "20002")
        assertFailsWith<FavoriteService.ServiceError.LoginRequired> { FavoriteService(cookies, transport).deleteFolder(1, 10001) }
        assertFailsWith<HistoryService.ServiceError.LoginRequired> { HistoryService(cookies, transport).clearHistory(10001) }
        assertEquals(emptyList(), transport.posts)
    }

    @Test
    fun `history deletion uses numeric archive kid and never treats pgc oid as a season id`() = runTest {
        val transport = PersonalManagementTransport()
        val service = HistoryService(PersonalManagementCookies(), transport)
        val items = service.fetchHistory().items
        assertEquals("archive_9000000001", items[0].historyKey)
        assertEquals("", items[1].historyKey)
        service.deleteHistory(items[0].historyKey, 10001)
        assertTrue(transport.posts.single().first.endsWith("/x/v2/history/delete"))
        assertTrue(transport.posts.single().second.contains("kid=archive_9000000001"))
        assertFailsWith<IllegalArgumentException> { service.deleteHistory("pgc_42", 10001) }
        assertEquals(1, transport.posts.size)
    }

    @Test
    fun `favorite transfer sends resource aid not bvid and copy includes account mid`() = runTest {
        val transport = PersonalManagementTransport()
        val service = FavoriteService(PersonalManagementCookies(), transport)
        service.transferResource(1, 2, 9_000_000_001, true, 10001)
        val body = transport.posts.single().second
        assertTrue(body.contains("resources=9000000001%3A2"))
        assertTrue(body.contains("src_media_id=1"))
        assertTrue(body.contains("tar_media_id=2"))
        assertTrue(body.contains("mid=10001"))
    }
}

private class PersonalManagementCookies(private val mid: String = "10001") : CookieProvider {
    override suspend fun loadCookies() = listOf(Cookie("DedeUserID", mid, ".bilibili.com"), Cookie("SESSDATA", "synthetic-session", ".bilibili.com"), Cookie("bili_jct", "synthetic-csrf", ".bilibili.com"))
}

private class PersonalManagementTransport : HttpClient {
    val posts = mutableListOf<Pair<String, String>>()
    val gets = mutableListOf<String>()
    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
        gets += url
        return when {
        "/x/web-interface/history/search" in url -> HttpResponse(200, """{"code":0,"data":{"list":[{"title":"Remote result","history":{"bvid":"BV-REMOTE","business":"archive","oid":42,"cid":101},"duration":600}],"cursor":{"unrecognized":"opaque"}}}""")
        "/x/v3/fav/folder/info" in url -> HttpResponse(200, """{"code":0,"data":{"intro":"Original intro","attr":1,"cover":"original-cover"}}""")
        "/x/v3/fav/resource/list" in url -> HttpResponse(200, """{"code":0,"data":{"medias":[{"id":42,"bvid":"BV-FAVORITE","duration":600}]}}""")
        "/x/web-interface/history/cursor" in url -> HttpResponse(200, """{"code":0,"data":{"list":[{"kid":9000000001,"title":"Archive","history":{"oid":42,"business":"archive","bvid":"BV-ARCHIVE"}},{"kid":42,"title":"Series","history":{"oid":42,"business":"pgc","bvid":"BV-SERIES"}}],"cursor":{"max":0}}}""")
        else -> error("Unexpected fixture GET")
        }
    }
    override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse {
        posts += url to body
        return HttpResponse(200, """{"code":0,"data":{}}""")
    }
}
