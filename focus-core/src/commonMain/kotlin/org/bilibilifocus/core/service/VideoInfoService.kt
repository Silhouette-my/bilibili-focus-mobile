package org.bilibilifocus.core.service

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.CommentCursor
import org.bilibilifocus.core.model.CommentPage
import org.bilibilifocus.core.model.VideoAuthor
import org.bilibilifocus.core.model.VideoComment
import org.bilibilifocus.core.model.VideoDanmakuSegment
import org.bilibilifocus.core.model.VideoDanmakuView
import org.bilibilifocus.core.model.VideoEpisode
import org.bilibilifocus.core.model.VideoEpisodeGroup
import org.bilibilifocus.core.model.VideoInfo
import org.bilibilifocus.core.model.VideoPage
import org.bilibilifocus.core.model.VideoStats
import kotlin.math.min

class VideoInfoService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    private val wbiSigner: WbiSigner = WbiSigner(cookieProvider, httpClient, userAgent),
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object LoginRequired : ServiceError("需要登录")
        data object InvalidResponse : ServiceError("接口返回无效数据")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
    }

    private val json = Json { ignoreUnknownKeys = true }

    private suspend fun buildHeaders(targetUrl: String): Map<String, String> {
        val headers = mapOf(
            "User-Agent" to userAgent,
            "Referer" to "https://www.bilibili.com/",
        )
        return cookieProvider.attachCookies(headers, targetUrl)
    }

    private fun parseDataField(body: String): JsonObject {
        val root = json.parseToJsonElement(body) as? JsonObject ?: throw ServiceError.InvalidResponse
        val code = root["code"]?.jsonPrimitive?.content?.toIntOrNull() ?: -1
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) {
            val msg = root["message"]?.jsonPrimitive?.content ?: "未知错误"
            throw ServiceError.Api(code, msg)
        }
        return root["data"] as? JsonObject ?: throw ServiceError.InvalidResponse
    }

    private suspend fun executeWbiText(
        endpoint: String,
        parameters: Map<String, String>,
    ): HttpResponse {
        val result = try {
            wbiSigner.execute(parameters) { signedQuery ->
                val url = "$endpoint?$signedQuery"
                val response = httpClient.get(url, buildHeaders(url))
                val apiCode = runCatching {
                    (json.parseToJsonElement(response.body) as? JsonObject)?.intValueAt("code")
                }.getOrNull()
                WbiRequestResult(response, response.statusCode, apiCode)
            }
        } catch (_: WbiSigner.SigningUnavailable) {
            throw ServiceError.InvalidResponse
        }
        return result.value
    }

    suspend fun fetchVideoInfo(id: String): VideoInfo {
        val param = if (id.startsWith("av")) "aid=${id.removePrefix("av")}" else "bvid=$id"
        val url = "${BiliApiContractCatalog.require("video.info.info").url}?$param"
        val data = parseDataField(
            httpClient.get(
                url,
                buildHeaders(url),
            ).body
        )

        val owner = data["owner"] as? JsonObject
        val stat = data["stat"] as? JsonObject
        val dimension = data["dimension"] as? JsonObject

        val tags = data["tname"]?.jsonPrimitive?.content
            ?.split("/")?.map { it.trim() }?.filter { it.isNotBlank() }
            ?: emptyList()

        val cid = data["cid"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0
        val aid = data["aid"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0
        val pages = parsePages(data)
        val episodeGroups = parseEpisodeGroups(data)
        val bvid = data["bvid"]?.jsonPrimitive?.content ?: id
        val playbackProgress = parsePlaybackProgress(data)
            ?: fetchPlaybackProgress(aid = aid, cid = cid)

        return VideoInfo(
            bvid = bvid,
            aid = aid,
            cid = cid,
            title = data["title"]?.jsonPrimitive?.content ?: "",
            description = data["desc"]?.jsonPrimitive?.content ?: "",
            coverURL = data["pic"]?.jsonPrimitive?.content ?: "",
            duration = data["duration"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
            publishDate = data["pubdate"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
            author = VideoAuthor(
                name = owner?.get("name")?.jsonPrimitive?.content ?: "",
                mid = owner?.get("mid")?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
                avatarURL = owner?.get("face")?.jsonPrimitive?.content ?: "",
            ),
            stats = VideoStats(
                views = stat?.get("view")?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
                likes = stat?.get("like")?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
                coins = stat?.get("coin")?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
                favorites = stat?.get("favorite")?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
                shares = stat?.get("share")?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
                danmaku = stat?.get("danmaku")?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
                comments = stat?.get("reply")?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
            ),
            tags = tags,
            pages = pages,
            episodeGroups = episodeGroups,
            playerURL = null,
            width = dimension?.get("width")?.jsonPrimitive?.content?.toIntOrNull() ?: 0,
            height = dimension?.get("height")?.jsonPrimitive?.content?.toIntOrNull() ?: 0,
            lastPlaybackCid = playbackProgress?.cid,
            lastPlaybackPositionMillis = playbackProgress?.positionMillis ?: 0,
        )
    }

    private suspend fun fetchPlaybackProgress(
        aid: Long,
        cid: Long,
    ): PlaybackProgress? {
        if (aid <= 0 || cid <= 0) return null
        return try {
            val response = executeWbiText(
                endpoint = BiliApiContractCatalog.require("video.info.get_player_info").url,
                parameters = mapOf(
                    "aid" to aid.toString(),
                    "cid" to cid.toString(),
                    "isGaiaAvoided" to "false",
                    "web_location" to "1315873",
                ),
            )
            if (response.statusCode !in 200..299) return null
            val data = parseDataField(response.body)
            parsePlaybackProgress(data)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            // Resume metadata is optional. A signed-out account or a temporary
            // player-info failure must not prevent the video detail from loading.
            null
        }
    }

    private fun parsePlaybackProgress(data: JsonObject): PlaybackProgress? {
        val lastCid = data["last_play_cid"]
            ?.jsonPrimitive
            ?.content
            ?.toLongOrNull()
            ?.takeIf { it > 0 }
            ?: return null
        val positionMillis = data["last_play_time"]
            ?.jsonPrimitive
            ?.content
            ?.toLongOrNull()
            ?.coerceAtLeast(0)
            ?: return null
        return PlaybackProgress(lastCid, positionMillis)
    }

    suspend fun fetchPlayerUrl(bvid: String, cid: Long): String? {
        return try {
            val response = executeWbiText(
                endpoint = BiliApiContractCatalog.require("video.info.playurl").url,
                parameters = mapOf(
                    "bvid" to bvid,
                    "cid" to cid.toString(),
                    "qn" to "80",
                    "fnval" to "4048",
                    "fourk" to "1",
                ),
            )
            if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse
            val data = parseDataField(response.body)

            // Try durl (progressive FLV/MP4) first
            val durl = data["durl"] as? kotlinx.serialization.json.JsonArray
            val durlUrl = (durl?.firstOrNull() as? JsonObject)?.get("url")?.jsonPrimitive?.content
            if (!durlUrl.isNullOrEmpty()) return durlUrl

            // Fall back to dash video stream
            val dash = data["dash"] as? JsonObject
            val videoArray = dash?.get("video") as? kotlinx.serialization.json.JsonArray
            val videoUrl = (videoArray?.firstOrNull() as? JsonObject)?.get("baseUrl")?.jsonPrimitive?.content
                ?: (videoArray?.firstOrNull() as? JsonObject)?.get("base_url")?.jsonPrimitive?.content
            if (!videoUrl.isNullOrEmpty()) return videoUrl

            // Last resort: accept_description / accept_quality with durl
            null
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Source-compatible first-page API. Further pages require the opaque
     * offset returned by [fetchCommentPage], not a numeric page index.
     */
    suspend fun fetchComments(oid: Long, page: Int = 1): Pair<List<VideoComment>, Int> {
        if (page < 1) return emptyList<VideoComment>() to 0
        val result = fetchCommentPage(oid)
        return result.comments to result.totalCount.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    suspend fun fetchCommentPage(
        oid: Long,
        cursor: CommentCursor = CommentCursor(),
    ): CommentPage {
        return try {
            val pagination = buildJsonObject {
                put("offset", cursor.nextOffset.orEmpty())
            }.toString()
            val response = executeWbiText(
                endpoint = BiliApiContractCatalog.require("common.comment.reply_by_session_id").url,
                parameters = mapOf(
                    "type" to "1",
                    "oid" to oid.toString(),
                    "mode" to "3",
                    "pagination_str" to pagination,
                    "web_location" to "1315875",
                ),
            )
            if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse
            val data = parseDataField(response.body)
            val replies = data["replies"] as? kotlinx.serialization.json.JsonArray
            val comments = replies?.mapNotNull { parseComment(it as? JsonObject) } ?: emptyList()
            val total = data.longValueAt("cursor", "all_count")
                ?: data.longValueAt("page", "count")
                ?: 0L
            val nextOffset = data.stringValueAt("cursor", "pagination_reply", "next_offset")
                ?.takeIf(String::isNotBlank)
            CommentPage(
                comments = comments,
                totalCount = total,
                cursor = CommentCursor(nextOffset),
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            CommentPage(emptyList(), 0L, CommentCursor())
        }
    }

    suspend fun fetchDanmakuView(aid: Long, cid: Long): VideoDanmakuView {
        val url = "https://api.bilibili.com/x/v2/dm/web/view?type=1&oid=$cid&pid=$aid"
        val response = httpClient.getBytes(
            url,
            buildHeaders(url) + mapOf("Accept" to "application/octet-stream, */*"),
        )
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse
        parseBinaryApiError(response.body)?.let { throw it }
        return try {
            VideoDanmakuDecoder.decodeView(response.body)
        } catch (_: ProtobufDecodingException) {
            throw ServiceError.InvalidResponse
        }
    }

    suspend fun fetchDanmakuSegment(
        aid: Long,
        cid: Long,
        segmentIndex: Int,
    ): VideoDanmakuSegment {
        require(segmentIndex > 0) { "segmentIndex 必须从 1 开始" }
        val endpoint = BiliApiContractCatalog.require("video.danmaku.get_danmaku").url
        val result = try {
            wbiSigner.execute(
                mapOf(
                    "oid" to cid.toString(),
                    "type" to "1",
                    "pid" to aid.toString(),
                    "segment_index" to segmentIndex.toString(),
                    "web_location" to "1550101",
                ),
            ) { signedQuery ->
                val url = "$endpoint?$signedQuery"
                val response = httpClient.getBytes(
                    url,
                    buildHeaders(url) + mapOf("Accept" to "application/octet-stream, */*"),
                )
                WbiRequestResult(
                    value = response,
                    httpStatusCode = response.statusCode,
                    apiCode = parseBinaryApiError(response.body)?.code,
                )
            }
        } catch (_: WbiSigner.SigningUnavailable) {
            throw ServiceError.InvalidResponse
        }
        val response = result.value
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse

        parseBinaryApiError(response.body)?.let { throw it }
        return try {
            VideoDanmakuDecoder.decodeSegment(response.body)
        } catch (_: ProtobufDecodingException) {
            throw ServiceError.InvalidResponse
        }
    }

    private fun parseBinaryApiError(bytes: ByteArray): ServiceError.Api? {
        val firstContentIndex = bytes.indexOfFirst { byte ->
            byte != 0x09.toByte() &&
                byte != 0x0a.toByte() &&
                byte != 0x0d.toByte() &&
                byte != 0x20.toByte()
        }
        if (firstContentIndex < 0 || bytes[firstContentIndex] != 0x7b.toByte()) return null
        val body = bytes.copyOfRange(firstContentIndex, bytes.size).decodeToString()
        val root = runCatching { json.parseToJsonElement(body) as? JsonObject }.getOrNull() ?: return null
        val code = root["code"]?.jsonPrimitive?.content?.toIntOrNull() ?: return null
        if (code == 0) return null
        return ServiceError.Api(
            code = code,
            message = root["message"]?.jsonPrimitive?.content ?: "弹幕接口失败",
        )
    }

    private fun parseComment(obj: JsonObject?): VideoComment? {
        if (obj == null) return null
        val member = obj["member"] as? JsonObject ?: return null
        val content = obj["content"] as? JsonObject ?: return null
        val subReplies = obj["replies"] as? kotlinx.serialization.json.JsonArray

        return VideoComment(
            rpid = obj["rpid"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
            mid = obj["mid"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
            authorName = member["uname"]?.jsonPrimitive?.content ?: "",
            avatarURL = member["avatar"]?.jsonPrimitive?.content ?: "",
            content = content["message"]?.jsonPrimitive?.content ?: "",
            contentRuns = CommentRichTextParser.parse(content),
            likeCount = obj["like"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
            replyCount = obj["rcount"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
            publishTime = obj["ctime"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
            replies = subReplies?.mapNotNull { parseComment(it as? JsonObject) } ?: emptyList(),
            imageURLs = CommentRichTextParser.parseImageURLs(content),
        )
    }

    private fun parsePages(data: JsonObject): List<VideoPage> {
        val pages = data["pages"] as? kotlinx.serialization.json.JsonArray ?: return emptyList()
        return pages.mapNotNull { pageElement ->
            val page = pageElement as? JsonObject ?: return@mapNotNull null
            val cid = page["cid"]?.jsonPrimitive?.content?.toLongOrNull() ?: return@mapNotNull null
            val pageNumber = page["page"]?.jsonPrimitive?.content?.toIntOrNull() ?: 1
            val title = page["part"]?.jsonPrimitive?.content?.ifBlank { null } ?: "P$pageNumber"
            val duration = page["duration"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
            VideoPage(
                pageNumber = pageNumber,
                cid = cid,
                title = title,
                duration = duration,
            )
        }
    }

    private fun parseEpisodeGroups(data: JsonObject): List<VideoEpisodeGroup> {
        val ugcSeason = data.dictionaryValueAt("ugc_season") ?: return emptyList()
        val seasonTitle = ugcSeason.stringValueAt("title").orEmpty()
        val sections = ugcSeason.arrayValueAt("sections") ?: return emptyList()
        return sections.mapNotNull { sectionElement ->
            val section = sectionElement as? JsonObject ?: return@mapNotNull null
            val groupTitle = section.stringValueAt("title")
                ?.takeIf { it.isNotBlank() }
                ?: seasonTitle.ifBlank { "选集" }
            val episodes = section.arrayValueAt("episodes")
                ?.mapNotNull { episodeElement -> parseEpisode(episodeElement as? JsonObject) }
                ?: emptyList()
            if (episodes.isEmpty()) null else VideoEpisodeGroup(groupTitle, episodes)
        }
    }

    private fun parseEpisode(episode: JsonObject?): VideoEpisode? {
        if (episode == null) return null
        val arc = episode.dictionaryValueAt("arc")
        val bvid = episode.stringValueAt("bvid")
            ?: arc?.stringValueAt("bvid")
            ?: return null
        val aid = episode.stringValueAt("aid")?.toLongOrNull()
            ?: arc?.stringValueAt("aid")?.toLongOrNull()
            ?: 0L
        val cid = episode.stringValueAt("cid")?.toLongOrNull()
            ?: arc?.stringValueAt("cid")?.toLongOrNull()
            ?: 0L
        val title = episode.stringValueAt("title")
            ?.takeIf { it.isNotBlank() }
            ?: episode.stringValueAt("long_title")
            ?.takeIf { it.isNotBlank() }
            ?: arc?.stringValueAt("title")
            ?.takeIf { it.isNotBlank() }
            ?: bvid
        val coverURL = episode.stringValueAt("cover")
            ?: arc?.stringValueAt("pic")
            ?: ""
        val badgeText = episode.stringValueAt("badge")
            ?: episode.stringValueAt("badge_info", "text")
            ?: ""
        return VideoEpisode(
            bvid = bvid,
            aid = aid,
            cid = cid,
            title = title,
            coverURL = coverURL,
            badgeText = badgeText,
        )
    }

    companion object {
        private val bvRegex = Regex("BV[0-9A-Za-z]{10}")
        private val avRegex = Regex("[av]*(\\d{5,})")

        fun extractBvid(url: String): String? {
            bvRegex.find(url)?.let { return it.value }
            val avMatch = avRegex.find(url.substringAfter("/video/", ""))
            if (avMatch != null) {
                val digits = avMatch.groupValues[1]
                if (digits.length >= 5) return "av$digits"
            }
            return null
        }
    }

    private data class PlaybackProgress(
        val cid: Long,
        val positionMillis: Long,
    )

}
