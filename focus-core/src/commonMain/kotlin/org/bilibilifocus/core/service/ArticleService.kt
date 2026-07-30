package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.ArticleAuthor
import org.bilibilifocus.core.model.ArticleDetail
import org.bilibilifocus.core.model.ArticleStats

class ArticleService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object LoginRequired : ServiceError("需要登录")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
        data object InvalidResponse : ServiceError("专栏接口返回无效数据")
        data object EmptyContent : ServiceError("专栏正文为空或暂时无法解析")
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchArticle(cvid: Long): ArticleDetail {
        val originalURL = "https://www.bilibili.com/read/cv$cvid"
        val endpoint = BiliApiContractCatalog.require("article.info.detail").url +
            "?id=$cvid&mobi_app=pc&from=web"
        val response = httpClient.get(
            endpoint,
            buildHeaders(endpoint, originalURL),
        )
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse
        val root = runCatching { json.parseToJsonElement(response.body) as? JsonObject }.getOrNull()
            ?: throw ServiceError.InvalidResponse
        val code = root["code"]?.jsonPrimitive?.int ?: throw ServiceError.InvalidResponse
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) throw ServiceError.Api(code, root["message"]?.jsonPrimitive?.content ?: "专栏加载失败")
        val data = root["data"]?.jsonObject ?: throw ServiceError.InvalidResponse

        val rawContent = data["content"]?.jsonPrimitive?.content.orEmpty()
        val blocks = ArticleContentParser.parse(rawContent)
        if (blocks.isEmpty()) throw ServiceError.EmptyContent

        val authorObj = data["author"] as? JsonObject
        val statsObj = data["stats"] as? JsonObject
        val mid = authorObj?.get("mid")?.jsonPrimitive?.long
            ?: data["mid"]?.jsonPrimitive?.long
            ?: 0L
        val authorName = authorObj?.get("name")?.jsonPrimitive?.content
            ?: data["author_name"]?.jsonPrimitive?.content
            ?: "作者"
        val authorFace = authorObj?.get("face")?.jsonPrimitive?.content
            ?: data["author_face"]?.jsonPrimitive?.content
            ?: ""

        return ArticleDetail(
            cvid = cvid,
            title = data["title"]?.jsonPrimitive?.content ?: "专栏",
            author = ArticleAuthor(mid, authorName, normalizedURL(authorFace)),
            publishTime = data["publish_time"]?.jsonPrimitive?.long
                ?: data["ctime"]?.jsonPrimitive?.long
                ?: 0L,
            stats = ArticleStats(
                views = statsObj?.get("view")?.jsonPrimitive?.long ?: 0L,
                likes = statsObj?.get("like")?.jsonPrimitive?.long ?: 0L,
                coins = statsObj?.get("coin")?.jsonPrimitive?.long ?: 0L,
                favorites = statsObj?.get("favorite")?.jsonPrimitive?.long ?: 0L,
                comments = statsObj?.get("reply")?.jsonPrimitive?.long ?: 0L,
            ),
            bannerUrl = normalizedURL(
                data["banner_url"]?.jsonPrimitive?.content
                    ?: firstString(data["origin_image_urls"])
                    ?: firstString(data["image_urls"])
                    ?: ""
            ),
            blocks = blocks,
            tags = parseTags(data),
            originalURL = originalURL,
        )
    }

    private suspend fun buildHeaders(targetUrl: String, referer: String): Map<String, String> {
        return cookieProvider.attachCookies(
            mapOf(
                "User-Agent" to "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Mobile Safari/537.36",
                "Referer" to referer,
                "Accept" to "application/json, text/plain, */*",
            ),
            targetUrl,
        )
    }

    private fun parseTags(data: JsonObject): List<String> {
        val values = mutableListOf<String>()
        (data["tags"] as? kotlinx.serialization.json.JsonArray)?.forEach { raw ->
            when (raw) {
                is JsonObject -> raw["name"]?.jsonPrimitive?.content?.let(values::add)
                else -> raw.jsonPrimitive.content.let(values::add)
            }
        }
        data["keywords"]?.jsonPrimitive?.content
            ?.split(',', '，')
            ?.map(String::trim)
            ?.filter(String::isNotEmpty)
            ?.let(values::addAll)
        data["category"]?.jsonObject?.get("name")?.jsonPrimitive?.content?.let(values::add)
        return values.distinct()
    }

    private fun firstString(element: JsonElement?): String? {
        if (element is JsonPrimitive) return element.contentOrNull?.takeIf(String::isNotBlank)
        val values = element as? JsonArray ?: return null
        for (value in values) {
            when (value) {
                is JsonPrimitive -> value.contentOrNull?.takeIf(String::isNotBlank)?.let { return it }
                is JsonObject -> listOf("self", "url", "src").firstNotNullOfOrNull { key ->
                    (value[key] as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)
                }?.let { return it }
                else -> Unit
            }
        }
        return null
    }

    private fun normalizedURL(raw: String): String = when {
        raw.startsWith("//") -> "https:$raw"
        raw.startsWith("http://") -> "https://${raw.removePrefix("http://")}"
        raw.startsWith("/") -> "https://www.bilibili.com$raw"
        else -> raw
    }
}
