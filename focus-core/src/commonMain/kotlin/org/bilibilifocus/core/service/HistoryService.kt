package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.HistoryItem
import org.bilibilifocus.core.model.HistoryPage

/**
 * 播放历史。基于 x/web-interface/history/cursor（需登录 cookie，无需 WBI 签名）。
 * 支持游标翻页：把上一页返回的 nextMax/nextViewAt/nextBusiness 传回即可取下一页。
 */
class HistoryService(
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

    suspend fun fetchHistory(
        max: Long = 0,
        viewAt: Long = 0,
        business: String = "",
    ): HistoryPage {
        val params = buildString {
            append("ps=20")
            if (max > 0) append("&max=$max")
            if (business.isNotEmpty()) append("&business=${rfc3986Encode(business)}")
            if (viewAt > 0) append("&view_at=$viewAt")
        }
        val url = BiliApiContractCatalog.require("user.info.history_new").url + "?$params"

        val response = httpClient.get(url, buildHeaders(url))
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse

        val payload = json.parseToJsonElement(response.body) as? JsonObject
            ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: -1
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) throw ServiceError.Api(code, payload.stringValueAt("message") ?: "未知错误")

        val data = payload.dictionaryValueAt("data") ?: throw ServiceError.InvalidResponse
        val list = payload.arrayValueAt("data", "list") ?: emptyList()
        val items = list.mapNotNull { element ->
            val dict = element as? JsonObject ?: return@mapNotNull null
            val history = dict.dictionaryValueAt("history")
            val cover = dict.stringValueAt("cover")?.takeIf { it.isNotEmpty() }
                ?: (dict.arrayValueAt("covers")?.firstOrNull() as? kotlinx.serialization.json.JsonPrimitive)?.content
                ?: ""
            HistoryItem(
                title = dict.stringValueAt("title") ?: "",
                coverURL = cover,
                bvid = history?.stringValueAt("bvid") ?: "",
                cid = history?.longValueAt("cid") ?: 0L,
                page = history?.longValueAt("page")?.toInt() ?: 0,
                authorName = dict.stringValueAt("author_name") ?: "",
                viewAt = dict.longValueAt("view_at") ?: 0L,
                progress = dict.longValueAt("progress") ?: 0L,
                duration = dict.longValueAt("duration") ?: 0L,
            )
        }

        return HistoryPage(
            items = items,
            nextMax = data.longValueAt("cursor", "max") ?: 0L,
            nextViewAt = data.longValueAt("cursor", "view_at") ?: 0L,
            nextBusiness = data.stringValueAt("cursor", "business") ?: "",
        )
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
