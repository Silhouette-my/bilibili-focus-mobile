package org.bilibilifocus.core.service

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.DynamicCard

class FollowingAuthorsService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val pageSize: Int = 50,
    private val maxPages: Int = 200,
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object LoginRequired : ServiceError("需要登录后才能读取关注列表")
        data object InvalidResponse : ServiceError("关注列表返回无效数据")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchFollowingAuthors(): List<DynamicCard.Author> {
        val nav = requestObject(
            url = BiliApiContractCatalog.require("credential.info.valid").url,
            referer = "https://www.bilibili.com/",
        )
        val navCode = nav.intValueAt("code") ?: -1
        val currentMid = nav.longValueAt("data", "mid") ?: 0L
        val isLogin = nav.stringValueAt("data", "isLogin")?.toBooleanStrictOrNull()
        if (navCode == -101 || currentMid <= 0L || isLogin == false) {
            throw ServiceError.LoginRequired
        }
        if (navCode != 0) {
            throw ServiceError.Api(navCode, nav.stringValueAt("message") ?: "登录信息读取失败")
        }

        val authors = linkedMapOf<String, DynamicCard.Author>()
        val attentionAuthors = try {
            fetchAttentionAuthors(currentMid)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            emptyList()
        }
        attentionAuthors.forEach { author -> authors.getOrPut(authorKey(author)) { author } }

        val safePageSize = pageSize.coerceIn(1, 100)
        val safeMaxPages = maxPages.coerceAtLeast(1)
        var page = 1
        var expectedTotal: Int? = null

        while (page <= safeMaxPages) {
            val root = requestObject(
                url = BiliApiContractCatalog.require("user.info.followings").url +
                    "?vmid=$currentMid&pn=$page&ps=$safePageSize&order=desc&order_type=attention",
                referer = "https://space.bilibili.com/$currentMid/fans/follow",
            )
            val code = root.intValueAt("code") ?: -1
            if (code == -101) throw ServiceError.LoginRequired
            if (code != 0) {
                if (authors.isNotEmpty()) break
                throw ServiceError.Api(code, root.stringValueAt("message") ?: "关注列表加载失败")
            }

            if (expectedTotal == null) {
                expectedTotal = root.intValueAt("data", "total")
            }
            val pageAuthors = root.arrayValueAt("data", "list")
                .orEmpty()
                .mapNotNull { (it as? JsonObject)?.let(::makeAuthor) }
            pageAuthors.forEach { author -> authors.getOrPut(authorKey(author)) { author } }

            val reachedTotal = expectedTotal?.let { page * safePageSize >= it } ?: false
            if (pageAuthors.isEmpty() || pageAuthors.size < safePageSize || reachedTotal) break
            page += 1
        }

        return authors.values.toList()
    }

    private suspend fun fetchAttentionAuthors(mid: Long): List<DynamicCard.Author> {
        val root = requestObject(
            url = BiliApiContractCatalog.require("user.info.all_followings").url + "?mid=$mid",
            referer = "https://space.bilibili.com/$mid/fans/follow",
        )
        val code = root.intValueAt("code") ?: -1
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) throw ServiceError.Api(code, root.stringValueAt("message") ?: "特别关注列表加载失败")
        val items = root.arrayValueAt("data", "list")
            ?: root.arrayValueAt("data")
            ?: root.arrayValueAt("list")
            ?: emptyList()
        return items.mapNotNull { (it as? JsonObject)?.let(::makeAuthor) }
    }

    private fun makeAuthor(item: JsonObject): DynamicCard.Author? {
        val mid = item.longValueAt("mid") ?: item.longValueAt("uid") ?: 0L
        val name = item.stringValueAt("uname")?.trim().takeUnless { it.isNullOrEmpty() }
            ?: item.stringValueAt("name")?.trim().takeUnless { it.isNullOrEmpty() }
            ?: "UP主"
        if (mid <= 0L && name == "UP主") return null
        return DynamicCard.Author(
            name = name,
            mid = mid,
            avatarURL = normalizedURL(item.stringValueAt("face") ?: item.stringValueAt("avatar")),
        )
    }

    private suspend fun requestObject(url: String, referer: String): JsonObject {
        val headers = cookieProvider.attachCookies(
            mapOf(
                "User-Agent" to userAgent,
                "Accept" to "application/json, text/plain, */*",
                "Referer" to referer,
            ),
            url,
        )
        val response = httpClient.get(url, headers)
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse
        return try {
            json.parseToJsonElement(response.body) as? JsonObject
        } catch (_: Exception) {
            null
        } ?: throw ServiceError.InvalidResponse
    }

    private fun normalizedURL(raw: String?): String? {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty()) return null
        return when {
            value.startsWith("//") -> "https:$value"
            value.startsWith("http://") -> "https://${value.removePrefix("http://")}"
            else -> value
        }
    }

    private fun authorKey(author: DynamicCard.Author): String =
        if (author.mid > 0L) "mid:${author.mid}" else "name:${author.name}"
}
