package org.bilibilifocus.core.service

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.cookie.CookieRequestPolicy
import org.bilibilifocus.core.model.WatchLaterAuthor
import org.bilibilifocus.core.model.WatchLaterItem
import org.bilibilifocus.core.model.WatchLaterList
import org.bilibilifocus.core.routing.urlEncode

/**
 * Account-scoped access to Bilibili's "watch later" list.
 *
 * Endpoint facts come from [BiliApiContractCatalog]. Request behavior is
 * implemented locally so credentials remain URL-scoped and write requests
 * are never retried by this service.
 */
class WatchLaterService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = DEFAULT_USER_AGENT,
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object InvalidResponse : ServiceError("稍后再看接口返回无效数据")
        data object LoginRequired : ServiceError("需要登录")
        data object MissingCsrf : ServiceError("登录凭据缺少 bili_jct")
        data object InvalidAid : ServiceError("视频 aid 无效")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
    }

    private data class AuthenticationSnapshot(
        val cookies: List<Cookie>,
        val csrf: String?,
    )

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchList(): WatchLaterList {
        currentCoroutineContext().ensureActive()
        val url = BiliApiContractCatalog.require(LIST_ENDPOINT).url
        val authentication = authenticationSnapshot(url, needsCsrf = false)
        val response = httpClient.get(url, buildHeaders(url, authentication.cookies))
        currentCoroutineContext().ensureActive()
        return decodeListResponse(response)
    }

    suspend fun add(aid: Long) {
        if (aid <= 0) throw ServiceError.InvalidAid
        postMutation(
            endpointKey = ADD_ENDPOINT,
            values = listOf("aid" to aid.toString()),
        )
    }

    suspend fun remove(aid: Long) {
        if (aid <= 0) throw ServiceError.InvalidAid
        postMutation(
            endpointKey = DELETE_ENDPOINT,
            values = listOf(
                "aid" to aid.toString(),
                "viewed" to "false",
            ),
        )
    }

    suspend fun deleteViewed() {
        postMutation(
            endpointKey = DELETE_ENDPOINT,
            values = listOf("viewed" to "true"),
        )
    }

    suspend fun clear() {
        postMutation(endpointKey = CLEAR_ENDPOINT, values = emptyList())
    }

    private suspend fun postMutation(
        endpointKey: String,
        values: List<Pair<String, String>>,
    ) {
        currentCoroutineContext().ensureActive()
        val url = BiliApiContractCatalog.require(endpointKey).url
        val authentication = authenticationSnapshot(url, needsCsrf = true)
        val csrf = authentication.csrf ?: throw ServiceError.MissingCsrf
        val body = formBody(
            values + listOf(
                "csrf" to csrf,
                "csrf_token" to csrf,
            ),
        )
        val response = httpClient.post(
            url = url,
            body = body,
            headers = buildHeaders(url, authentication.cookies) + mapOf(
                "Content-Type" to "application/x-www-form-urlencoded; charset=UTF-8",
                "Origin" to "https://www.bilibili.com",
            ),
        )
        currentCoroutineContext().ensureActive()
        validateResponse(response)
    }

    private suspend fun authenticationSnapshot(
        targetUrl: String,
        needsCsrf: Boolean,
    ): AuthenticationSnapshot {
        val cookies = cookieProvider.loadCookies()
        currentCoroutineContext().ensureActive()
        val matchingCookies = CookieRequestPolicy.matchingCookies(cookies, targetUrl)
        val hasSession = matchingCookies.any {
            it.name == "SESSDATA" && it.value.isNotBlank()
        }
        if (!hasSession) throw ServiceError.LoginRequired

        val csrf = matchingCookies.firstOrNull {
            it.name == "bili_jct" && it.value.isNotBlank()
        }?.value
        if (needsCsrf && csrf == null) throw ServiceError.MissingCsrf
        return AuthenticationSnapshot(cookies = cookies, csrf = csrf)
    }

    private fun decodeListResponse(response: HttpResponse): WatchLaterList {
        val payload = validatedPayload(response)
        val data = payload.dictionaryValueAt("data") ?: throw ServiceError.InvalidResponse
        val items = (data.arrayValueAt("list") ?: emptyList()).mapNotNull { element ->
            val item = element as? JsonObject ?: return@mapNotNull null
            val aid = item.longValue("aid") ?: return@mapNotNull null
            if (aid <= 0) return@mapNotNull null
            val author = item.dictionaryValueAt("owner")
            WatchLaterItem(
                aid = aid,
                bvid = item.stringValueAt("bvid") ?: "",
                cid = item.longValue("cid") ?: 0L,
                title = item.stringValueAt("title") ?: "",
                coverURL = normalizedURL(item.stringValueAt("pic")),
                author = WatchLaterAuthor(
                    mid = author?.longValue("mid") ?: 0L,
                    name = author?.stringValueAt("name") ?: "",
                    avatarURL = normalizedURL(author?.stringValueAt("face")),
                ),
                durationSeconds = item.longValue("duration") ?: 0L,
                progressSeconds = item.longValue("progress") ?: 0L,
                addedAt = item.longValue("add_at") ?: 0L,
                publishedAt = item.longValue("pubdate") ?: 0L,
                viewCount = item.longValue("stat", "view") ?: 0L,
            )
        }
        return WatchLaterList(
            totalCount = (data.longValue("count") ?: items.size.toLong())
                .coerceIn(0, Int.MAX_VALUE.toLong())
                .toInt(),
            items = items,
        )
    }

    private fun validateResponse(response: HttpResponse) {
        validatedPayload(response)
    }

    private fun validatedPayload(response: HttpResponse): JsonObject {
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse
        val payload = runCatching {
            json.parseToJsonElement(response.body) as? JsonObject
        }.getOrNull() ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: throw ServiceError.InvalidResponse
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) {
            throw ServiceError.Api(
                code = code,
                message = payload.stringValueAt("message") ?: "未知错误",
            )
        }
        return payload
    }

    private fun buildHeaders(
        targetUrl: String,
        cookies: List<Cookie>,
    ): Map<String, String> = cookieProvider.attachCookies(
        requestHeaders = mapOf(
            "User-Agent" to userAgent,
            "Referer" to "https://www.bilibili.com/",
            "Accept" to "application/json, text/plain, */*",
        ),
        cookies = cookies,
        targetUrl = targetUrl,
    )

    private fun formBody(values: List<Pair<String, String>>): String =
        values.joinToString("&") { (name, value) ->
            "${urlEncode(name)}=${urlEncode(value)}"
        }

    private fun JsonObject.longValue(vararg path: String): Long? {
        val element = valueAt(*path) ?: return null
        if (element is JsonNull) return null
        return element.jsonPrimitive.content.toLongOrNull()
    }

    private fun normalizedURL(rawValue: String?): String {
        val value = rawValue?.trim().orEmpty()
        return if (value.startsWith("//")) "https:$value" else value
    }

    private companion object {
        const val LIST_ENDPOINT = "toview.info.list"
        const val ADD_ENDPOINT = "toview.operate.add"
        const val DELETE_ENDPOINT = "toview.operate.del"
        const val CLEAR_ENDPOINT = "toview.operate.clear"
        const val DEFAULT_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
    }
}
