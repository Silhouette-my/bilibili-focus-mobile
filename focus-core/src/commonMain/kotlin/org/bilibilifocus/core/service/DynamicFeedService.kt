package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.DynamicCard
import org.bilibilifocus.core.routing.ArticleURL

class DynamicFeedService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val timezoneOffsetMinutes: Int = currentTimezoneOffsetMinutes(),
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
) {
    data class FeedPage(
        val cards: List<DynamicCard>,
        val nextOffset: String?,
    )

    sealed class ServiceError(message: String) : Exception(message) {
        data object LoginRequired : ServiceError("需要登录或登录已失效")
        data object InvalidResponse : ServiceError("动态接口返回无效数据")
        data class Api(val code: Int, override val message: String) :
            ServiceError(message)
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchFollowingFeed(): List<DynamicCard> =
        fetchFollowingFeedPage().cards

    suspend fun fetchFollowingFeedPage(offset: String? = null): FeedPage {
        val cookies = cookieProvider.loadCookies()
        if (cookies.isEmpty()) throw ServiceError.LoginRequired

        val url = buildEndpoint(offset)
        val headers = buildHeaders(cookies)
        val response = httpClient.get(url, headers)

        if (response.statusCode !in 200..299) {
            throw ServiceError.InvalidResponse
        }

        return decodeFeedPage(response.body)
    }

    internal fun buildEndpoint(offset: String?): String {
        val sb = StringBuilder("https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all")
        sb.append("?type=all")
        sb.append("&timezone_offset=$timezoneOffsetMinutes")
        sb.append("&features=itemOpusStyle")
        if (!offset.isNullOrEmpty()) {
            sb.append("&offset=$offset")
        }
        return sb.toString()
    }

    private fun buildHeaders(cookies: List<Cookie>): Map<String, String> {
        return mapOf(
            "Referer" to "https://t.bilibili.com/",
            "Accept" to "application/json, text/plain, */*",
            "User-Agent" to userAgent,
        ).let { cookieProvider.attachCookies(it, cookies) }
    }

    fun decodeFeedPage(rawJson: String): FeedPage {
        val payload = try {
            json.parseToJsonElement(rawJson) as? JsonObject
        } catch (_: Exception) {
            throw ServiceError.InvalidResponse
        } ?: throw ServiceError.InvalidResponse

        val code = payload.intValueAt("code") ?: -1
        val message = payload.stringValueAt("message") ?: "unknown"

        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) throw ServiceError.Api(code, message)

        val items = payload.arrayValueAt("data", "items")
        val cards = items?.mapNotNull { element ->
            val dict = element as? JsonObject ?: return@mapNotNull null
            makeCard(dict)
        } ?: emptyList()

        val nextOffset = payload.stringValueAt("data", "offset")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

        return FeedPage(cards, nextOffset)
    }

    private fun makeCard(item: JsonObject): DynamicCard? {
        val modules = item.dictionaryValueAt("modules") ?: JsonObject(emptyMap())
        val author = modules.dictionaryValueAt("module_author") ?: JsonObject(emptyMap())
        val dynamic = modules.dictionaryValueAt("module_dynamic") ?: JsonObject(emptyMap())
        val major = dynamic.dictionaryValueAt("major") ?: JsonObject(emptyMap())
        val basic = item.dictionaryValueAt("basic") ?: JsonObject(emptyMap())

        val id = item.stringValueAt("id_str")
            ?: basic.stringValueAt("comment_id_str")
            ?: basic.stringValueAt("rid_str")
            ?: basic.intValueAt("comment_id")?.toString()
            ?: return null

        val authorName = author.stringValueAt("name") ?: "Bilibili"
        val authorMid = author.intValueAt("mid")?.toLong() ?: 0L
        val authorAvatar = normalizedURL(author.stringValueAt("face"))
        val publishTime = author.stringValueAt("pub_time")
            ?: author.stringValueAt("pub_action")
            ?: author.stringValueAt("pub_time_label")
            ?: ""

        val majorType = major.stringValueAt("type") ?: ""

        val primaryJumpCandidates = listOfNotNull(
            normalizedURL(basic.stringValueAt("jump_url")),
            normalizedURL(major.stringValueAt("archive", "jump_url")),
            normalizedURL(major.stringValueAt("article", "jump_url")),
            normalizedURL(major.stringValueAt("pgc", "jump_url")),
            normalizedURL(major.stringValueAt("courses", "jump_url")),
            normalizedURL(major.stringValueAt("music", "jump_url")),
            normalizedURL(major.stringValueAt("medialist", "jump_url")),
            normalizedURL(major.stringValueAt("live", "jump_url")),
            normalizedURL(major.stringValueAt("opus", "jump_url")),
            normalizedURL(major.stringValueAt("common", "jump_url")),
        )
        val jumpCandidates = primaryJumpCandidates + extractJumpURLs(major)

        val coverURLs = makeCoverURLs(major)
        val text = makeText(dynamic, major)
        val videoURL = jumpCandidates.firstOrNull { isVideoLikeURL(it) }
        val kind = makeKind(majorType, item.stringValueAt("type") ?: "", videoURL, coverURLs)
        val articleCvid = major.stringValueAt("article", "id")?.toLongOrNull()
            ?: major.stringValueAt("article", "id_str")?.toLongOrNull()
            ?: major.stringValueAt("article", "cvid")?.toLongOrNull()
            ?: major.intValueAt("article", "id")?.toLong()
            ?: jumpCandidates.firstNotNullOfOrNull(ArticleURL::extractCvid)
        val articleURL = if (kind == DynamicCard.Kind.ARTICLE_LIKE) {
            jumpCandidates.firstOrNull { ArticleURL.extractCvid(it) != null }
                ?.let(ArticleURL::canonicalURL)
                ?: articleCvid?.let(ArticleURL::canonicalURL)
        } else {
            null
        }
        val opusDetailURL = primaryJumpCandidates.firstOrNull(::isOpusLikeURL)
        val targetURL = when (kind) {
            DynamicCard.Kind.VIDEO -> videoURL
                ?: primaryJumpCandidates.firstOrNull()
                ?: jumpCandidates.firstOrNull()
                ?: fallbackTargetURL(id, kind)
            DynamicCard.Kind.ARTICLE_LIKE -> articleURL
                ?: opusDetailURL
                ?: primaryJumpCandidates.firstOrNull()
                ?: jumpCandidates.firstOrNull()
                ?: fallbackTargetURL(id, kind)
            DynamicCard.Kind.TEXT,
            DynamicCard.Kind.IMAGE,
            -> opusDetailURL ?: fallbackTargetURL(id, kind)
        }

        return DynamicCard(
            id = id,
            kind = kind,
            author = DynamicCard.Author(name = authorName, mid = authorMid, avatarURL = authorAvatar),
            publishTime = publishTime,
            text = text,
            coverURLs = coverURLs,
            targetURL = targetURL,
            videoURL = videoURL,
        )
    }

    private fun makeText(dynamic: JsonObject, major: JsonObject): String {
        val bodyCandidates = listOfNotNull(
            richTextPlainText(dynamic.arrayValueAt("desc", "rich_text_nodes")),
            richTextPlainText(dynamic.arrayValueAt("desc", "rich_text_nodes_v2")),
            dynamic.stringValueAt("desc", "text"),
            richTextPlainText(major.arrayValueAt("opus", "summary", "rich_text_nodes")),
            richTextPlainText(major.arrayValueAt("opus", "summary", "rich_text_nodes_v2")),
            major.stringValueAt("opus", "summary", "text"),
        ).mapNotNull { it.trim().takeIf(String::isNotEmpty) }

        bodyCandidates.maxByOrNull(String::length)?.let { return it }

        val candidates = listOfNotNull(
            major.stringValueAt("archive", "title"),
            major.stringValueAt("article", "title"),
            major.stringValueAt("pgc", "title"),
            major.stringValueAt("courses", "title"),
            major.stringValueAt("music", "title"),
            major.stringValueAt("medialist", "title"),
            major.stringValueAt("live", "title"),
            major.stringValueAt("common", "title"),
        ) + extractTextCandidates(major)

        return candidates
            .mapNotNull { it?.trim()?.takeIf { t -> t.isNotEmpty() } }
            .firstOrNull() ?: ""
    }

    private fun richTextPlainText(nodes: List<JsonElement>?): String? {
        if (nodes.isNullOrEmpty()) return null
        val text = buildString {
            nodes.forEach { node ->
                val dict = node as? JsonObject ?: return@forEach
                append(
                    dict.stringValueAt("word", "words")
                        ?: dict.stringValueAt("words")
                        ?: dict.stringValueAt("text")
                        ?: dict.stringValueAt("orig_text")
                        ?: dict.stringValueAt("rich", "text")
                        ?: dict.stringValueAt("rich", "emoji", "text")
                        ?: dict.stringValueAt("emoji", "text")
                        ?: ""
                )
            }
        }
        return text.takeIf(String::isNotBlank)
    }

    private fun makeCoverURLs(major: JsonObject): List<String> {
        val urls = mutableListOf<String>()

        normalizedURL(major.stringValueAt("archive", "cover"))?.let { urls.add(it) }
        major.arrayValueAt("article", "covers")?.forEach { cover ->
            (cover as? kotlinx.serialization.json.JsonPrimitive)?.content?.let { normalizedURL(it) }?.let { urls.add(it) }
        }
        normalizedURL(major.stringValueAt("pgc", "cover") ?: major.stringValueAt("pgc", "ep_cover"))
            ?.let { urls.add(it) }
        normalizedURL(major.stringValueAt("courses", "cover"))?.let { urls.add(it) }
        normalizedURL(major.stringValueAt("music", "cover"))?.let { urls.add(it) }
        normalizedURL(major.stringValueAt("medialist", "cover"))?.let { urls.add(it) }
        normalizedURL(
            major.stringValueAt("live", "cover") ?: major.stringValueAt("live", "room_cover")
        )?.let { urls.add(it) }

        major.arrayValueAt("draw", "items")?.forEach { item ->
            val dict = item as? JsonObject ?: return@forEach
            normalizedURL(dict.stringValueAt("src") ?: dict.stringValueAt("url"))?.let { urls.add(it) }
        }

        major.arrayValueAt("opus", "pics")?.forEach { picture ->
            val dict = picture as? JsonObject ?: return@forEach
            normalizedURL(dict.stringValueAt("url") ?: dict.stringValueAt("src"))?.let { urls.add(it) }
        }

        normalizedURL(major.stringValueAt("common", "cover"))?.let { urls.add(it) }
        urls.addAll(extractImageURLs(major))

        return urls.distinct()
    }

    private fun makeKind(
        majorType: String,
        itemType: String,
        videoURL: String?,
        coverURLs: List<String>,
    ): DynamicCard.Kind {
        if (videoURL != null ||
            itemType.contains("_AV") ||
            majorType in setOf(
                "MAJOR_TYPE_ARCHIVE", "MAJOR_TYPE_PGC",
                "MAJOR_TYPE_COURSES", "MAJOR_TYPE_MEDIALIST",
            )
        ) {
            return DynamicCard.Kind.VIDEO
        }

        return when (majorType) {
            "MAJOR_TYPE_DRAW", "MAJOR_TYPE_OPUS" ->
                if (coverURLs.isEmpty()) DynamicCard.Kind.TEXT else DynamicCard.Kind.IMAGE
            "MAJOR_TYPE_ARTICLE" -> DynamicCard.Kind.ARTICLE_LIKE
            else -> if (coverURLs.isEmpty()) DynamicCard.Kind.TEXT else DynamicCard.Kind.IMAGE
        }
    }

    private fun normalizedURL(rawValue: String?): String? {
        if (rawValue == null) return null
        var value = rawValue.trim()
        if (value.isEmpty()) return null

        canonicalOpusURLFromScheme(value)?.let { return it }

        value = when {
            value.startsWith("//") -> "https:$value"
            value.startsWith("/opus/") || value.startsWith("/video/") ||
                value.startsWith("/bangumi/play/") -> "https://www.bilibili.com$value"
            value.startsWith("/") -> "https://t.bilibili.com$value"
            else -> value
        }

        return org.bilibilifocus.core.routing.FocusNavigationPolicy.canonicalWebURL(value)
    }

    private fun canonicalOpusURLFromScheme(value: String): String? {
        val match = opusSchemePattern.find(value) ?: return null
        return "https://www.bilibili.com/opus/${match.groupValues[1]}"
    }

    private fun isOpusLikeURL(url: String): Boolean {
        val lower = url.lowercase()
        val marker = "/opus/"
        val markerIndex = lower.indexOf(marker)
        if (markerIndex < 0 || "bilibili.com" !in lower.substring(0, markerIndex)) return false
        val candidate = lower.substring(markerIndex + marker.length)
            .substringBefore('?')
            .substringBefore('#')
            .trimEnd('/')
        return candidate.isNotEmpty() && candidate.all { it.isDigit() }
    }

    private fun isVideoLikeURL(url: String): Boolean {
        val path = url.lowercase().let { u ->
            u.substringAfter("bilibili.com", u).substringBefore("?")
        }
        return path.startsWith("/video/") || path.startsWith("/bangumi/play/")
    }

    private fun extractJumpURLs(major: JsonObject): List<String> {
        return extractURLs(major, urlKeyPatterns, maxDepth = 4) { isLikelyNavigationURL(it) }
    }

    private fun extractImageURLs(major: JsonObject): List<String> {
        return extractURLs(major, imageKeyPatterns, maxDepth = 4) { isLikelyImageURL(it) }
    }

    private fun extractTextCandidates(major: JsonObject): List<String?> {
        val results = mutableListOf<String>()
        collectTextCandidates(major, textKeyPatterns, maxDepth = 4, results)
        return results.distinctBy { it.trim().lowercase() }
            .filter { trimmed ->
                val t = trimmed.trim()
                t.isNotEmpty() && !t.contains("http://") && !t.contains("https://")
            }
    }

    private fun extractURLs(
        element: JsonElement,
        keys: Set<String>,
        maxDepth: Int,
        predicate: (String) -> Boolean,
    ): List<String> {
        val results = mutableListOf<String>()
        collectURLs(element, keys, maxDepth, predicate, results)
        return results.distinct()
    }

    private fun collectURLs(
        element: JsonElement,
        keys: Set<String>,
        maxDepth: Int,
        predicate: (String) -> Boolean,
        results: MutableList<String>,
    ) {
        if (maxDepth < 0) return

        when (element) {
            is JsonObject -> {
                for ((key, value) in element) {
                    if (key.lowercase() in keys && value is kotlinx.serialization.json.JsonPrimitive) {
                        val raw = value.content
                        if (predicate(raw)) {
                            normalizedURL(raw)?.let { results.add(it) }
                        }
                    }
                    collectURLs(value, keys, maxDepth - 1, predicate, results)
                }
            }
            is JsonArray -> {
                for (item in element) {
                    collectURLs(item, keys, maxDepth - 1, predicate, results)
                }
            }
            else -> {}
        }
    }

    private fun collectTextCandidates(
        element: JsonElement,
        keys: Set<String>,
        maxDepth: Int,
        results: MutableList<String>,
    ) {
        if (maxDepth < 0) return

        when (element) {
            is JsonObject -> {
                for ((key, value) in element) {
                    if (key.lowercase() in keys && value is kotlinx.serialization.json.JsonPrimitive) {
                        results.add(value.content)
                    }
                    collectTextCandidates(value, keys, maxDepth - 1, results)
                }
            }
            is JsonArray -> {
                for (item in element) {
                    collectTextCandidates(item, keys, maxDepth - 1, results)
                }
            }
            else -> {}
        }
    }

    private fun isLikelyNavigationURL(rawValue: String): Boolean {
        val url = normalizedURL(rawValue) ?: return false
        if (!url.contains("bilibili.com")) return false
        return !isLikelyImageURL(url)
    }

    private fun isLikelyImageURL(rawValue: String): Boolean {
        val url = normalizedURL(rawValue) ?: return false
        val lower = url.lowercase()
        if ("hdslb.com" in lower) return true
        val imageExtensions = listOf(".jpg", ".jpeg", ".png", ".webp", ".avif", ".gif", ".bmp")
        if (imageExtensions.any { lower.endsWith(it) }) return true
        return "/bfs/" in lower
    }

    private fun fallbackTargetURL(id: String, kind: DynamicCard.Kind): String = when (kind) {
        DynamicCard.Kind.VIDEO -> "https://t.bilibili.com/$id"
        else -> "https://www.bilibili.com/opus/$id"
    }

    companion object {
        private val opusSchemePattern = Regex(
            """^bilibili://(?:following/detail|opus/detail|dynamic)/(\d+)(?:[/?#].*)?$""",
            RegexOption.IGNORE_CASE,
        )
        private val urlKeyPatterns = setOf(
            "jump_url", "url", "link", "target_url", "target", "schema",
        )
        private val imageKeyPatterns = setOf(
            "cover", "src", "url", "image", "img", "pic", "poster",
        )
        private val textKeyPatterns = setOf(
            "title", "text", "content", "desc", "summary", "copy_text", "name",
        )
    }
}
