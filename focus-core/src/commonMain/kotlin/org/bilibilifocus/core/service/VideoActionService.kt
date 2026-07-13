package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.VideoInteractionState

class VideoActionService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val accountService: AccountService = AccountService(cookieProvider, httpClient),
    private val favoriteService: FavoriteService = FavoriteService(cookieProvider, httpClient),
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object InvalidResponse : ServiceError("接口返回无效数据")
        data object LoginRequired : ServiceError("需要登录")
        data object NoFavoriteFolder : ServiceError("当前账号没有可用收藏夹")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchInteractionState(aid: Long): VideoInteractionState {
        val headers = buildHeaders()
        val liked = runCatching {
            val raw = getDataElement(
                "https://api.bilibili.com/x/web-interface/archive/has/like?aid=$aid",
                headers,
            )
            when (raw) {
                is JsonObject -> raw.intValueAt("liked") == 1 || raw.intValueAt("like") == 1
                else -> raw.jsonPrimitive.content.toIntOrNull() == 1 || raw.jsonPrimitive.content == "true"
            }
        }.getOrDefault(false)

        val coined = runCatching {
            val raw = getDataElement(
                "https://api.bilibili.com/x/web-interface/archive/coins?aid=$aid",
                headers,
            )
            when (raw) {
                is JsonObject -> (raw.intValueAt("multiply") ?: raw.intValueAt("coin"))?.let { it > 0 } ?: false
                else -> raw.jsonPrimitive.content.toIntOrNull()?.let { it > 0 } ?: false
            }
        }.getOrDefault(false)

        val favorited = runCatching {
            val raw = getDataElement(
                "https://api.bilibili.com/x/v2/fav/video/favoured?aid=$aid",
                headers,
            )
            when (raw) {
                is JsonObject -> {
                    val favoured = raw.intValueAt("favoured")
                    when (favoured) {
                        1 -> true
                        0 -> false
                        else -> raw.stringValueAt("favoured") == "true"
                    }
                }
                else -> raw.jsonPrimitive.content.toIntOrNull() == 1 || raw.jsonPrimitive.content == "true"
            }
        }.getOrDefault(false)

        val favoriteFolderId = runCatching { resolveDefaultFavoriteFolderId() }.getOrNull()

        return VideoInteractionState(
            liked = liked,
            coined = coined,
            favorited = favorited,
            favoriteFolderId = favoriteFolderId,
            loading = false,
        )
    }

    suspend fun toggleLike(aid: Long, liked: Boolean) {
        val csrf = csrfToken()
        postForm(
            url = "https://api.bilibili.com/x/web-interface/archive/like",
            body = "aid=$aid&like=${if (liked) 1 else 2}&csrf=$csrf&csrf_token=$csrf",
        )
    }

    suspend fun coin(aid: Long, likeAlso: Boolean = false) {
        val csrf = csrfToken()
        postForm(
            url = "https://api.bilibili.com/x/web-interface/coin/add",
            body = "aid=$aid&multiply=1&select_like=${if (likeAlso) 1 else 0}&csrf=$csrf&csrf_token=$csrf",
        )
    }

    /** Mirrors bilibili-api's Video.report_watch_history request. */
    suspend fun reportWatchHistory(aid: Long, cid: Long, progressSeconds: Long) {
        val csrf = csrfToken()
        postForm(
            url = "https://api.bilibili.com/x/v2/history/report",
            body = "aid=$aid&cid=$cid&progress=${progressSeconds.coerceAtLeast(0)}&csrf=$csrf",
        )
    }

    suspend fun toggleFavorite(aid: Long, favorited: Boolean, folderId: Long? = null): Long {
        val targetFolderId = folderId ?: resolveDefaultFavoriteFolderId()
        val csrf = csrfToken()
        val addMediaIds = if (favorited) targetFolderId.toString() else ""
        val delMediaIds = if (favorited) "" else targetFolderId.toString()
        postForm(
            url = "https://api.bilibili.com/x/v3/fav/resource/deal",
            body = "rid=$aid&type=2&add_media_ids=$addMediaIds&del_media_ids=$delMediaIds&csrf=$csrf&csrf_token=$csrf",
        )
        return targetFolderId
    }

    suspend fun resolveDefaultFavoriteFolderId(): Long {
        val account = accountService.fetchLoginAccount()
        if (!account.isLogin || account.mid <= 0) throw ServiceError.LoginRequired
        val folders = favoriteService.fetchFolders(account.mid)
        return folders.firstOrNull()?.id ?: throw ServiceError.NoFavoriteFolder
    }

    private suspend fun getDataElement(url: String, headers: Map<String, String>): JsonElement {
        val response = httpClient.get(url, headers)
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse
        val payload = json.parseToJsonElement(response.body) as? JsonObject
            ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: -1
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) throw ServiceError.Api(code, payload.stringValueAt("message") ?: "未知错误")
        return payload.valueAt("data") ?: JsonObject(emptyMap())
    }

    private suspend fun postForm(url: String, body: String) {
        val response = httpClient.post(url, body, buildPostHeaders())
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse
        val payload = json.parseToJsonElement(response.body) as? JsonObject
            ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: -1
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) throw ServiceError.Api(code, payload.stringValueAt("message") ?: "未知错误")
    }

    private suspend fun csrfToken(): String {
        val csrf = cookieProvider.loadCookies().firstOrNull { it.name == "bili_jct" }?.value
        if (csrf.isNullOrBlank()) throw ServiceError.LoginRequired
        return csrf
    }

    private suspend fun buildHeaders(): Map<String, String> {
        val cookies = cookieProvider.loadCookies()
        val headers = mutableMapOf(
            "User-Agent" to userAgent,
            "Referer" to "https://www.bilibili.com/",
            "Accept" to "application/json, text/plain, */*",
        )
        return cookieProvider.attachCookies(headers, cookies)
    }

    private suspend fun buildPostHeaders(): Map<String, String> {
        return buildHeaders() + mapOf(
            "Content-Type" to "application/x-www-form-urlencoded; charset=UTF-8",
            "Origin" to "https://www.bilibili.com",
        )
    }
}
