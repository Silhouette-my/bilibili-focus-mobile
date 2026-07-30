package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.SearchQuery
import org.bilibilifocus.core.model.SearchResultFilter
import org.bilibilifocus.core.model.SearchResultItem
import org.bilibilifocus.core.model.SearchResultPage
import org.bilibilifocus.core.model.SearchResultSection
import org.bilibilifocus.core.model.SearchVideoSortOption
import org.bilibilifocus.core.routing.FocusNavigationPolicy
import kotlin.math.roundToLong

class SearchResultService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
    private val wbiSigner: WbiSigner = WbiSigner(cookieProvider, httpClient, userAgent),
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object InvalidResponse : ServiceError("搜索接口返回无效数据")
        data class Api(val code: Int, override val message: String) :
            ServiceError(message)
        data object SigningUnavailable : ServiceError("搜索签名初始化失败")
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchPage(
        query: SearchQuery,
        filter: SearchResultFilter = SearchResultFilter.ALL,
        page: Int = 1,
        videoSort: SearchVideoSortOption = SearchVideoSortOption.DEFAULT,
    ): SearchResultPage {
        val parameters = buildMap {
            put("keyword", query.keyword)
            if (filter != SearchResultFilter.ALL) {
                filter.apiSearchType?.let { put("search_type", it) }
                put("page", maxOf(page, 1).toString())
            }
            if (filter == SearchResultFilter.VIDEO) {
                videoSort.apiOrderValue?.let { put("order", it) }
            }
        }
        val endpoint = if (filter == SearchResultFilter.ALL) {
            BiliApiContractCatalog.require("search.search.web_search").url
        } else {
            BiliApiContractCatalog.require("search.search.web_search_by_type").url
        }
        val result = try {
            wbiSigner.execute(parameters) { signedQuery ->
                val url = "$endpoint?$signedQuery"
                val response = httpClient.get(url, buildHeaders(query, url))
                val apiCode = runCatching {
                    (json.parseToJsonElement(response.body) as? JsonObject)?.intValueAt("code")
                }.getOrNull()
                WbiRequestResult(response, response.statusCode, apiCode)
            }
        } catch (_: WbiSigner.SigningUnavailable) {
            throw ServiceError.SigningUnavailable
        }
        val response = result.value
        if (response.statusCode !in 200..299) {
            throw ServiceError.InvalidResponse
        }
        return decodePage(response.body, query, filter, page)
    }

    private suspend fun buildHeaders(query: SearchQuery, targetUrl: String): Map<String, String> {
        val headers = mutableMapOf(
            "Accept" to "application/json, text/plain, */*",
            "Referer" to query.resultURL,
            "User-Agent" to userAgent,
        )
        return cookieProvider.attachCookies(headers, targetUrl)
    }

    fun decodePage(rawJson: String, query: SearchQuery, filter: SearchResultFilter, requestedPage: Int = 1): SearchResultPage {
        val payload = try {
            json.parseToJsonElement(rawJson) as? JsonObject
        } catch (_: Exception) {
            throw ServiceError.InvalidResponse
        } ?: throw ServiceError.InvalidResponse

        val code = payload.intValueAt("code") ?: -1
        val message = payload.stringValueAt("message") ?: "unknown"
        if (code != 0) throw ServiceError.Api(code, message)

        val dataPayload = payload.dictionaryValueAt("data")
            ?: return SearchResultPage(sections = emptyList(), nextPage = null)

        if (filter == SearchResultFilter.ALL) {
            val sections = makeOverviewSections(dataPayload)
            val nextPage = if (sections.any { it.filter == SearchResultFilter.VIDEO && it.items.isNotEmpty() }) 2 else null
            return SearchResultPage(sections = sections, nextPage = nextPage)
        }

        val items = dataPayload.arrayValueAt("result")
            ?.mapNotNull { it as? JsonObject }
            ?: emptyList()
        val section = makeSection(filter, items)
        val currentPage = dataPayload.intValueAt("page") ?: requestedPage
        val totalPages = dataPayload.intValueAt("numPages") ?: currentPage
        val nextPage = if (currentPage < totalPages) currentPage + 1 else null
        return SearchResultPage(
            sections = if (section.items.isEmpty()) emptyList() else listOf(section),
            nextPage = nextPage,
        )
    }

    private fun makeOverviewSections(dataPayload: JsonObject): List<SearchResultSection> {
        val blocks = dataPayload.arrayValueAt("result")?.mapNotNull { it as? JsonObject } ?: emptyList()
        val mappedSections = blocks.mapNotNull { block ->
            val resultType = block.stringValueAt("result_type") ?: return@mapNotNull null
            val filter = filterFor(resultType) ?: return@mapNotNull null
            val items = block.arrayValueAt("data")?.mapNotNull { it as? JsonObject } ?: emptyList()
            makeSection(filter, items)
        }

        val sectionMap = mutableMapOf<SearchResultFilter, SearchResultSection>()
        for (section in mappedSections) {
            if (section.items.isNotEmpty()) {
                sectionMap[section.filter] = section
            }
        }

        return SearchResultFilter.defaultOrder
            .filter { it != SearchResultFilter.ALL }
            .mapNotNull { sectionMap[it] }
    }

    private fun filterFor(rawResultType: String): SearchResultFilter? = when (rawResultType) {
        "video" -> SearchResultFilter.VIDEO
        "bili_user" -> SearchResultFilter.USERS
        "live_room" -> SearchResultFilter.LIVE
        "media_bangumi" -> SearchResultFilter.BANGUMI
        "media_ft" -> SearchResultFilter.FILM
        else -> null
    }

    private fun makeSection(filter: SearchResultFilter, items: List<JsonObject>): SearchResultSection {
        val mappedItems = items.mapNotNull { item ->
            when (filter) {
                SearchResultFilter.ALL -> null
                SearchResultFilter.VIDEO -> makeVideoItem(item)
                SearchResultFilter.USERS -> makeUserItem(item)
                SearchResultFilter.LIVE -> makeLiveItem(item)
                SearchResultFilter.BANGUMI, SearchResultFilter.FILM -> makeMediaItem(item, filter)
            }
        }
        return SearchResultSection(filter, mappedItems)
    }

    // Item builders...

    private fun makeVideoItem(item: JsonObject): SearchResultItem? {
        val targetURL = normalizedNavigationURL(
            item.stringValueAt("arcurl") ?: item.stringValueAt("url")
        ) ?: return null

        val title = cleanText(item.stringValueAt("title") ?: item.stringValueAt("typename"))
        val subtitle = cleanText(
            item.stringValueAt("author") ?: item.stringValueAt("up_name") ?: item.stringValueAt("uname")
        )
        val playText = formattedCount(item.stringValueAt("play") ?: item.stringValueAt("stat", "view"))
        val durationText = durationLabel(item.stringValueAt("duration") ?: item.stringValueAt("length"))
        val badgeText = durationText
        val metadataText = if (playText.isEmpty()) cleanText(item.stringValueAt("pubdate")) else "${playText}播放"
        val descriptionText = cleanText(item.stringValueAt("description") ?: item.stringValueAt("desc"))
        val coverURL = normalizedImageURL(item.stringValueAt("pic") ?: item.stringValueAt("cover"))
        val id = item.stringValueAt("bvid") ?: item.stringValueAt("id") ?: targetURL

        return SearchResultItem(
            id = id, kind = SearchResultItem.Kind.VIDEO,
            title = title.ifEmpty { "视频" }, subtitle = subtitle,
            metadataText = metadataText, badgeText = badgeText,
            descriptionText = descriptionText, coverURL = coverURL,
            targetURL = targetURL,
        )
    }

    private fun makeUserItem(item: JsonObject): SearchResultItem? {
        val id = item.stringValueAt("mid") ?: item.stringValueAt("uid") ?: "0"
        val fallbackSpaceURL = "https://space.bilibili.com/$id"
        val targetURL = normalizedNavigationURL(
            item.stringValueAt("uri") ?: item.stringValueAt("url") ?: item.stringValueAt("space_url") ?: fallbackSpaceURL
        ) ?: fallbackSpaceURL
        val title = cleanText(item.stringValueAt("uname") ?: item.stringValueAt("title"))
        val signature = cleanText(item.stringValueAt("usign") ?: item.stringValueAt("desc"))
        val fansText = formattedCount(item.stringValueAt("fans") ?: item.stringValueAt("fans_count"))
        val videoCount = plainCountString(item.stringValueAt("videos") ?: item.stringValueAt("archive_count"))
        val metadataParts = listOfNotNull(
            fansText.takeIf { it.isNotEmpty() }?.let { "粉丝 $it" },
            videoCount.takeIf { it.isNotEmpty() }?.let { "视频 $it" },
        )
        val metadataText = metadataParts.joinToString(" · ")
        val avatarURL = normalizedImageURL(item.stringValueAt("face") ?: item.stringValueAt("upic"))

        val previews = item.arrayValueAt("res")?.mapNotNull { preview ->
            val dict = preview as? JsonObject ?: return@mapNotNull null
            val previewURL = normalizedNavigationURL(
                dict.stringValueAt("arcurl") ?: dict.stringValueAt("url")
            ) ?: return@mapNotNull null
            val previewID = dict.stringValueAt("bvid") ?: dict.stringValueAt("id") ?: previewURL
            val previewTitle = cleanText(dict.stringValueAt("title") ?: dict.stringValueAt("typename"))
            val previewCover = normalizedImageURL(dict.stringValueAt("pic") ?: dict.stringValueAt("cover"))
            val previewMetadata = formattedCount(dict.stringValueAt("play") ?: dict.stringValueAt("stat", "view"))
            val previewBadge = durationLabel(dict.stringValueAt("duration") ?: dict.stringValueAt("length"))

            SearchResultItem.PreviewVideo(
                id = previewID,
                title = previewTitle.ifEmpty { "视频" },
                coverURL = previewCover,
                targetURL = previewURL,
                metadataText = if (previewMetadata.isEmpty()) "" else "${previewMetadata}播放",
                badgeText = previewBadge,
            )
        } ?: emptyList()

        return SearchResultItem(
            id = id, kind = SearchResultItem.Kind.USER,
            title = title.ifEmpty { "UP主" }, subtitle = signature,
            metadataText = metadataText, avatarURL = avatarURL,
            targetURL = targetURL, previews = previews,
        )
    }

    private fun makeLiveItem(item: JsonObject): SearchResultItem? {
        val roomID = item.stringValueAt("roomid") ?: item.stringValueAt("id")
        val directRoomURL = roomID?.let { "https://live.bilibili.com/$it" }
        val targetURL = directRoomURL?.let { FocusNavigationPolicy.canonicalWebURL(it) }
            ?: normalizedNavigationURL(item.stringValueAt("link") ?: item.stringValueAt("url"))
            ?: return null

        val title = cleanText(item.stringValueAt("title"))
        val uname = cleanText(item.stringValueAt("uname"))
        val areaText = cleanText(item.stringValueAt("area") ?: item.stringValueAt("cate_name"))
        val subtitle = listOf(uname, areaText).filter { it.isNotEmpty() }.joinToString(" · ")
        val onlineText = formattedCount(item.stringValueAt("online") ?: item.stringValueAt("online_total"))
        val badgeText = liveStatusText(item.stringValueAt("live_status"), areaText)
        val descriptionText = cleanText(
            item.stringValueAt("watched_show", "text_large") ?: item.stringValueAt("desc")
        )
        val coverURL = normalizedImageURL(
            item.stringValueAt("cover") ?: item.stringValueAt("user_cover") ?: item.stringValueAt("room_cover")
        )
        val id = roomID ?: targetURL

        return SearchResultItem(
            id = id, kind = SearchResultItem.Kind.LIVE,
            title = title.ifEmpty { "直播" }, subtitle = subtitle,
            metadataText = if (onlineText.isEmpty()) "" else "${onlineText}人气",
            badgeText = badgeText, descriptionText = descriptionText,
            coverURL = coverURL, targetURL = targetURL,
        )
    }

    private fun makeMediaItem(item: JsonObject, filter: SearchResultFilter): SearchResultItem? {
        val rawURL = item.stringValueAt("url") ?: item.stringValueAt("share_url") ?: item.stringValueAt("media_url")
        val targetURL = normalizedNavigationURL(rawURL) ?: return null

        val title = cleanText(item.stringValueAt("title") ?: item.stringValueAt("org_title"))
        val styleText = cleanText(item.stringValueAt("styles") ?: item.stringValueAt("style"))
        val areaText = cleanText(item.stringValueAt("areas"))
        val subtitle = listOf(styleText, areaText).filter { it.isNotEmpty() }.joinToString(" · ")
        val scoreText = mediaScoreText(item)
        val badgeText = cleanText(item.stringValueAt("season_type_name") ?: item.stringValueAt("badge"))
        val descriptionText = cleanText(item.stringValueAt("index_show") ?: item.stringValueAt("desc"))
        val coverURL = normalizedImageURL(
            item.stringValueAt("cover") ?: item.stringValueAt("season_cover") ?: item.stringValueAt("vertical_cover")
        )
        val id = item.stringValueAt("season_id") ?: item.stringValueAt("media_id") ?: targetURL

        return SearchResultItem(
            id = id, kind = SearchResultItem.Kind.MEDIA,
            title = title.ifEmpty { filter.sectionTitle }, subtitle = subtitle,
            metadataText = scoreText, badgeText = badgeText,
            descriptionText = descriptionText, coverURL = coverURL,
            targetURL = targetURL,
        )
    }

    // Helper functions

    private fun cleanText(rawValue: String?): String {
        if (rawValue == null) return ""
        var value = rawValue.trim()
        if (value.isEmpty()) return ""

        value = value.replace(Regex("<[^>]+>"), "")
        val htmlEntities = mapOf(
            "&amp;" to "&", "&lt;" to "<", "&gt;" to ">",
            "&quot;" to "\"", "&#39;" to "'", "&nbsp;" to " ",
        )
        for ((entity, replacement) in htmlEntities) {
            value = value.replace(entity, replacement)
        }

        return value
            .replace("\n", " ")
            .replace("\t", " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun normalizedNavigationURL(rawValue: String?): String? {
        if (rawValue == null) return null
        var value = rawValue.trim()
        if (value.isEmpty()) return null

        value = when {
            value.startsWith("//") -> "https:$value"
            value.startsWith("/") -> "https://www.bilibili.com$value"
            else -> value
        }

        return FocusNavigationPolicy.canonicalWebURL(value)
    }

    private fun normalizedImageURL(rawValue: String?): String? {
        if (rawValue == null) return null
        var value = rawValue.trim()
        if (value.isEmpty()) return null

        if (value.startsWith("//")) value = "https:$value"
        return value.takeIf { it.isNotEmpty() }
    }

    private fun formattedCount(rawValue: String?): String {
        val rawText = cleanText(rawValue)
        if (rawText.isEmpty()) return ""
        if ("万" in rawText || "亿" in rawText) return rawText

        val normalized = rawText.replace(",", "")
        val value = normalized.toDoubleOrNull() ?: return rawText

        return when {
            value >= 100_000_000 -> "${oneDecimal(value / 100_000_000)}亿"
            value >= 10_000 -> "${oneDecimal(value / 10_000)}万"
            else -> value.toLong().toString()
        }
    }

    private fun plainCountString(rawValue: String?): String {
        val rawText = cleanText(rawValue)
        if (rawText.isEmpty()) return ""
        if ("万" in rawText || "亿" in rawText) return rawText

        val normalized = rawText.replace(",", "")
        return normalized.toIntOrNull()?.toString() ?: rawText
    }

    private fun durationLabel(rawValue: String?): String {
        val rawText = cleanText(rawValue)
        if (rawText.isEmpty()) return ""
        if (":" in rawText) return rawText

        val normalized = rawText.replace(",", "")
        val seconds = normalized.toIntOrNull() ?: return rawText
        if (seconds <= 0) return rawText

        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        val remainingSeconds = seconds % 60

        return if (hours > 0) {
            "$hours:${minutes.twoDigits()}:${remainingSeconds.twoDigits()}"
        } else {
            "${minutes.twoDigits()}:${remainingSeconds.twoDigits()}"
        }
    }

    private fun oneDecimal(value: Double): String {
        val tenths = (value * 10).roundToLong()
        val whole = tenths / 10
        val fraction = tenths % 10
        return if (fraction == 0L) whole.toString() else "$whole.$fraction"
    }

    private fun Int.twoDigits(): String = toString().padStart(2, '0')

    private fun mediaScoreText(item: JsonObject): String {
        val rawScore = cleanText(
            item.stringValueAt("media_score", "score") ?: item.stringValueAt("score")
        )
        if (rawScore.isNotEmpty()) {
            return if (rawScore.startsWith("评分")) rawScore else "评分 $rawScore"
        }
        return cleanText(item.stringValueAt("cv") ?: item.stringValueAt("index_show"))
    }

    private fun liveStatusText(rawValue: String?, fallback: String): String = when (cleanText(rawValue)) {
        "1" -> "直播中"
        "0" -> if (fallback.isEmpty()) "未开播" else fallback
        else -> fallback
    }

}
