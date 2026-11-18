package org.bilibilifocus.core.service

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.CommentTarget
import org.bilibilifocus.core.model.OpusAuthor
import org.bilibilifocus.core.model.OpusBlock
import org.bilibilifocus.core.model.OpusDetail
import org.bilibilifocus.core.model.OpusImage
import org.bilibilifocus.core.model.OpusReference
import org.bilibilifocus.core.model.RichTextRun
import org.bilibilifocus.core.model.VideoComment
import org.bilibilifocus.core.routing.ArticleURL
import org.bilibilifocus.core.routing.FocusNavigationPolicy

class OpusService(
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

    suspend fun fetchOpusDetail(id: String): OpusDetail {
        val url = BiliApiContractCatalog.require("opus.info.detail").url +
            "?id=$id&timezone_offset=-480" +
            "&features=onlyfansVote,onlyfansAssetsV2,decorationCard,htmlNewStyle,ugcDelete,editable,opusPrivateVisible"

        val response = httpClient.get(url, buildHeaders(url))
        if (response.statusCode !in 200..299) {
            fetchFromDynamicDetail(id)?.let { return it }
            throw ServiceError.InvalidResponse
        }

        val payload = try {
            json.parseToJsonElement(response.body) as? JsonObject
        } catch (_: Exception) {
            null
        }
        if (payload == null) {
            fetchFromDynamicDetail(id)?.let { return it }
            throw ServiceError.InvalidResponse
        }

        val code = payload.intValueAt("code") ?: -1
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) {
            fetchFromDynamicDetail(id)?.let { return it }
            val msg = payload.stringValueAt("message") ?: "未知错误"
            throw ServiceError.Api(code, msg)
        }

        val data = payload.dictionaryValueAt("data")
        if (data == null) {
            fetchFromDynamicDetail(id)?.let { return it }
            throw ServiceError.InvalidResponse
        }

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
        val modules = normalizeModules(item)

        val opusId = basic.stringValueAt("comment_id_str")
            ?: basic.stringValueAt("rid_str")
            ?: id
        val commentId = basic.longValueAt("comment_id")
            ?: basic.stringValueAt("comment_id_str")?.toLongOrNull()
            ?: id.toLongOrNull()
            ?: 0L
        val commentType = basic.intValueAt("comment_type") ?: 0

        val authorModule = modules.dictionaryValueAt("module_author")
        val authorName = authorModule?.stringValueAt("name")?.ifEmpty { null } ?: "用户"
        val authorMid = authorModule?.longValueAt("mid") ?: 0L
        val authorAvatar = normalizedURL(authorModule?.stringValueAt("face")) ?: ""
        val publishTime = authorModule?.stringValueAt("pub_time")
            ?: authorModule?.stringValueAt("pub_time_text")
            ?: authorModule?.longValueAt("pub_ts")?.toString()
            ?: ""

        val paragraphs = parseOpusModulesParagraphs(modules).toMutableList()
        val hasReferenceBlock = paragraphs.any { paragraph ->
            paragraph.blocks.any { it is OpusBlock.Reference }
        }
        if (!hasReferenceBlock) {
            val dynamicModule = modules.dictionaryValueAt("module_dynamic")
            val embeddedRef = (
                item.dictionaryValueAt("orig")
                    ?: item.dictionaryValueAt("origin")
                    ?: dynamicModule?.dictionaryValueAt("forward")
                    ?: dynamicModule?.dictionaryValueAt("orig")
                )?.let(::parseDynamicItemReference)
                ?: dynamicModule?.dictionaryValueAt("additional")?.let(::parseAdditionalReference)
                ?: dynamicModule?.dictionaryValueAt("major")?.let { parseMajorReference(it, basic) }
            if (embeddedRef != null) {
                paragraphs.add(OpusDetail.Paragraph(listOf(OpusBlock.Reference(embeddedRef))))
            }
        }

        val isForwardItem = item.stringValueAt("type") == "DYNAMIC_TYPE_FORWARD"
        if (isForwardItem && paragraphs.none { p -> p.blocks.any { it is OpusBlock.Reference } }) {
            fetchFromDynamicDetail(id)?.let { dynamicDetail ->
                if (dynamicDetail.paragraphs.any { p -> p.blocks.any { it is OpusBlock.Reference } }) {
                    return dynamicDetail
                }
            }
        }

        // 如果解析不到段落，先尝试动态详情接口（普通图片/文字动态），再退化为空结果
        if (paragraphs.isEmpty()) {
            fetchFromDynamicDetail(id)?.let { return it }
            return OpusDetail(
                id = opusId,
                commentId = commentId,
                commentType = commentType,
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
            commentType = commentType,
            author = OpusAuthor(name = authorName, mid = authorMid, avatarURL = authorAvatar),
            publishTime = publishTime,
            paragraphs = paragraphs,
        )
    }

    /**
     * 普通图片/文字动态（MAJOR_TYPE_DRAW 等）与转发动态走 opus/detail 拿不到完整正文/引用内容，
     * 回退到动态详情接口，按 feed 相同的 module_dynamic + orig 结构解析文本、图片与引用动态。
     */
    private suspend fun fetchFromDynamicDetail(id: String): OpusDetail? {
        val endpoint = BiliApiContractCatalog.require("dynamic.info.detail").url
        val result = try {
            wbiSigner.execute(
                mapOf(
                    "id" to id,
                    "features" to "itemOpusStyle",
                    "timezone_offset" to "-480",
                ),
            ) { signedQuery ->
                val url = "$endpoint?$signedQuery"
                val response = httpClient.get(url, buildHeaders(url))
                val payload = runCatching {
                    json.parseToJsonElement(response.body) as? JsonObject
                }.getOrNull()
                WbiRequestResult(payload, response.statusCode, payload?.intValueAt("code"))
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            return null
        }
        if (result.httpStatusCode !in 200..299) return null
        val payload = result.value ?: return null
        val code = payload.intValueAt("code") ?: -1
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) return null

        val item = payload.dictionaryValueAt("data", "item") ?: return null
        val modules = normalizeModules(item)
        val author = modules.dictionaryValueAt("module_author")
        val dynamic = modules.dictionaryValueAt("module_dynamic")
        val major = dynamic?.dictionaryValueAt("major")
        val basic = item.dictionaryValueAt("basic")

        val blocks = mutableListOf<OpusBlock>()

        major?.stringValueAt("opus", "title")?.trim()?.takeIf { it.isNotEmpty() }?.let { opusTitle ->
            blocks.add(OpusBlock.Text(listOf(RichTextRun.Text(text = opusTitle, bold = true))))
        }

        val richTextRuns = parseOpusTextNodes(
            dynamic?.arrayValueAt("desc", "rich_text_nodes")
                ?: dynamic?.arrayValueAt("desc", "rich_text_nodes_v2")
                ?: major?.arrayValueAt("opus", "summary", "rich_text_nodes")
                ?: major?.arrayValueAt("opus", "summary", "rich_text_nodes_v2")
                ?: emptyList()
        )
        val text = dynamic?.stringValueAt("desc", "text") ?: major?.stringValueAt("opus", "summary", "text")
        if (richTextRuns.isNotEmpty()) {
            blocks.add(OpusBlock.Text(richTextRuns))
        } else if (!text.isNullOrEmpty()) {
            blocks.add(OpusBlock.Text(listOf(RichTextRun.Text(text = text))))
        }

        val pics = mutableListOf<OpusImage>()
        fun addPic(d: JsonObject, vararg keys: String) {
            val raw = keys.firstNotNullOfOrNull { d.stringValueAt(it) } ?: return
            val u = normalizedURL(raw) ?: return
            pics.add(OpusImage(url = u, width = d.intValueAt("width") ?: 0, height = d.intValueAt("height") ?: 0))
        }
        major?.arrayValueAt("opus", "pics")?.forEach { (it as? JsonObject)?.let { d -> addPic(d, "url", "src") } }
        major?.arrayValueAt("draw", "items")?.forEach { (it as? JsonObject)?.let { d -> addPic(d, "src", "url") } }
        if (pics.isNotEmpty()) {
            blocks.add(OpusBlock.Image(pics))
        }

        val resultParagraphs = mutableListOf<OpusDetail.Paragraph>()
        if (blocks.isNotEmpty()) {
            resultParagraphs.add(OpusDetail.Paragraph(blocks))
        } else {
            resultParagraphs.addAll(parseOpusModulesParagraphs(modules))
        }

        val hasReference = resultParagraphs.any { paragraph ->
            paragraph.blocks.any { it is OpusBlock.Reference }
        }
        if (!hasReference) {
            val origRef = (
                item.dictionaryValueAt("orig")
                    ?: item.dictionaryValueAt("origin")
                    ?: dynamic?.dictionaryValueAt("forward")
                    ?: dynamic?.dictionaryValueAt("orig")
                )?.let(::parseDynamicItemReference)
                ?: dynamic?.dictionaryValueAt("additional")?.let(::parseAdditionalReference)
                ?: major?.let { parseMajorReference(it, basic) }
            if (origRef != null) {
                resultParagraphs.add(OpusDetail.Paragraph(listOf(OpusBlock.Reference(origRef))))
            }
        }

        if (resultParagraphs.isEmpty()) return null

        // Image dynamics comment on (rid, 11), text/forward dynamics on (dynamic id, 17).
        val basicCommentId = basic?.stringValueAt("comment_id_str")?.toLongOrNull()
            ?: basic?.longValueAt("comment_id")
        val basicCommentType = basic?.intValueAt("comment_type") ?: 0

        return OpusDetail(
            id = id,
            commentId = basicCommentId ?: id.toLongOrNull() ?: 0L,
            commentType = if (basicCommentId != null) basicCommentType else 0,
            author = OpusAuthor(
                name = author?.stringValueAt("name")?.ifEmpty { null } ?: "用户",
                mid = author?.longValueAt("mid") ?: 0L,
                avatarURL = normalizedURL(author?.stringValueAt("face")) ?: "",
            ),
            publishTime = author?.stringValueAt("pub_time")
                ?: author?.stringValueAt("pub_time_text")
                ?: "",
            paragraphs = resultParagraphs,
        )
    }

    /**
     * The comment area of [detail]. Uses the API's own `comment_type` when present;
     * otherwise probes the historical (oid, type) candidates once and keeps the first
     * area that actually has comments. Returns null when no area can be identified.
     */
    suspend fun resolveCommentTarget(detail: OpusDetail): CommentTarget? {
        if (detail.commentType > 0 && detail.commentId > 0) return CommentTarget(detail.commentId, detail.commentType)
        val oidCandidates = buildList {
            if (detail.commentId > 0) add(detail.commentId)
            detail.id.toLongOrNull()?.takeIf { it > 0 && it !in this }?.let(::add)
        }
        for (oid in oidCandidates) {
            for (type in listOf(17, 11, 12)) {
                val result = try {
                    fetchCommentsByType(oid.toString(), type)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    null
                }
                if (result != null && (result.first.isNotEmpty() || result.second > 0)) return CommentTarget(oid, type)
            }
        }
        // Long ids are dynamic ids: their (empty) area is still the text-dynamic one.
        return oidCandidates.firstOrNull { it > 1_000_000_000_000L }?.let { CommentTarget(it, 17) }
    }

    suspend fun fetchComments(commentId: Long, fallbackId: String, page: Int = 1): Pair<List<VideoComment>, Int> {
        if (page < 1) return emptyList<VideoComment>() to 0
        val oidCandidates = buildList {
            if (commentId > 0) add(commentId.toString())
            if (fallbackId.isNotBlank() && fallbackId !in this) add(fallbackId)
        }
        val typeCandidates = listOf(17, 11, 12)

        for (oid in oidCandidates) {
            for (type in typeCandidates) {
                val result = runCatching { fetchCommentsByType(oid, type) }.getOrNull()
                if (result != null && (result.first.isNotEmpty() || result.second > 0)) return result
            }
        }
        return emptyList<VideoComment>() to 0
    }

    private suspend fun fetchCommentsByType(oid: String, type: Int): Pair<List<VideoComment>, Int> {
        val endpoint = BiliApiContractCatalog.require("common.comment.reply_by_session_id").url
        val result = try {
            wbiSigner.execute(
                mapOf(
                    "type" to type.toString(),
                    "oid" to oid,
                    "mode" to "3",
                    "pagination_str" to """{"offset":""}""",
                    "web_location" to "1315875",
                ),
            ) { signedQuery ->
                val url = "$endpoint?$signedQuery"
                val response = httpClient.get(url, buildHeaders(url))
                val payload = runCatching {
                    json.parseToJsonElement(response.body) as? JsonObject
                }.getOrNull()
                WbiRequestResult(payload, response.statusCode, payload?.intValueAt("code"))
            }
        } catch (_: WbiSigner.SigningUnavailable) {
            throw ServiceError.InvalidResponse
        }
        if (result.httpStatusCode !in 200..299) throw ServiceError.InvalidResponse
        val payload = result.value ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: -1
        if (code != 0) throw ServiceError.Api(code, payload.stringValueAt("message") ?: "未知错误")
        val data = payload.dictionaryValueAt("data") ?: throw ServiceError.InvalidResponse
        val replies = data.arrayValueAt("replies") ?: emptyList()
        val comments = replies.mapNotNull { parseComment(it as? JsonObject) }
        val total = (
            data.longValueAt("cursor", "all_count")
                ?: data.longValueAt("page", "count")
                ?: 0L
            ).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        return comments to total
    }

    private fun parseComment(obj: JsonObject?): VideoComment? {
        if (obj == null) return null
        val member = obj.dictionaryValueAt("member") ?: return null
        val content = obj.dictionaryValueAt("content") ?: return null
        val subReplies = obj.arrayValueAt("replies") ?: emptyList()
        return VideoComment(
            rpid = obj.longValueAt("rpid") ?: 0L,
            mid = obj.longValueAt("mid") ?: 0L,
            authorName = member.stringValueAt("uname") ?: "",
            avatarURL = member.stringValueAt("avatar") ?: "",
            content = content.stringValueAt("message") ?: "",
            contentRuns = CommentRichTextParser.parse(content),
            likeCount = obj.longValueAt("like") ?: 0L,
            replyCount = obj.longValueAt("rcount") ?: 0L,
            publishTime = obj.longValueAt("ctime") ?: 0L,
            replies = subReplies.mapNotNull { parseComment(it as? JsonObject) },
            imageURLs = CommentRichTextParser.parseImageURLs(content),
        )
    }

    private fun normalizeModules(item: JsonObject): JsonObject {
        item.dictionaryValueAt("modules")?.let { return it }
        val array = item.arrayValueAt("modules") ?: return JsonObject(emptyMap())
        val merged = linkedMapOf<String, JsonElement>()
        array.forEach { element ->
            val entry = element as? JsonObject ?: return@forEach
            val mappedKey = when (entry.stringValueAt("module_type")) {
                "MODULE_TYPE_AUTHOR" -> "module_author"
                "MODULE_TYPE_CONTENT" -> "module_content"
                "MODULE_TYPE_TITLE" -> "module_title"
                "MODULE_TYPE_TOP" -> "module_top"
                "MODULE_TYPE_DYNAMIC" -> "module_dynamic"
                else -> null
            }
            if (mappedKey != null && entry[mappedKey] != null) {
                merged[mappedKey] = entry[mappedKey]!!
            }
            entry.forEach { (key, value) ->
                if (key != "module_type" && key !in merged) merged[key] = value
            }
        }
        return JsonObject(merged)
    }

    private fun parseOpusModulesParagraphs(modules: JsonObject): List<OpusDetail.Paragraph> {
        val result = mutableListOf<OpusDetail.Paragraph>()
        modules.stringValueAt("module_title", "text")?.trim()?.takeIf { it.isNotEmpty() }?.let { title ->
            result.add(OpusDetail.Paragraph(listOf(OpusBlock.Text(listOf(RichTextRun.Text(text = title, bold = true))))))
        }
        val topPics = modules.dictionaryValueAt("module_top", "display", "album")?.arrayValueAt("pics").orEmpty()
            .mapNotNull { element ->
                val pic = element as? JsonObject ?: return@mapNotNull null
                val url = normalizedURL(pic.stringValueAt("url") ?: pic.stringValueAt("src")) ?: return@mapNotNull null
                OpusImage(url = url, width = pic.intValueAt("width") ?: 0, height = pic.intValueAt("height") ?: 0)
            }
        if (topPics.isNotEmpty()) {
            result.add(OpusDetail.Paragraph(listOf(OpusBlock.Image(topPics))))
        }
        result.addAll(parseParagraphs(modules))
        return result
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
                    val url = normalizedURL(dict.stringValueAt("url") ?: dict.stringValueAt("src"))
                        ?: return@mapNotNull null
                    OpusImage(
                        url = url,
                        width = dict.intValueAt("width") ?: 0,
                        height = dict.intValueAt("height") ?: 0
                    )
                }
                if (pics.isEmpty()) emptyList() else listOf(OpusBlock.Image(pics))
            }
            4 -> {
                // 块引用段落
                val children = para.arrayValueAt("blockquote", "children")
                val nodes = if (!children.isNullOrEmpty()) {
                    buildList {
                        children.forEach { child ->
                            val childObj = child as? JsonObject ?: return@forEach
                            val rawNodes = childObj.arrayValueAt("text", "nodes")
                                ?: childObj.arrayValueAt("nodes")
                                ?: return@forEach
                            val parsed = parseOpusTextNodes(rawNodes)
                            if (parsed.isNotEmpty()) {
                                if (isNotEmpty()) add(RichTextRun.Text("\n"))
                                addAll(parsed)
                            }
                        }
                    }
                } else {
                    val nodesArray = para.arrayValueAt("text", "nodes")
                        ?: para.arrayValueAt("nodes")
                        ?: emptyList()
                    parseOpusTextNodes(nodesArray)
                }
                if (nodes.isEmpty()) emptyList() else listOf(OpusBlock.Quote(nodes))
            }
            5 -> {
                // 列表段落
                val listObj = para.dictionaryValueAt("list") ?: para
                val ordered = listObj.intValueAt("style") == 1
                val items = listObj.arrayValueAt("items") ?: emptyList()
                val runs = buildList {
                    items.forEachIndexed { idx, item ->
                        val itemObj = item as? JsonObject ?: return@forEachIndexed
                        val rawNodes = itemObj.arrayValueAt("nodes")
                            ?: itemObj.arrayValueAt("text", "nodes")
                            ?: return@forEachIndexed
                        val parsed = parseOpusTextNodes(rawNodes)
                        if (parsed.isNotEmpty()) {
                            if (isNotEmpty()) add(RichTextRun.Text("\n"))
                            add(RichTextRun.Text(if (ordered) "${idx + 1}. " else "• "))
                            addAll(parsed)
                        }
                    }
                }
                if (runs.isEmpty()) emptyList() else listOf(OpusBlock.Text(runs))
            }
            6 -> {
                // 引用/链卡段落
                val card = para.dictionaryValueAt("link_card", "card")
                    ?: para.dictionaryValueAt("link_card")
                    ?: return emptyList()
                val ref = parseLinkCardReference(card) ?: return emptyList()
                listOf(OpusBlock.Reference(ref))
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

    private fun parseLinkCardReference(card: JsonObject): OpusReference? {
        val cardType = card.stringValueAt("type") ?: ""
        val oid = card.stringValueAt("oid")?.trim().orEmpty()
        val cardJumpURL = normalizedURL(card.stringValueAt("jump_url"))

        if (cardType == "LINK_CARD_TYPE_ITEM_NULL" || card.dictionaryValueAt("item_null") != null) {
            val itemNull = card.dictionaryValueAt("item_null")
            val tip = itemNull?.stringValueAt("text")?.trim()?.takeIf { it.isNotEmpty() }
                ?: card.stringValueAt("tips")?.trim()?.takeIf { it.isNotEmpty() }
                ?: "引用内容已失效"
            return OpusReference(unavailableTip = tip)
        }

        if (cardType == "LINK_CARD_TYPE_FORWARD" ||
            card.dictionaryValueAt("forward") != null ||
            card.dictionaryValueAt("dynamic") != null ||
            card.dictionaryValueAt("orig") != null
        ) {
            val dynamicItem = card.dictionaryValueAt("forward")
                ?: card.dictionaryValueAt("dynamic")
                ?: card.dictionaryValueAt("orig")
            if (dynamicItem != null) {
                parseDynamicItemReference(dynamicItem)?.let { return it }
            }
        }

        if (cardType == "LINK_CARD_TYPE_OPUS" || card.dictionaryValueAt("opus") != null) {
            val opus = card.dictionaryValueAt("opus") ?: return null
            val author = opus.dictionaryValueAt("author")
            val title = opus.stringValueAt("title")?.trim().orEmpty()
            val richNodes = parseOpusTextNodes(
                opus.arrayValueAt("summary", "rich_text_nodes")
                    ?: opus.arrayValueAt("content", "rich_text_nodes")
                    ?: emptyList()
            )
            val plainSummary = (
                opus.primitiveString("content")
                    ?: opus.dictionaryValueAt("summary")?.stringValueAt("text")
                    ?: opus.primitiveString("summary")
                    ?: opus.primitiveString("desc")
                )?.trim().orEmpty()
            val textRuns = when {
                richNodes.isNotEmpty() -> richNodes
                plainSummary.isNotEmpty() && plainSummary != title -> listOf(RichTextRun.Text(plainSummary))
                else -> emptyList()
            }
            val images = collectOpusImages(
                singleUrls = listOfNotNull(
                    opus.stringValueAt("cover"),
                    card.stringValueAt("cover"),
                ),
                arrays = listOfNotNull(opus.arrayValueAt("pics")),
            )
            val jumpURL = normalizedURL(opus.stringValueAt("jump_url"))
                ?: cardJumpURL
                ?: oid.takeIf { it.isNotEmpty() && it.all(Char::isDigit) }?.let { "https://www.bilibili.com/opus/$it" }
            if (title.isEmpty() && textRuns.isEmpty() && images.isEmpty() && jumpURL == null) return null
            return OpusReference(
                authorName = author?.stringValueAt("name")?.trim().orEmpty(),
                authorMid = author?.longValueAt("mid") ?: 0L,
                authorAvatar = normalizedURL(author?.stringValueAt("face")) ?: "",
                title = title,
                textRuns = textRuns,
                images = images,
                targetURL = jumpURL,
                badgeText = "动态",
            )
        }

        if (cardType == "LINK_CARD_TYPE_UGC" || card.dictionaryValueAt("ugc") != null) {
            val ugc = card.dictionaryValueAt("ugc") ?: return null
            val title = ugc.stringValueAt("title")?.trim().orEmpty()
            val subtitle = listOfNotNull(
                ugc.stringValueAt("desc_second")?.trim()?.takeIf { it.isNotEmpty() },
                ugc.stringValueAt("duration")?.trim()?.takeIf { it.isNotEmpty() },
            ).joinToString(" · ")
            val cover = normalizedURL(ugc.stringValueAt("cover"))
            val bvid = ugc.stringValueAt("bvid")?.trim()?.takeIf { it.isNotEmpty() }
                ?: oid.takeIf { it.startsWith("BV", ignoreCase = true) }
            val jumpURL = normalizedURL(ugc.stringValueAt("jump_url"))
                ?: cardJumpURL
                ?: bvid?.let { "https://www.bilibili.com/video/$it/" }
            if (title.isEmpty() && subtitle.isEmpty() && cover == null && jumpURL == null) return null
            return OpusReference(
                title = title,
                textRuns = if (subtitle.isEmpty()) emptyList() else listOf(RichTextRun.Text(subtitle)),
                images = listOfNotNull(cover?.let { OpusImage(it, 0, 0) }),
                targetURL = jumpURL,
                badgeText = "视频",
            )
        }

        if (cardType == "LINK_CARD_TYPE_ARTICLE" || card.dictionaryValueAt("article") != null) {
            val article = card.dictionaryValueAt("article") ?: return null
            val title = article.stringValueAt("title")?.trim().orEmpty()
            val desc = (article.stringValueAt("desc") ?: article.primitiveString("summary"))?.trim().orEmpty()
            val images = collectOpusImages(
                singleUrls = listOfNotNull(article.stringValueAt("cover")),
                arrays = listOfNotNull(article.arrayValueAt("covers")),
            )
            val cvid = article.stringValueAt("id")?.toLongOrNull()
                ?: article.longValueAt("id")
                ?: oid.toLongOrNull()
            val jumpURL = normalizedURL(article.stringValueAt("jump_url"))
                ?: cardJumpURL
                ?: cvid?.let(ArticleURL::canonicalURL)
            if (title.isEmpty() && desc.isEmpty() && images.isEmpty() && jumpURL == null) return null
            return OpusReference(
                title = title,
                textRuns = if (desc.isEmpty()) emptyList() else listOf(RichTextRun.Text(desc)),
                images = images,
                targetURL = jumpURL,
                badgeText = "专栏",
            )
        }

        if (cardType == "LINK_CARD_TYPE_LIVE" || card.dictionaryValueAt("live") != null) {
            val live = card.dictionaryValueAt("live") ?: return null
            val title = live.stringValueAt("title")?.trim().orEmpty()
            val desc = listOfNotNull(
                live.stringValueAt("desc_first")?.trim()?.takeIf { it.isNotEmpty() },
                live.stringValueAt("desc_second")?.trim()?.takeIf { it.isNotEmpty() },
            ).joinToString(" · ")
            val cover = normalizedURL(live.stringValueAt("cover"))
            val jumpURL = normalizedURL(live.stringValueAt("jump_url")) ?: cardJumpURL
            if (title.isEmpty() && desc.isEmpty() && cover == null && jumpURL == null) return null
            return OpusReference(
                title = title,
                textRuns = if (desc.isEmpty()) emptyList() else listOf(RichTextRun.Text(desc)),
                images = listOfNotNull(cover?.let { OpusImage(it, 0, 0) }),
                targetURL = jumpURL,
                badgeText = "直播",
            )
        }

        if (cardType == "LINK_CARD_TYPE_PGC" || card.dictionaryValueAt("pgc") != null) {
            val pgc = card.dictionaryValueAt("pgc") ?: return null
            val title = pgc.stringValueAt("title")?.trim().orEmpty()
            val desc = (pgc.stringValueAt("desc") ?: pgc.stringValueAt("sub_title"))?.trim().orEmpty()
            val cover = normalizedURL(pgc.stringValueAt("cover") ?: pgc.stringValueAt("ep_cover"))
            val jumpURL = normalizedURL(pgc.stringValueAt("jump_url")) ?: cardJumpURL
            if (title.isEmpty() && desc.isEmpty() && cover == null && jumpURL == null) return null
            return OpusReference(
                title = title,
                textRuns = if (desc.isEmpty()) emptyList() else listOf(RichTextRun.Text(desc)),
                images = listOfNotNull(cover?.let { OpusImage(it, 0, 0) }),
                targetURL = jumpURL,
                badgeText = "番剧",
            )
        }

        if (cardType == "LINK_CARD_TYPE_MUSIC" || card.dictionaryValueAt("music") != null) {
            val music = card.dictionaryValueAt("music") ?: return null
            val title = music.stringValueAt("title")?.trim().orEmpty()
            val desc = (music.stringValueAt("label") ?: music.stringValueAt("singer"))?.trim().orEmpty()
            val cover = normalizedURL(music.stringValueAt("cover"))
            val jumpURL = normalizedURL(music.stringValueAt("jump_url")) ?: cardJumpURL
            if (title.isEmpty() && desc.isEmpty() && cover == null && jumpURL == null) return null
            return OpusReference(
                title = title,
                textRuns = if (desc.isEmpty()) emptyList() else listOf(RichTextRun.Text(desc)),
                images = listOfNotNull(cover?.let { OpusImage(it, 0, 0) }),
                targetURL = jumpURL,
                badgeText = "音频",
            )
        }

        if (cardType == "LINK_CARD_TYPE_GOODS" || card.dictionaryValueAt("goods") != null) {
            val goods = card.dictionaryValueAt("goods") ?: return null
            val item = goods.arrayValueAt("items")?.firstOrNull() as? JsonObject ?: goods
            val title = (item.stringValueAt("name") ?: item.stringValueAt("title"))?.trim().orEmpty()
            val desc = (item.stringValueAt("price") ?: item.stringValueAt("brief"))?.trim().orEmpty()
            val cover = normalizedURL(item.stringValueAt("img") ?: item.stringValueAt("cover"))
            val jumpURL = normalizedURL(item.stringValueAt("jump_url") ?: goods.stringValueAt("jump_url")) ?: cardJumpURL
            if (title.isEmpty() && desc.isEmpty() && cover == null && jumpURL == null) return null
            return OpusReference(
                title = title,
                textRuns = if (desc.isEmpty()) emptyList() else listOf(RichTextRun.Text(desc)),
                images = listOfNotNull(cover?.let { OpusImage(it, 0, 0) }),
                targetURL = jumpURL,
                badgeText = "商品",
            )
        }

        val common = card.dictionaryValueAt("common")
        if (cardType == "LINK_CARD_TYPE_COMMON" || common != null) {
            val source = common ?: return null
            val title = (source.stringValueAt("title") ?: source.stringValueAt("head_text"))?.trim().orEmpty()
            val desc = listOfNotNull(
                source.stringValueAt("desc1")?.trim()?.takeIf { it.isNotEmpty() },
                source.stringValueAt("desc2")?.trim()?.takeIf { it.isNotEmpty() },
            ).joinToString("\n")
            val cover = normalizedURL(source.stringValueAt("cover"))
            val jumpURL = normalizedURL(source.stringValueAt("jump_url")) ?: cardJumpURL
            if (title.isEmpty() && desc.isEmpty() && cover == null && jumpURL == null) return null
            return OpusReference(
                title = title,
                textRuns = if (desc.isEmpty()) emptyList() else listOf(RichTextRun.Text(desc)),
                images = listOfNotNull(cover?.let { OpusImage(it, 0, 0) }),
                targetURL = jumpURL,
                badgeText = "链接",
            )
        }

        return null
    }

    private fun parseDynamicItemReference(origItem: JsonObject): OpusReference? {
        val origType = origItem.stringValueAt("type") ?: ""
        val origModules = normalizeModules(origItem)
        val origDynamic = origModules.dictionaryValueAt("module_dynamic")
        val origMajor = origDynamic?.dictionaryValueAt("major")
        val origMajorType = origMajor?.stringValueAt("type") ?: ""
        val origBasic = origItem.dictionaryValueAt("basic")

        if (origType == "DYNAMIC_TYPE_NONE" || origMajorType == "MAJOR_TYPE_NONE") {
            val tip = origMajor?.stringValueAt("none", "tips")?.trim()?.takeIf { it.isNotEmpty() }
                ?: origDynamic?.stringValueAt("desc", "text")?.trim()?.takeIf { it.isNotEmpty() }
                ?: "源动态已被作者删除"
            return OpusReference(unavailableTip = tip)
        }

        val author = origModules.dictionaryValueAt("module_author")
        val authorName = author?.stringValueAt("name")?.trim().orEmpty()
        val authorMid = author?.longValueAt("mid") ?: 0L
        val authorAvatar = normalizedURL(author?.stringValueAt("face")) ?: ""
        val publishTime = author?.stringValueAt("pub_time")
            ?: author?.stringValueAt("pub_time_text")
            ?: author?.stringValueAt("pub_action")
            ?: ""

        val title = listOfNotNull(
            origModules.stringValueAt("module_title", "text"),
            origMajor?.stringValueAt("archive", "title"),
            origMajor?.stringValueAt("article", "title"),
            origMajor?.stringValueAt("pgc", "title"),
            origMajor?.stringValueAt("opus", "title"),
            origMajor?.stringValueAt("courses", "title"),
            origMajor?.stringValueAt("music", "title"),
            origMajor?.stringValueAt("medialist", "title"),
            origMajor?.stringValueAt("live", "title"),
            origMajor?.stringValueAt("common", "title"),
            origMajor?.stringValueAt("ugc_season", "title"),
        ).map { it.trim() }.firstOrNull { it.isNotEmpty() } ?: ""

        val contentParagraphs = parseOpusModulesParagraphs(origModules)
        val descNodes = parseOpusTextNodes(
            origDynamic?.arrayValueAt("desc", "rich_text_nodes")
                ?: origDynamic?.arrayValueAt("desc", "rich_text_nodes_v2")
                ?: origMajor?.arrayValueAt("opus", "summary", "rich_text_nodes")
                ?: origMajor?.arrayValueAt("opus", "summary", "rich_text_nodes_v2")
                ?: emptyList()
        )
        val descText = (
            origDynamic?.stringValueAt("desc", "text")
                ?: origMajor?.stringValueAt("opus", "summary", "text")
            )?.trim().orEmpty()
        val majorDesc = (
            origMajor?.stringValueAt("archive", "desc")
                ?: origMajor?.stringValueAt("article", "desc")
                ?: origMajor?.stringValueAt("common", "desc")
                ?: origMajor?.stringValueAt("live", "desc_first")
            )?.trim().orEmpty()

        val paragraphTextRuns = buildList {
            contentParagraphs.forEach { para ->
                para.blocks.forEach { block ->
                    val nodes = when (block) {
                        is OpusBlock.Text -> block.nodes
                        is OpusBlock.Quote -> block.nodes
                        else -> emptyList()
                    }
                    if (nodes.isNotEmpty()) {
                        val plain = nodes.joinToString("") {
                            when (it) {
                                is RichTextRun.Text -> it.text
                                is RichTextRun.Emote -> it.alt
                                is RichTextRun.Resource -> it.label
                            }
                        }.trim()
                        if (plain.isNotEmpty() && plain != title) {
                            if (isNotEmpty()) add(RichTextRun.Text("\n"))
                            addAll(nodes)
                        }
                    }
                }
            }
        }

        val textRuns = when {
            descNodes.isNotEmpty() -> descNodes
            descText.isNotEmpty() && descText != title -> listOf(RichTextRun.Text(descText))
            paragraphTextRuns.isNotEmpty() -> paragraphTextRuns
            majorDesc.isNotEmpty() && majorDesc != title -> listOf(RichTextRun.Text(majorDesc))
            else -> emptyList()
        }

        val paragraphImages = contentParagraphs.flatMap { para ->
            para.blocks.flatMap { block ->
                (block as? OpusBlock.Image)?.pics.orEmpty()
            }
        }
        val majorImages = collectOpusImages(
            singleUrls = listOfNotNull(
                origMajor?.stringValueAt("archive", "cover"),
                origMajor?.stringValueAt("pgc", "cover") ?: origMajor?.stringValueAt("pgc", "ep_cover"),
                origMajor?.stringValueAt("courses", "cover"),
                origMajor?.stringValueAt("music", "cover"),
                origMajor?.stringValueAt("medialist", "cover"),
                origMajor?.stringValueAt("live", "cover") ?: origMajor?.stringValueAt("live", "room_cover"),
                origMajor?.stringValueAt("common", "cover"),
                origMajor?.stringValueAt("ugc_season", "cover"),
            ),
            arrays = listOfNotNull(
                origMajor?.arrayValueAt("opus", "pics"),
                origMajor?.arrayValueAt("draw", "items"),
                origMajor?.arrayValueAt("article", "covers"),
            ),
        )
        val images = (paragraphImages + majorImages).distinctBy { it.url }

        val origId = origItem.stringValueAt("id_str")
            ?: origBasic?.stringValueAt("comment_id_str")
            ?: origBasic?.stringValueAt("rid_str")
        val archiveBvid = origMajor?.stringValueAt("archive", "bvid")?.trim()?.takeIf { it.isNotEmpty() }
        val articleCvid = origMajor?.stringValueAt("article", "id")?.toLongOrNull()
            ?: origMajor?.stringValueAt("article", "id_str")?.toLongOrNull()
            ?: origMajor?.longValueAt("article", "id")

        val targetURL = listOfNotNull(
            normalizedURL(origMajor?.stringValueAt("archive", "jump_url")),
            archiveBvid?.let { "https://www.bilibili.com/video/$it/" },
            normalizedURL(origMajor?.stringValueAt("pgc", "jump_url")),
            normalizedURL(origMajor?.stringValueAt("article", "jump_url")),
            articleCvid?.let(ArticleURL::canonicalURL),
            normalizedURL(origMajor?.stringValueAt("courses", "jump_url")),
            normalizedURL(origMajor?.stringValueAt("music", "jump_url")),
            normalizedURL(origMajor?.stringValueAt("medialist", "jump_url")),
            normalizedURL(origMajor?.stringValueAt("live", "jump_url")),
            normalizedURL(origMajor?.stringValueAt("ugc_season", "jump_url")),
            normalizedURL(origMajor?.stringValueAt("opus", "jump_url")),
            normalizedURL(origMajor?.stringValueAt("common", "jump_url")),
            normalizedURL(origBasic?.stringValueAt("jump_url")),
            origId?.takeIf { it.isNotEmpty() }?.let { "https://www.bilibili.com/opus/$it" },
        ).firstOrNull()

        val badgeText = when {
            origMajorType in setOf("MAJOR_TYPE_ARCHIVE", "MAJOR_TYPE_PGC", "MAJOR_TYPE_COURSES", "MAJOR_TYPE_MEDIALIST", "MAJOR_TYPE_UGC_SEASON") ||
                origType.contains("_AV") ||
                archiveBvid != null -> "视频"
            origMajorType == "MAJOR_TYPE_ARTICLE" || articleCvid != null -> "专栏"
            origMajorType == "MAJOR_TYPE_LIVE" -> "直播"
            images.isNotEmpty() -> "图片"
            else -> "动态"
        }

        if (authorName.isEmpty() && title.isEmpty() && textRuns.isEmpty() && images.isEmpty() && targetURL == null) {
            return null
        }

        return OpusReference(
            authorName = authorName,
            authorMid = authorMid,
            authorAvatar = authorAvatar,
            publishTime = publishTime,
            title = title,
            textRuns = textRuns,
            images = images,
            targetURL = targetURL,
            badgeText = badgeText,
        )
    }

    private fun parseAdditionalReference(additional: JsonObject): OpusReference? {
        val type = additional.stringValueAt("type") ?: ""
        if (type == "ADDITIONAL_TYPE_UGC" || additional.dictionaryValueAt("ugc") != null) {
            val ugc = additional.dictionaryValueAt("ugc") ?: return null
            val title = ugc.stringValueAt("title")?.trim().orEmpty()
            val desc = ugc.stringValueAt("desc_second")?.trim().orEmpty()
            val cover = normalizedURL(ugc.stringValueAt("cover"))
            val jumpURL = normalizedURL(ugc.stringValueAt("jump_url"))
            if (title.isEmpty() && desc.isEmpty() && cover == null && jumpURL == null) return null
            return OpusReference(
                title = title,
                textRuns = if (desc.isEmpty()) emptyList() else listOf(RichTextRun.Text(desc)),
                images = listOfNotNull(cover?.let { OpusImage(it, 0, 0) }),
                targetURL = jumpURL,
                badgeText = "视频",
            )
        }
        if (type == "ADDITIONAL_TYPE_OPUS" || additional.dictionaryValueAt("opus") != null) {
            val opus = additional.dictionaryValueAt("opus") ?: return null
            val title = opus.stringValueAt("title")?.trim().orEmpty()
            val desc = (
                opus.dictionaryValueAt("summary")?.stringValueAt("text")
                    ?: opus.primitiveString("desc")
                )?.trim().orEmpty()
            val images = collectOpusImages(
                singleUrls = listOfNotNull(opus.stringValueAt("cover")),
                arrays = listOfNotNull(opus.arrayValueAt("pics")),
            )
            val jumpURL = normalizedURL(opus.stringValueAt("jump_url"))
            if (title.isEmpty() && desc.isEmpty() && images.isEmpty() && jumpURL == null) return null
            return OpusReference(
                title = title,
                textRuns = if (desc.isEmpty()) emptyList() else listOf(RichTextRun.Text(desc)),
                images = images,
                targetURL = jumpURL,
                badgeText = "动态",
            )
        }
        if (type == "ADDITIONAL_TYPE_COMMON" || additional.dictionaryValueAt("common") != null) {
            val common = additional.dictionaryValueAt("common") ?: return null
            val title = (common.stringValueAt("title") ?: common.stringValueAt("head_text"))?.trim().orEmpty()
            val desc = listOfNotNull(
                common.stringValueAt("desc1")?.trim()?.takeIf { it.isNotEmpty() },
                common.stringValueAt("desc2")?.trim()?.takeIf { it.isNotEmpty() },
            ).joinToString("\n")
            val cover = normalizedURL(common.stringValueAt("cover"))
            val jumpURL = normalizedURL(common.stringValueAt("jump_url"))
            if (title.isEmpty() && desc.isEmpty() && cover == null && jumpURL == null) return null
            return OpusReference(
                title = title,
                textRuns = if (desc.isEmpty()) emptyList() else listOf(RichTextRun.Text(desc)),
                images = listOfNotNull(cover?.let { OpusImage(it, 0, 0) }),
                targetURL = jumpURL,
                badgeText = "链接",
            )
        }
        return null
    }

    private fun parseMajorReference(major: JsonObject, basic: JsonObject?): OpusReference? {
        val majorType = major.stringValueAt("type") ?: ""
        if (majorType in setOf("MAJOR_TYPE_DRAW", "MAJOR_TYPE_OPUS", "MAJOR_TYPE_NONE", "")) {
            return null
        }
        val syntheticItem = JsonObject(
            mapOf(
                "basic" to (basic ?: JsonObject(emptyMap())),
                "modules" to JsonObject(
                    mapOf(
                        "module_dynamic" to JsonObject(mapOf("major" to major)),
                    ),
                ),
            ),
        )
        return parseDynamicItemReference(syntheticItem)
    }

    private fun collectOpusImages(
        singleUrls: List<String>,
        arrays: List<List<JsonElement>>,
    ): List<OpusImage> {
        val result = mutableListOf<OpusImage>()
        arrays.forEach { items ->
            items.forEach { elem ->
                when (elem) {
                    is JsonObject -> {
                        val url = normalizedURL(elem.stringValueAt("url") ?: elem.stringValueAt("src"))
                        if (url != null) {
                            result.add(OpusImage(url, elem.intValueAt("width") ?: 0, elem.intValueAt("height") ?: 0))
                        }
                    }
                    is JsonPrimitive -> {
                        if (elem.isString) {
                            normalizedURL(elem.content)?.let { result.add(OpusImage(it, 0, 0)) }
                        }
                    }
                    else -> {}
                }
            }
        }
        singleUrls.forEach { raw ->
            normalizedURL(raw)?.let { result.add(OpusImage(it, 0, 0)) }
        }
        return result.distinctBy { it.url }
    }

    private fun JsonObject.primitiveString(key: String): String? =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content?.takeIf { it.isNotEmpty() }

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
        opusSchemePattern.find(value)?.let { match ->
            return "https://www.bilibili.com/opus/${match.groupValues[1]}"
        }
        videoSchemePattern.find(value)?.let { match ->
            return "https://www.bilibili.com/video/${match.groupValues[1]}/"
        }
        val normalized = when {
            value.startsWith("//") -> "https:$value"
            value.startsWith("http://") -> "https://${value.removePrefix("http://")}"
            value.startsWith("/") -> "https://www.bilibili.com$value"
            else -> value
        }
        return FocusNavigationPolicy.canonicalWebURL(normalized)
    }

    private suspend fun buildHeaders(targetUrl: String): Map<String, String> {
        val headers = mutableMapOf(
            "User-Agent" to userAgent,
            "Referer" to "https://www.bilibili.com/",
            "Accept" to "application/json, text/plain, */*",
        )
        return cookieProvider.attachCookies(headers, targetUrl)
    }

    private companion object {
        val opusSchemePattern = Regex(
            """^bilibili://(?:following/detail|opus/detail|dynamic)/(\d+)(?:[/?#].*)?$""",
            RegexOption.IGNORE_CASE,
        )
        val videoSchemePattern = Regex(
            """^bilibili://video/(BV[0-9A-Za-z]+)(?:[/?#].*)?$""",
            RegexOption.IGNORE_CASE,
        )
    }
}
