package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.OpusAuthor
import org.bilibilifocus.core.model.OpusBlock
import org.bilibilifocus.core.model.OpusDetail
import org.bilibilifocus.core.model.OpusImage
import org.bilibilifocus.core.model.RichTextRun
import org.bilibilifocus.core.model.VideoComment

class OpusService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object LoginRequired : ServiceError("需要登录")
        data object InvalidResponse : ServiceError("接口返回无效数据")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
    }

    private val json = Json { ignoreUnknownKeys = true }
    private var wbiMixedKey: String? = null
    private val wbiMixinTable = intArrayOf(
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
        33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40,
        61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11,
        36, 20, 52, 34, 44,
    )

    suspend fun fetchOpusDetail(id: String): OpusDetail {
        val url = "https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail" +
            "?id=$id&timezone_offset=-480" +
            "&features=onlyfansVote,onlyfansAssetsV2,decorationCard,htmlNewStyle,ugcDelete,editable,opusPrivateVisible"

        val response = httpClient.get(url, buildHeaders())
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse

        val payload = try {
            json.parseToJsonElement(response.body) as? JsonObject
        } catch (_: Exception) {
            throw ServiceError.InvalidResponse
        } ?: throw ServiceError.InvalidResponse

        val code = payload.intValueAt("code") ?: -1
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) {
            val msg = payload.stringValueAt("message") ?: "未知错误"
            throw ServiceError.Api(code, msg)
        }

        val data = payload.dictionaryValueAt("data")
            ?: throw ServiceError.InvalidResponse

        val item = data.dictionaryValueAt("item")

        // 如果没有 item，尝试直接从 data 解析
        if (item == null) {
            val directParagraphs = parseParagraphs(data)
            if (directParagraphs.isNotEmpty()) {
                return OpusDetail(
                    id = id,
                    commentId = 0L,
                    author = OpusAuthor(name = "用户", mid = 0, avatarURL = ""),
                    publishTime = "",
                    paragraphs = directParagraphs,
                )
            }
            return fetchFromDynamicDetail(id) ?: throw ServiceError.InvalidResponse
        }

        val basic = item.dictionaryValueAt("basic") ?: JsonObject(emptyMap())
        val modules = item.dictionaryValueAt("modules") ?: JsonObject(emptyMap())

        val opusId = basic.stringValueAt("comment_id_str")
            ?: basic.stringValueAt("rid_str")
            ?: id
        val commentId = basic.intValueAt("comment_id")?.toLong()
            ?: basic.stringValueAt("comment_id_str")?.toLongOrNull()
            ?: id.toLongOrNull()
            ?: 0L

        val authorModule = modules.dictionaryValueAt("module_author")
        val authorName = authorModule?.stringValueAt("name")?.ifEmpty { null } ?: "用户"
        val authorMid = authorModule?.intValueAt("mid")?.toLong() ?: 0L
        val authorAvatar = authorModule?.stringValueAt("face") ?: ""
        val publishTime = authorModule?.stringValueAt("pub_time")
            ?: authorModule?.stringValueAt("pub_time_text")
            ?: authorModule?.intValueAt("pub_ts")?.toString()
            ?: ""

        val paragraphs = parseParagraphs(modules)

        // 如果解析不到段落，先尝试动态详情接口（普通图片/文字动态），再退化为空结果
        if (paragraphs.isEmpty()) {
            fetchFromDynamicDetail(id)?.let { return it }
            return OpusDetail(
                id = opusId,
                commentId = commentId,
                author = OpusAuthor(name = authorName, mid = authorMid, avatarURL = authorAvatar),
                publishTime = publishTime,
                paragraphs = listOf(
                    OpusDetail.Paragraph(
                        listOf(OpusBlock.Text(listOf(RichTextRun.Text(text = "暂无内容"))))
                    )
                ),
            )
        }

        return OpusDetail(
            id = opusId,
            commentId = commentId,
            author = OpusAuthor(name = authorName, mid = authorMid, avatarURL = authorAvatar),
            publishTime = publishTime,
            paragraphs = paragraphs,
        )
    }

    /**
     * 普通图片/文字动态（MAJOR_TYPE_DRAW 等）走 opus/detail 拿不到 module_content，
     * 回退到动态详情接口，按 feed 相同的 module_dynamic 结构解析文本 + 图片。
     */
    private suspend fun fetchFromDynamicDetail(id: String): OpusDetail? {
        val url = "https://api.bilibili.com/x/polymer/web-dynamic/v1/detail" +
            "?id=$id&features=itemOpusStyle&timezone_offset=-480"
        val response = try {
            httpClient.get(url, buildHeaders())
        } catch (_: Exception) {
            return null
        }
        if (response.statusCode !in 200..299) return null

        val payload = try {
            json.parseToJsonElement(response.body) as? JsonObject
        } catch (_: Exception) {
            null
        } ?: return null
        if (payload.intValueAt("code") != 0) return null

        val item = payload.dictionaryValueAt("data", "item") ?: return null
        val modules = item.dictionaryValueAt("modules") ?: return null
        val author = modules.dictionaryValueAt("module_author")
        val dynamic = modules.dictionaryValueAt("module_dynamic") ?: return null
        val major = dynamic.dictionaryValueAt("major")

        val blocks = mutableListOf<OpusBlock>()

        val richTextRuns = parseOpusTextNodes(
            dynamic.arrayValueAt("desc", "rich_text_nodes")
                ?: dynamic.arrayValueAt("desc", "rich_text_nodes_v2")
                ?: emptyList()
        )
        val text = dynamic.stringValueAt("desc", "text") ?: major?.stringValueAt("opus", "summary", "text")
        if (richTextRuns.isNotEmpty()) {
            blocks.add(OpusBlock.Text(richTextRuns))
        } else if (!text.isNullOrEmpty()) {
            blocks.add(OpusBlock.Text(listOf(RichTextRun.Text(text = text))))
        }

        val pics = mutableListOf<OpusImage>()
        fun addPic(d: JsonObject, vararg keys: String) {
            val raw = keys.firstNotNullOfOrNull { d.stringValueAt(it) } ?: return
            val u = if (raw.startsWith("//")) "https:$raw" else raw
            pics.add(OpusImage(url = u, width = d.intValueAt("width") ?: 0, height = d.intValueAt("height") ?: 0))
        }
        major?.arrayValueAt("opus", "pics")?.forEach { (it as? JsonObject)?.let { d -> addPic(d, "url", "src") } }
        major?.arrayValueAt("draw", "items")?.forEach { (it as? JsonObject)?.let { d -> addPic(d, "src", "url") } }
        if (pics.isNotEmpty()) {
            blocks.add(OpusBlock.Image(pics))
        }

        if (blocks.isEmpty()) return null

        return OpusDetail(
            id = id,
            commentId = id.toLongOrNull() ?: 0L,
            author = OpusAuthor(
                name = author?.stringValueAt("name")?.ifEmpty { null } ?: "用户",
                mid = author?.intValueAt("mid")?.toLong() ?: 0L,
                avatarURL = author?.stringValueAt("face") ?: "",
            ),
            publishTime = author?.stringValueAt("pub_time")
                ?: author?.stringValueAt("pub_time_text")
                ?: "",
            paragraphs = listOf(OpusDetail.Paragraph(blocks)),
        )
    }

    suspend fun fetchComments(commentId: Long, fallbackId: String, page: Int = 1): Pair<List<VideoComment>, Int> {
        val oidCandidates = buildList {
            if (commentId > 0) add(commentId.toString())
            if (fallbackId.isNotBlank() && fallbackId !in this) add(fallbackId)
        }
        val typeCandidates = listOf(17, 11, 12)

        for (oid in oidCandidates) {
            for (type in typeCandidates) {
                val result = runCatching { fetchCommentsByType(oid, type, page) }.getOrNull()
                if (result != null && (result.first.isNotEmpty() || result.second > 0)) return result
            }
        }
        return emptyList<VideoComment>() to 0
    }

    private suspend fun fetchCommentsByType(oid: String, type: Int, page: Int): Pair<List<VideoComment>, Int> {
        val signed = signWbi(
            "type" to type.toString(),
            "oid" to oid,
            "pn" to page.toString(),
            "ps" to "20",
            "sort" to "2",
        )
        val response = httpClient.get(
            "https://api.bilibili.com/x/v2/reply/wbi/main?$signed",
            buildHeaders(),
        )
        val payload = json.parseToJsonElement(response.body) as? JsonObject ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: -1
        if (code != 0) throw ServiceError.Api(code, payload.stringValueAt("message") ?: "未知错误")
        val data = payload.dictionaryValueAt("data") ?: throw ServiceError.InvalidResponse
        val replies = data.arrayValueAt("replies") ?: emptyList()
        val comments = replies.mapNotNull { parseComment(it as? JsonObject) }
        val total = data.intValueAt("cursor", "all_count")
            ?: data.intValueAt("page", "count")
            ?: 0
        return comments to total
    }

    private suspend fun ensureWbiKey() {
        if (wbiMixedKey != null) return
        val response = httpClient.get("https://api.bilibili.com/x/web-interface/nav", buildHeaders())
        val root = json.parseToJsonElement(response.body) as? JsonObject ?: throw ServiceError.InvalidResponse
        val data = root.dictionaryValueAt("data") ?: throw ServiceError.InvalidResponse
        val wbiImg = data.dictionaryValueAt("wbi_img") ?: throw ServiceError.InvalidResponse
        val imgUrl = wbiImg.stringValueAt("img_url") ?: throw ServiceError.InvalidResponse
        val subUrl = wbiImg.stringValueAt("sub_url") ?: throw ServiceError.InvalidResponse
        val imgKey = imgUrl.substringAfterLast("/").substringBefore(".")
        val subKey = subUrl.substringAfterLast("/").substringBefore(".")
        val combined = imgKey + subKey
        wbiMixedKey = buildString {
            for (idx in wbiMixinTable) {
                if (idx < combined.length) append(combined[idx])
            }
        }.take(32)
    }

    private suspend fun signWbi(vararg params: Pair<String, String>): String {
        ensureWbiKey()
        val key = wbiMixedKey ?: throw ServiceError.InvalidResponse
        val wts = currentEpochSeconds().toString()
        val all = params.toMutableList()
        all.add("wts" to wts)
        all.sortBy { it.first }
        val raw = all.joinToString("&") { "${it.first}=${it.second}" } + key
        val wrid = org.bilibilifocus.core.crypto.md5Hex(raw)
        return all.joinToString("&") { "${it.first}=${it.second}" } + "&w_rid=$wrid"
    }

    private fun parseComment(obj: JsonObject?): VideoComment? {
        if (obj == null) return null
        val member = obj.dictionaryValueAt("member") ?: return null
        val content = obj.dictionaryValueAt("content") ?: return null
        val subReplies = obj.arrayValueAt("replies") ?: emptyList()
        return VideoComment(
            rpid = obj.intValueAt("rpid")?.toLong() ?: 0L,
            mid = obj.intValueAt("mid")?.toLong() ?: 0L,
            authorName = member.stringValueAt("uname") ?: "",
            avatarURL = member.stringValueAt("avatar") ?: "",
            content = content.stringValueAt("message") ?: "",
            contentRuns = CommentRichTextParser.parse(content),
            likeCount = obj.intValueAt("like")?.toLong() ?: 0L,
            replyCount = obj.intValueAt("rcount")?.toLong() ?: 0L,
            publishTime = obj.intValueAt("ctime")?.toLong() ?: 0L,
            replies = subReplies.mapNotNull { parseComment(it as? JsonObject) },
        )
    }

    private fun parseParagraphs(modules: JsonObject): List<OpusDetail.Paragraph> {
        val contentModule = modules.dictionaryValueAt("module_content")
            ?: modules.dictionaryValueAt("content")
            ?: return emptyList()

        val paragraphsJson = contentModule.arrayValueAt("paragraphs")
            ?: contentModule.arrayValueAt("items")
            ?: return emptyList()

        return paragraphsJson.mapNotNull { para ->
            val dict = para as? JsonObject ?: return@mapNotNull null
            val paraType = dict.intValueAt("para_type")
                ?: dict.intValueAt("type")
                ?: return@mapNotNull null
            val blocks = parseBlocks(dict, paraType)
            if (blocks.isEmpty()) null else OpusDetail.Paragraph(blocks)
        }.filterNot { it.blocks.isEmpty() }
    }

    private fun parseBlocks(para: JsonObject, paraType: Int): List<OpusBlock> {
        return when (paraType) {
            1 -> {
                // 纯文字段落
                val nodesArray = para.arrayValueAt("text", "nodes")
                    ?: para.arrayValueAt("nodes")
                    ?: return emptyList()

                val nodes = parseOpusTextNodes(nodesArray)
                if (nodes.isEmpty()) emptyList() else listOf(OpusBlock.Text(nodes))
            }
            2 -> {
                // 图片段落
                val picsArray = para.arrayValueAt("pic", "pics")
                    ?: para.arrayValueAt("pics")
                    ?: para.arrayValueAt("images")
                    ?: return emptyList()

                val pics = picsArray.mapNotNull { pic ->
                    val dict = pic as? JsonObject ?: return@mapNotNull null
                    val url = dict.stringValueAt("url")
                        ?: dict.stringValueAt("src")
                        ?: return@mapNotNull null
                    OpusImage(
                        url = url,
                        width = dict.intValueAt("width") ?: 0,
                        height = dict.intValueAt("height") ?: 0
                    )
                }
                if (pics.isEmpty()) emptyList() else listOf(OpusBlock.Image(pics))
            }
            7 -> {
                // 代码块
                val lang = para.stringValueAt("code", "lang")
                    ?: para.stringValueAt("lang")
                    ?: ""
                val content = para.stringValueAt("code", "content")
                    ?: para.stringValueAt("content")
                    ?: ""
                if (content.isEmpty()) emptyList() else listOf(OpusBlock.Code(lang = lang, content = content))
            }
            else -> emptyList()
        }
    }

    private fun parseOpusTextNodes(nodes: List<kotlinx.serialization.json.JsonElement>): List<RichTextRun> =
        nodes.mapNotNull { node ->
            val dict = node as? JsonObject ?: return@mapNotNull null
            val words = dict.stringValueAt("word", "words")
                ?: dict.stringValueAt("words")
                ?: dict.stringValueAt("text")
                ?: dict.stringValueAt("orig_text")
                ?: ""
            val style = dict.dictionaryValueAt("word", "style") ?: dict.dictionaryValueAt("style")
            val linkUrl = dict.stringValueAt("rich", "jump_url")
                ?: dict.stringValueAt("jump_url")
                ?: dict.stringValueAt("link")
            val emojiUrl = dict.stringValueAt("rich", "emoji", "icon_url")
                ?: dict.stringValueAt("rich", "emoji", "url")
                ?: dict.stringValueAt("emoji", "icon_url")
                ?: dict.stringValueAt("emoji", "url")
                ?: dict.stringValueAt("icon_url")
            val emojiSize = dict.intValueAt("rich", "emoji", "meta", "size")
                ?: dict.intValueAt("emoji", "meta", "size")
                ?: 0

            when {
                emojiUrl != null -> RichTextRun.Emote(
                    alt = words.ifEmpty { "[表情]" },
                    url = normalizedURL(emojiUrl) ?: emojiUrl,
                    width = dict.intValueAt("rich", "emoji", "width")
                        ?: dict.intValueAt("emoji", "width")
                        ?: emojiSize,
                    height = dict.intValueAt("rich", "emoji", "height")
                        ?: dict.intValueAt("emoji", "height")
                        ?: emojiSize,
                )
                words.isNotEmpty() -> RichTextRun.Text(
                    text = words,
                    bold = style?.intValueAt("bold") == 1,
                    italic = style?.intValueAt("italic") == 1,
                    underline = style?.intValueAt("underline") == 1,
                    strikethrough = style?.intValueAt("strikethrough") == 1 || style?.intValueAt("strike") == 1,
                    color = style?.stringValueAt("color"),
                    linkUrl = normalizedURL(linkUrl),
                )
                linkUrl != null -> RichTextRun.Resource(
                    label = "查看内容",
                    url = normalizedURL(linkUrl) ?: linkUrl,
                )
                else -> null
            }
        }

    private fun normalizedURL(raw: String?): String? {
        val value = raw?.trim()?.takeIf(String::isNotEmpty) ?: return null
        return when {
            value.startsWith("//") -> "https:$value"
            value.startsWith("http://") -> "https://${value.removePrefix("http://")}"
            value.startsWith("/") -> "https://www.bilibili.com$value"
            else -> value
        }
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
}
