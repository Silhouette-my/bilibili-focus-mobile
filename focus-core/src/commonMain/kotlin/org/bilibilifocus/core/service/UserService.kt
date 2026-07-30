package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.UserArticle
import org.bilibilifocus.core.model.UserCollectionPage
import org.bilibilifocus.core.model.UserContentCollection
import org.bilibilifocus.core.model.UserProfile
import org.bilibilifocus.core.model.UserVideo
import org.bilibilifocus.core.model.UserVideoPage

class UserService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    private val wbiSigner: WbiSigner = WbiSigner(cookieProvider, httpClient, userAgent),
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object InvalidResponse : ServiceError("接口返回无效数据")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
        data object SigningUnavailable : ServiceError("签名初始化失败")
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchUserInfo(mid: Long): UserProfile {
        val payload = requestWbiObject(
            endpoint = BiliApiContractCatalog.require("user.info.info").url,
            parameters = mapOf("mid" to mid.toString(), "w_webid" to ""),
            referer = "https://space.bilibili.com/$mid",
        ) ?: throw ServiceError.InvalidResponse
        requireSuccessful(payload)

        val data = payload.dictionaryValueAt("data") ?: throw ServiceError.InvalidResponse
        return UserProfile(
            mid = data.longValueAt("mid") ?: mid,
            name = data.stringValueAt("name") ?: "",
            avatarURL = normalizedURL(data.stringValueAt("face")),
            sign = data.stringValueAt("sign") ?: "",
            level = data.intValueAt("level") ?: data.intValueAt("level_info", "current_level") ?: 0,
            following = 0,
            followers = 0,
            videoCount = data.intValueAt("archive_count") ?: data.intValueAt("archive") ?: 0,
            articleCount = data.intValueAt("article_count") ?: data.intValueAt("article") ?: 0,
        )
    }

    suspend fun fetchRelationInfo(mid: Long): Pair<Long, Long> {
        val payload = requestObject(
            url = BiliApiContractCatalog.require("user.info.relation_stat").url + "?vmid=$mid",
            referer = "https://space.bilibili.com/$mid",
        ) ?: return 0L to 0L
        val data = payload.dictionaryValueAt("data") ?: return 0L to 0L
        return (data.longValueAt("following") ?: 0L) to (data.longValueAt("follower") ?: 0L)
    }

    suspend fun fetchUserVideos(mid: Long, page: Int = 1, pageSize: Int = 30): List<UserVideo> =
        fetchUserVideoPage(mid, page, pageSize).items

    suspend fun fetchUserVideoPage(mid: Long, page: Int = 1, pageSize: Int = 12): UserVideoPage {
        val ps = pageSize.coerceIn(1, 50)
        val pn = page.coerceAtLeast(1)
        val payload = requestWbiObject(
            endpoint = BiliApiContractCatalog.require("user.info.video").url,
            parameters = mapOf(
                "mid" to mid.toString(),
                "ps" to ps.toString(),
                "pn" to pn.toString(),
                "tid" to "0",
                "keyword" to "",
                "order" to "pubdate",
                "order_avoided" to "true",
                "platform" to "web",
            ),
            referer = "https://space.bilibili.com/$mid",
        ) ?: return UserVideoPage(0, emptyList(), null)
        if (payload.intValueAt("code") != 0) return UserVideoPage(0, emptyList(), null)

        val items = payload.arrayValueAt("data", "list", "vlist")
            .orEmpty()
            .mapNotNull { (it as? JsonObject)?.let(::mapUserVideo) }
        val totalCount = payload.intValueAt("data", "page", "count")
            ?: payload.intValueAt("data", "page", "total")
            ?: items.size
        val nextPage = if (items.isNotEmpty() && (pn * ps < totalCount || items.size >= ps)) pn + 1 else null
        return UserVideoPage(totalCount, items, nextPage)
    }

    suspend fun fetchUserCollections(mid: Long): List<UserContentCollection> {
        val payload = requestWbiObject(
            endpoint = BiliApiContractCatalog.require("user.info.channel_list").url,
            parameters = mapOf(
                "mid" to mid.toString(),
                "page_num" to "1",
                "page_size" to "10",
            ),
            referer = "https://space.bilibili.com/$mid",
        ) ?: return emptyList()
        if (payload.intValueAt("code") != 0) return emptyList()

        val seasons = payload.arrayValueAt("data", "items_lists", "seasons_list").orEmpty()
        val series = payload.arrayValueAt("data", "items_lists", "series_list").orEmpty()
        return seasons.mapNotNull { element ->
            (element as? JsonObject)?.let { mapCollection(it, mid, UserContentCollection.Kind.SEASON) }
        } + series.mapNotNull { element ->
            (element as? JsonObject)?.let { mapCollection(it, mid, UserContentCollection.Kind.SERIES) }
        }
    }

    suspend fun fetchUserArticles(mid: Long): List<UserArticle> {
        val payload = requestWbiObject(
            endpoint = BiliApiContractCatalog.require("user.info.article").url,
            parameters = mapOf(
                "mid" to mid.toString(),
                "pn" to "1",
                "ps" to "8",
                "sort" to "publish_time",
            ),
            referer = "https://space.bilibili.com/$mid",
        ) ?: return emptyList()
        if (payload.intValueAt("code") != 0) return emptyList()

        val items = payload.arrayValueAt("data", "articles")
            ?: payload.arrayValueAt("data", "list")
            ?: emptyList()
        return items.mapNotNull { element ->
            val item = element as? JsonObject ?: return@mapNotNull null
            val id = item.longValueAt("id")
                ?: item.longValueAt("cvid")
                ?: item.longValueAt("cv")
                ?: return@mapNotNull null
            UserArticle(
                id = id,
                title = cleanText(item.stringValueAt("title")).ifEmpty { "专栏" },
                summary = cleanText(item.stringValueAt("summary") ?: item.stringValueAt("description")),
                coverURL = normalizedURL(
                    item.stringValueAt("banner_url")
                        ?: item.stringValueAt("image_url")
                        ?: firstString(item["image_urls"])
                        ?: firstString(item["covers"])
                ),
                publishedAt = item.longValueAt("publish_time_seconds")
                    ?: item.longValueAt("publish_time")
                    ?: item.longValueAt("ctime")
                    ?: 0L,
                viewCount = item.longValueAt("stats", "view") ?: item.longValueAt("view") ?: 0L,
                targetURL = normalizedURL(item.stringValueAt("share_url"))
                    .ifEmpty { "https://www.bilibili.com/read/cv$id" },
            )
        }
    }

    suspend fun fetchUserCollectionPage(
        collection: UserContentCollection,
        page: Int = 1,
        pageSize: Int = 20,
    ): UserCollectionPage {
        val pn = page.coerceAtLeast(1)
        val ps = pageSize.coerceIn(1, 50)
        val parameters = when (collection.kind) {
            UserContentCollection.Kind.SEASON ->
                mapOf(
                    "mid" to collection.ownerMid.toString(),
                    "season_id" to collection.rawId.toString(),
                    "sort_reverse" to "false",
                    "page_num" to pn.toString(),
                    "page_size" to ps.toString(),
                )
            UserContentCollection.Kind.SERIES ->
                mapOf(
                    "mid" to collection.ownerMid.toString(),
                    "series_id" to collection.rawId.toString(),
                    "pn" to pn.toString(),
                    "ps" to ps.toString(),
                    "sort" to "desc",
                )
        }
        val endpoint = when (collection.kind) {
            UserContentCollection.Kind.SEASON ->
                BiliApiContractCatalog.require("user.info.channel_video_season").url
            UserContentCollection.Kind.SERIES ->
                BiliApiContractCatalog.require("user.info.channel_video_series").url
        }
        val payload = requestWbiObject(
            endpoint = endpoint,
            parameters = parameters,
            referer = "https://space.bilibili.com/${collection.ownerMid}",
        ) ?: return UserCollectionPage(collection, emptyList(), null)
        if (payload.intValueAt("code") != 0) return UserCollectionPage(collection, emptyList(), null)

        val rawItems = payload.arrayValueAt("data", "archives")
            ?: payload.arrayValueAt("data", "list", "archives")
            ?: payload.arrayValueAt("data", "items")
            ?: emptyList()
        val videos = rawItems.mapNotNull { (it as? JsonObject)?.let(::mapUserVideo) }
        val totalCount = payload.intValueAt("data", "page", "total")
            ?: payload.intValueAt("data", "page", "count")
            ?: payload.intValueAt("data", "meta", "total")
            ?: collection.itemCount
        val nextPage = if (videos.isNotEmpty() && (pn * ps < totalCount || videos.size >= ps)) pn + 1 else null
        return UserCollectionPage(collection, videos, nextPage)
    }

    private fun mapUserVideo(item: JsonObject): UserVideo? {
        val bvid = item.stringValueAt("bvid")?.trim().orEmpty()
        if (bvid.isEmpty()) return null
        return UserVideo(
            aid = item.longValueAt("aid") ?: 0L,
            bvid = bvid,
            title = cleanText(item.stringValueAt("title")).ifEmpty { "视频" },
            coverURL = normalizedURL(item.stringValueAt("pic") ?: item.stringValueAt("cover")),
            playCount = item.longValueAt("play") ?: item.longValueAt("stat", "view") ?: 0L,
            danmakuCount = item.longValueAt("video_review") ?: item.longValueAt("stat", "danmaku") ?: 0L,
            duration = formatDuration(
                raw = item.stringValueAt("length"),
                seconds = item.longValueAt("duration"),
            ),
            created = item.longValueAt("created")
                ?: item.longValueAt("pubdate")
                ?: item.longValueAt("ptime")
                ?: item.longValueAt("ctime")
                ?: 0L,
            author = item.stringValueAt("author") ?: item.stringValueAt("owner", "name") ?: "",
        )
    }

    private fun mapCollection(
        item: JsonObject,
        mid: Long,
        kind: UserContentCollection.Kind,
    ): UserContentCollection? {
        val meta = item.dictionaryValueAt("meta") ?: item
        val rawId = when (kind) {
            UserContentCollection.Kind.SEASON -> meta.longValueAt("season_id")
            UserContentCollection.Kind.SERIES -> meta.longValueAt("series_id")
        } ?: return null
        val count = meta.intValueAt("total")
            ?: meta.intValueAt("archives_count")
            ?: meta.intValueAt("media_count")
            ?: item.arrayValueAt("archives")?.size
            ?: 0
        return UserContentCollection(
            id = "${kind.name.lowercase()}-$rawId",
            ownerMid = mid,
            rawId = rawId,
            kind = kind,
            title = meta.stringValueAt("name")?.trim().takeUnless { it.isNullOrEmpty() }
                ?: meta.stringValueAt("title")?.trim().takeUnless { it.isNullOrEmpty() }
                ?: kind.title,
            description = meta.stringValueAt("description")?.trim().takeUnless { it.isNullOrEmpty() }
                ?: meta.stringValueAt("desc")?.trim().takeUnless { it.isNullOrEmpty() }
                ?: meta.stringValueAt("intro")?.trim().orEmpty(),
            coverURL = normalizedURL(meta.stringValueAt("cover") ?: meta.stringValueAt("image")),
            itemCount = count,
            updatedAt = meta.longValueAt("mtime")
                ?: meta.longValueAt("ctime")
                ?: meta.longValueAt("pub_time")
                ?: 0L,
        )
    }

    private suspend fun requestWbiObject(
        endpoint: String,
        parameters: Map<String, String>,
        referer: String,
    ): JsonObject? {
        val result = try {
            wbiSigner.execute(parameters) { signedQuery ->
                val url = "$endpoint?$signedQuery"
                val response = httpClient.get(url, buildHeaders(url, referer))
                val payload = parseObject(response.body)
                WbiRequestResult(
                    value = payload,
                    httpStatusCode = response.statusCode,
                    apiCode = payload?.intValueAt("code"),
                )
            }
        } catch (_: WbiSigner.SigningUnavailable) {
            throw ServiceError.SigningUnavailable
        }
        if (result.httpStatusCode !in 200..299) return null
        return result.value
    }

    private suspend fun requestObject(url: String, referer: String): JsonObject? {
        val response = httpClient.get(url, buildHeaders(url, referer))
        if (response.statusCode !in 200..299) return null
        return parseObject(response.body)
    }

    private fun parseObject(body: String): JsonObject? = try {
        json.parseToJsonElement(body) as? JsonObject
    } catch (_: Exception) {
        null
    }

    private fun requireSuccessful(payload: JsonObject) {
        val code = payload.intValueAt("code") ?: -1
        if (code != 0) {
            throw ServiceError.Api(code, payload.stringValueAt("message") ?: "未知错误")
        }
    }

    private fun formatDuration(raw: String?, seconds: Long?): String {
        val normalizedRaw = raw?.trim().orEmpty()
        if (normalizedRaw.isNotEmpty()) {
            val parts = normalizedRaw.split(":")
            return when (parts.size) {
                2 -> "${parts[0].toIntOrNull() ?: 0}:${parts[1].padStart(2, '0')}"
                3 -> "${parts[0].toIntOrNull() ?: 0}:${parts[1].padStart(2, '0')}:${parts[2].padStart(2, '0')}"
                else -> normalizedRaw
            }
        }
        val value = seconds ?: return ""
        if (value <= 0) return ""
        val hours = value / 3600
        val minutes = (value % 3600) / 60
        val remaining = value % 60
        return if (hours > 0) {
            "$hours:${minutes.toString().padStart(2, '0')}:${remaining.toString().padStart(2, '0')}"
        } else {
            "${minutes.toString().padStart(2, '0')}:${remaining.toString().padStart(2, '0')}"
        }
    }

    private fun cleanText(raw: String?): String = raw
        ?.replace(Regex("<[^>]+>"), "")
        ?.trim()
        .orEmpty()

    private fun normalizedURL(raw: String?): String {
        val value = raw?.trim().orEmpty()
        return when {
            value.startsWith("//") -> "https:$value"
            value.startsWith("http://") -> "https://${value.removePrefix("http://")}"
            else -> value
        }
    }

    private fun firstString(element: JsonElement?): String? = when (element) {
        is JsonPrimitive -> element.content.takeIf { it.isNotBlank() }
        is JsonArray -> element.firstNotNullOfOrNull(::firstString)
        is JsonObject -> element.stringValueAt("url")
            ?: element.stringValueAt("src")
            ?: element.values.firstNotNullOfOrNull(::firstString)
        else -> null
    }

    private suspend fun buildHeaders(targetUrl: String, referer: String): Map<String, String> {
        val headers = mapOf(
            "User-Agent" to userAgent,
            "Referer" to referer,
            "Accept" to "application/json, text/plain, */*",
        )
        return cookieProvider.attachCookies(headers, targetUrl)
    }

}
