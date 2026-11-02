package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.cookie.CookieRequestPolicy
import org.bilibilifocus.core.model.FavFolder
import org.bilibilifocus.core.model.FavResource

/**
 * 收藏夹。基于 x/v3/fav/folder/created/list-all（收藏夹列表）与
 * x/v3/fav/resource/list（夹内内容）。私密收藏夹需登录 cookie。
 */
class FavoriteService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object InvalidResponse : ServiceError("接口返回无效数据")
        data object LoginRequired : ServiceError("需要登录")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchFolders(mid: Long): List<FavFolder> {
        val url = BiliApiContractCatalog.require("favorite-list.info.list_list").url +
            "?up_mid=$mid&web_location=333.1387"
        val data = getData(url)
        val list = data.arrayValueAt("list") ?: emptyList()
        return list.mapNotNull { element ->
            val dict = element as? JsonObject ?: return@mapNotNull null
            FavFolder(
                id = dict.longValueAt("id") ?: return@mapNotNull null,
                title = dict.stringValueAt("title") ?: "",
                mediaCount = dict.intValueAt("media_count") ?: 0,
                coverURL = dict.stringValueAt("cover") ?: "",
            )
        }
    }

    suspend fun fetchFolderContents(mediaId: Long, page: Int = 1): List<FavResource> {
        val pn = page.coerceAtLeast(1)
        val url = BiliApiContractCatalog.require("favorite-list.info.list_content").url +
            "?media_id=$mediaId&pn=$pn&ps=20&order=mtime&type=0&tid=0&platform=web&web_location=333.1387"
        val data = getData(url)
        val medias = data.arrayValueAt("medias") ?: emptyList()
        return medias.mapNotNull { element ->
            val dict = element as? JsonObject ?: return@mapNotNull null
            FavResource(
                bvid = dict.stringValueAt("bvid") ?: return@mapNotNull null,
                title = dict.stringValueAt("title") ?: "",
                coverURL = dict.stringValueAt("cover") ?: "",
                upperName = dict.stringValueAt("upper", "name") ?: "",
                duration = formatSeconds(dict.longValueAt("duration") ?: 0L),
                playCount = dict.longValueAt("cnt_info", "play") ?: 0L,
                aid = dict.longValueAt("id") ?: 0L,
            )
        }
    }

    suspend fun authenticatedMID(): Long {
        val endpoint = BiliApiContractCatalog.require("favorite-list.info.list_list").url
        val cookies = CookieRequestPolicy.matchingCookies(cookieProvider.loadCookies(), endpoint)
        return cookies.firstOrNull { it.name == "DedeUserID" }?.value?.toLongOrNull()
            ?: throw ServiceError.LoginRequired
    }

    suspend fun createFolder(title: String, isPrivate: Boolean, expectedMID: Long) {
        require(title.isNotBlank()) { "请输入收藏夹名称" }
        mutate("favorite-list.operate.new", mapOf("title" to title.trim(), "intro" to "", "privacy" to if (isPrivate) "1" else "0", "cover" to ""), expectedMID)
    }

    suspend fun renameFolder(id: Long, title: String, expectedMID: Long) {
        require(title.isNotBlank()) { "请输入收藏夹名称" }
        val info = getData(BiliApiContractCatalog.require("favorite-list.info.info").url + "?media_id=$id")
        mutate("favorite-list.operate.modify", mapOf(
            "media_id" to id.toString(), "title" to title.trim(),
            "intro" to (info.stringValueAt("intro") ?: ""),
            "cover" to (info.stringValueAt("cover") ?: ""),
            "privacy" to if (((info.intValueAt("attr") ?: 0) and 1) == 1) "1" else "0",
        ), expectedMID)
    }

    suspend fun deleteFolder(id: Long, expectedMID: Long) =
        mutate("favorite-list.operate.delete", mapOf("media_ids" to id.toString()), expectedMID)

    suspend fun removeResource(folderID: Long, aid: Long, expectedMID: Long) =
        mutate("favorite-list.operate.content_rm", mapOf("media_id" to folderID.toString(), "resources" to "$aid:2"), expectedMID)

    suspend fun transferResource(source: Long, target: Long, aid: Long, copy: Boolean, expectedMID: Long) {
        val fields = mutableMapOf("src_media_id" to source.toString(), "tar_media_id" to target.toString(), "resources" to "$aid:2")
        if (copy) fields["mid"] = expectedMID.toString()
        mutate(if (copy) "favorite-list.operate.content_copy" else "favorite-list.operate.content_move", fields, expectedMID)
    }

    private suspend fun mutate(key: String, fields: Map<String, String>, expectedMID: Long) {
        val url = BiliApiContractCatalog.require(key).url
        val cookies = CookieRequestPolicy.matchingCookies(cookieProvider.loadCookies(), url)
        if (cookies.firstOrNull { it.name == "DedeUserID" }?.value?.toLongOrNull() != expectedMID ||
            cookies.none { it.name == "SESSDATA" && it.value.isNotBlank() }) throw ServiceError.LoginRequired
        val csrf = cookies.firstOrNull { it.name == "bili_jct" }?.value?.takeIf { it.isNotBlank() } ?: throw ServiceError.LoginRequired
        val body = (fields + ("csrf" to csrf)).entries.sortedBy { it.key }.joinToString("&") { "${rfc3986Encode(it.key)}=${rfc3986Encode(it.value)}" }
        val headers = cookieProvider.attachCookies(mapOf(
            "User-Agent" to userAgent, "Referer" to "https://www.bilibili.com/", "Origin" to "https://www.bilibili.com",
            "Content-Type" to "application/x-www-form-urlencoded; charset=UTF-8",
        ), cookies, url)
        val response = httpClient.post(url, body, headers)
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse
        val payload = json.parseToJsonElement(response.body) as? JsonObject ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: -1
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) throw ServiceError.Api(code, payload.stringValueAt("message") ?: "操作失败")
    }

    /** 发请求并校验通用返回结构，成功返回 data 对象。*/
    private suspend fun getData(url: String): JsonObject {
        val response = httpClient.get(url, buildHeaders(url))
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse

        val payload = json.parseToJsonElement(response.body) as? JsonObject
            ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: -1
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) throw ServiceError.Api(code, payload.stringValueAt("message") ?: "未知错误")
        return payload.dictionaryValueAt("data") ?: throw ServiceError.InvalidResponse
    }

    private fun formatSeconds(total: Long): String {
        if (total <= 0) return ""
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) {
            "$h:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}"
        } else {
            "$m:${s.toString().padStart(2, '0')}"
        }
    }

    private suspend fun buildHeaders(targetUrl: String): Map<String, String> {
        val headers = mutableMapOf(
            "User-Agent" to userAgent,
            "Referer" to "https://www.bilibili.com/",
            "Accept" to "application/json, text/plain, */*",
        )
        return cookieProvider.attachCookies(headers, targetUrl)
    }
}
