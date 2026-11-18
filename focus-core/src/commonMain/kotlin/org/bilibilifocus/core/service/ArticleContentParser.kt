package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import org.bilibilifocus.core.model.ArticleBlock
import org.bilibilifocus.core.model.RichTextRun
import org.bilibilifocus.core.model.TextAlignment

object ArticleContentParser {
    private val json = Json { ignoreUnknownKeys = true }
    private val scriptStylePattern = Regex("(?is)<(script|style)[^>]*>.*?</\\1>")
    private val breakPattern = Regex("(?i)<br\\s*/?>")
    private val htmlTokenPattern = Regex("(?s)<[^>]+>|[^<]+")
    private val tagNamePattern = Regex("</?\\s*([a-zA-Z0-9]+)")
    private val quotedAttributePattern = Regex("([A-Za-z0-9_:-]+)\\s*=\\s*([\"'])(.*?)\\2", RegexOption.DOT_MATCHES_ALL)
    private val bareAttributePattern = Regex("([A-Za-z0-9_:-]+)\\s*=\\s*([^\\s>\"']+)")
    private val colorPattern = Regex("(?i)color\\s*:\\s*([^;]+)")
    private val encodedByteSequencePattern = Regex("(?:%[0-9A-Fa-f]{2})+")
    private val decimalEntityPattern = Regex("&#(\\d+);")
    private val hexEntityPattern = Regex("&#x([0-9A-Fa-f]+);")

    fun parse(rawContent: String): List<ArticleBlock> {
        val content = rawContent.trim()
        if (content.isEmpty()) return emptyList()
        val ops = runCatching {
            (json.parseToJsonElement(content) as? JsonObject)?.arrayValueAt("ops")
        }.getOrNull()
        return if (ops != null) parseOps(ops.mapNotNull { it as? JsonObject }) else parseHTML(content)
    }

    private fun parseOps(ops: List<JsonObject>): List<ArticleBlock> {
        val blocks = mutableListOf<ArticleBlock>()
        val currentRuns = mutableListOf<RichTextRun>()

        fun emitLine(attributes: JsonObject? = null) {
            if (currentRuns.isEmpty()) return
            val runs = currentRuns.toList()
            currentRuns.clear()
            val header = attributes?.get("header")?.jsonPrimitive?.intOrNull
            when {
                header != null -> blocks += ArticleBlock.Heading(runs, header.coerceIn(1, 6))
                attributes?.get("blockquote")?.jsonPrimitive?.booleanOrNull == true -> blocks += ArticleBlock.Quote(runs)
                attributes?.get("list")?.jsonPrimitive?.contentOrNull != null -> {
                    val ordered = attributes["list"]?.jsonPrimitive?.contentOrNull == "ordered"
                    val last = blocks.lastOrNull()
                    if (last is ArticleBlock.ListBlock && last.ordered == ordered) {
                        blocks[blocks.lastIndex] = last.copy(items = last.items + listOf(runs))
                    } else {
                        blocks += ArticleBlock.ListBlock(ordered, listOf(runs))
                    }
                }
                attributes?.get("code-block") != null -> {
                    val text = runs.joinToString("") { (it as? RichTextRun.Text)?.text ?: "" }
                    val last = blocks.lastOrNull()
                    if (last is ArticleBlock.CodeBlock) {
                        blocks[blocks.lastIndex] = last.copy(code = last.code + "\n" + text)
                    } else {
                        blocks += ArticleBlock.CodeBlock(text)
                    }
                }
                else -> blocks += ArticleBlock.Paragraph(runs, alignmentFrom(attributes?.get("align")?.jsonPrimitive?.contentOrNull))
            }
        }

        for (op in ops) {
            val insert = op["insert"] ?: continue
            val attributes = op.dictionaryValueAt("attributes")
            if (insert is JsonPrimitive && insert.isString) {
                val parts = insert.content.split('\n')
                parts.forEachIndexed { index, value ->
                    if (value.isNotEmpty()) currentRuns += textRun(value, attributes)
                    if (index < parts.lastIndex) emitLine(attributes)
                }
                continue
            }

            val embed = insert as? JsonObject ?: continue
            val image = embed.dictionaryValueAt("native-image")
                ?: embed.dictionaryValueAt("image")
            if (image != null) {
                emitLine()
                normalizedURL(image.stringValueAt("url") ?: image.stringValueAt("src"))?.let { url ->
                    blocks += ArticleBlock.Image(
                        url = url,
                        width = image.intValueAt("width") ?: 0,
                        height = image.intValueAt("height") ?: 0,
                        caption = image.stringValueAt("alt") ?: "",
                    )
                }
                continue
            }
            val rawImage = (embed["native-image"] as? JsonPrimitive)?.contentOrNull
                ?: (embed["image"] as? JsonPrimitive)?.contentOrNull
            if (rawImage != null) {
                emitLine()
                normalizedURL(rawImage)?.let { url -> blocks += ArticleBlock.Image(url, 0, 0) }
                continue
            }

            if (embed.keys.any { it in setOf("cut-off", "divider", "hr") }) {
                emitLine()
                blocks += ArticleBlock.Divider
                continue
            }

            val resourceEntry = embed.entries.firstOrNull()
            val resource = resourceEntry?.value as? JsonObject
            val target = resource?.stringValueAt("url")
                ?: resource?.stringValueAt("jump_url")
                ?: resourceEntry?.key?.let { key -> resource?.let { embeddedResourceURL(key, it) } }
            if (resource != null) {
                emitLine()
                blocks += ArticleBlock.Resource(
                    title = resource.stringValueAt("title") ?: resource.stringValueAt("name") ?: "站内内容",
                    url = normalizedURL(target) ?: target ?: "https://www.bilibili.com/",
                )
            }
        }
        emitLine()
        return blocks.filterNot(::isEmptyBlock)
    }

    private fun textRun(text: String, attributes: JsonObject?): RichTextRun.Text = RichTextRun.Text(
        text = decodeEntities(text),
        bold = attributes?.get("bold")?.jsonPrimitive?.booleanOrNull == true,
        italic = attributes?.get("italic")?.jsonPrimitive?.booleanOrNull == true,
        underline = attributes?.get("underline")?.jsonPrimitive?.booleanOrNull == true,
        strikethrough = attributes?.get("strike")?.jsonPrimitive?.booleanOrNull == true,
        color = attributes?.get("color")?.jsonPrimitive?.contentOrNull,
        linkUrl = normalizedURL(attributes?.get("link")?.jsonPrimitive?.contentOrNull),
    )

    private fun parseHTML(source: String): List<ArticleBlock> {
        val html = source
            .replace(scriptStylePattern, "")
            .replace(breakPattern, "<br>")
        val blocks = mutableListOf<ArticleBlock>()
        val runs = mutableListOf<RichTextRun>()
        var boldDepth = 0
        var italicDepth = 0
        var underlineDepth = 0
        var strikeDepth = 0
        var linkURL: String? = null
        var color: String? = null
        val colorStack = mutableListOf<String?>()
        var alignment = TextAlignment.START
        var headingLevel: Int? = null
        var quote = false
        var listOrdered: Boolean? = null
        val listItems = mutableListOf<List<RichTextRun>>()
        var codeLanguage = ""
        var codeBuffer: StringBuilder? = null

        fun flushRuns() {
            val value = runs.toList().trimmedRuns()
            runs.clear()
            if (value.isEmpty()) return
            when {
                headingLevel != null -> blocks += ArticleBlock.Heading(value, headingLevel!!)
                quote -> blocks += ArticleBlock.Quote(value)
                listOrdered != null -> listItems += value
                else -> blocks += ArticleBlock.Paragraph(value, alignment)
            }
        }

        fun flushList() {
            flushRuns()
            val ordered = listOrdered ?: return
            if (listItems.isNotEmpty()) blocks += ArticleBlock.ListBlock(ordered, listItems.toList())
            listItems.clear()
            listOrdered = null
        }

        val tokens = htmlTokenPattern.findAll(html).map { it.value }
        for (token in tokens) {
            if (!token.startsWith('<')) {
                val text = decodeEntities(token)
                if (codeBuffer != null) codeBuffer?.append(text)
                else if (text.isNotEmpty()) runs += RichTextRun.Text(
                    text = text,
                    bold = boldDepth > 0,
                    italic = italicDepth > 0,
                    underline = underlineDepth > 0,
                    strikethrough = strikeDepth > 0,
                    color = color,
                    linkUrl = linkURL,
                )
                continue
            }

            val closing = token.startsWith("</")
            val tag = tagNamePattern.find(token)?.groupValues?.getOrNull(1)?.lowercase() ?: continue
            val attrs = parseAttributes(token)
            if (closing) {
                when (tag) {
                    "strong", "b" -> boldDepth = (boldDepth - 1).coerceAtLeast(0)
                    "em", "i" -> italicDepth = (italicDepth - 1).coerceAtLeast(0)
                    "u" -> underlineDepth = (underlineDepth - 1).coerceAtLeast(0)
                    "s", "del" -> strikeDepth = (strikeDepth - 1).coerceAtLeast(0)
                    "span", "font" -> color = colorStack.removeLastOrNull()
                    "a" -> linkURL = null
                    "p", "div" -> flushRuns()
                    "h1", "h2", "h3", "h4", "h5", "h6" -> { flushRuns(); headingLevel = null }
                    "blockquote" -> { flushRuns(); quote = false }
                    "li" -> flushRuns()
                    "ul", "ol" -> flushList()
                    "pre" -> {
                        val code = codeBuffer?.toString()?.trimEnd().orEmpty()
                        if (code.isNotEmpty()) blocks += ArticleBlock.CodeBlock(code, codeLanguage)
                        codeBuffer = null
                        codeLanguage = ""
                    }
                    "figcaption" -> {
                        val caption = runs.toList().plainTextValue().trim()
                        runs.clear()
                        val last = blocks.lastOrNull()
                        if (caption.isNotEmpty() && last is ArticleBlock.Image) {
                            blocks[blocks.lastIndex] = last.copy(caption = caption)
                        }
                    }
                }
                continue
            }

            when (tag) {
                "strong", "b" -> boldDepth++
                "em", "i" -> italicDepth++
                "u" -> underlineDepth++
                "s", "del" -> strikeDepth++
                "span", "font" -> {
                    colorStack += color
                    color = attrs["color"] ?: colorFromStyle(attrs["style"]) ?: color
                }
                "a" -> linkURL = normalizedURL(attrs["href"])
                "br" -> runs += RichTextRun.Text(
                    text = "\n",
                    bold = boldDepth > 0,
                    italic = italicDepth > 0,
                    underline = underlineDepth > 0,
                    strikethrough = strikeDepth > 0,
                    color = color,
                    linkUrl = linkURL,
                )
                "p", "div" -> {
                    flushRuns()
                    alignment = alignmentFromStyle(attrs["style"])
                }
                "h1", "h2", "h3", "h4", "h5", "h6" -> {
                    flushRuns()
                    headingLevel = tag.drop(1).toIntOrNull() ?: 2
                }
                "blockquote" -> { flushRuns(); quote = true }
                "ul", "ol" -> { flushList(); listOrdered = tag == "ol" }
                "li" -> flushRuns()
                "pre" -> {
                    flushRuns()
                    codeBuffer = StringBuilder()
                    codeLanguage = attrs["data-lang"]?.substringBefore('@') ?: attrs["lang"] ?: ""
                    attrs["codecontent"]?.let { codeBuffer?.append(decodePercentEncoded(it)) }
                }
                "hr" -> { flushRuns(); blocks += ArticleBlock.Divider }
                "img" -> {
                    val classes = attrs["class"].orEmpty()
                    val aid = attrs["aid"]
                    if ("cut-off" in classes) {
                        flushRuns(); blocks += ArticleBlock.Divider
                    } else if (aid != null && "card" in classes) {
                        flushRuns()
                        val target = resourceURL(classes, aid)
                        blocks += ArticleBlock.Resource(resourceTitle(classes), target)
                    } else {
                        val rawURL = attrs["data-src"] ?: attrs["data-original"] ?: attrs["src"]
                        normalizedURL(rawURL)?.let { url ->
                            flushRuns()
                            blocks += ArticleBlock.Image(
                                url = url,
                                width = attrs["width"]?.toIntOrNull() ?: 0,
                                height = attrs["height"]?.toIntOrNull() ?: 0,
                                caption = attrs["alt"].orEmpty(),
                            )
                        }
                    }
                }
            }
        }
        flushList()
        flushRuns()
        return blocks.filterNot(::isEmptyBlock)
    }

    private fun parseAttributes(tag: String): Map<String, String> {
        val result = mutableMapOf<String, String>()
        quotedAttributePattern.findAll(tag).forEach { match ->
            result[match.groupValues[1].lowercase()] = decodeEntities(match.groupValues[3])
        }
        bareAttributePattern.findAll(tag).forEach { match ->
            val key = match.groupValues[1].lowercase()
            result.getOrPut(key) { decodeEntities(match.groupValues[2]) }
        }
        return result
    }

    private fun alignmentFromStyle(style: String?): TextAlignment = when {
        style?.contains("text-align:center", ignoreCase = true) == true || style?.contains("text-align: center", ignoreCase = true) == true -> TextAlignment.CENTER
        style?.contains("text-align:right", ignoreCase = true) == true || style?.contains("text-align: right", ignoreCase = true) == true -> TextAlignment.END
        else -> TextAlignment.START
    }

    private fun colorFromStyle(style: String?): String? =
        colorPattern.find(style.orEmpty())
            ?.groupValues
            ?.getOrNull(1)
            ?.trim()

    private fun alignmentFrom(value: String?): TextAlignment = when (value?.lowercase()) {
        "center" -> TextAlignment.CENTER
        "right", "end" -> TextAlignment.END
        else -> TextAlignment.START
    }

    private fun resourceTitle(classes: String): String = when {
        "video-card" in classes -> "视频"
        "article-card" in classes -> "专栏"
        "fanju-card" in classes -> "番剧"
        "live-card" in classes -> "直播"
        "music-card" in classes -> "音频"
        else -> "站内内容"
    }

    private fun resourceURL(classes: String, id: String): String = when {
        "video-card" in classes -> "https://www.bilibili.com/video/av${id.substringBefore(',')}"
        "article-card" in classes -> "https://www.bilibili.com/read/cv$id"
        "fanju-card" in classes -> "https://www.bilibili.com/bangumi/play/${id.removePrefix("ep")}"
        "live-card" in classes -> "https://live.bilibili.com/$id"
        "music-card" in classes -> "https://www.bilibili.com/audio/${id.removePrefix("au")}"
        else -> "https://www.bilibili.com/"
    }

    private fun embeddedResourceURL(kind: String, resource: JsonObject): String? {
        val type = (resource.stringValueAt("type") ?: kind).lowercase()
        val bvid = resource.stringValueAt("bvid") ?: resource.stringValueAt("bv_id")
        if (bvid != null || "video" in type || "archive" in type) {
            if (bvid != null) return "https://www.bilibili.com/video/$bvid"
            val aid = resource.stringValueAt("aid") ?: resource.stringValueAt("id") ?: resource.longValueAt("aid")?.toString()
            if (aid != null) return "https://www.bilibili.com/video/av${aid.removePrefix("av")}"
        }
        if ("article" in type) {
            val cvid = resource.stringValueAt("cvid") ?: resource.stringValueAt("id") ?: resource.longValueAt("id")?.toString()
            if (cvid != null) return "https://www.bilibili.com/read/cv${cvid.removePrefix("cv")}"
        }
        if ("bangumi" in type || "pgc" in type || "episode" in type) {
            val episode = resource.stringValueAt("ep_id") ?: resource.stringValueAt("id") ?: resource.longValueAt("ep_id")?.toString()
            if (episode != null) return "https://www.bilibili.com/bangumi/play/ep${episode.removePrefix("ep")}"
        }
        if ("live" in type) {
            val room = resource.stringValueAt("room_id") ?: resource.stringValueAt("id") ?: resource.longValueAt("room_id")?.toString()
            if (room != null) return "https://live.bilibili.com/$room"
        }
        if ("audio" in type || "music" in type) {
            val audio = resource.stringValueAt("auid") ?: resource.stringValueAt("id") ?: resource.longValueAt("id")?.toString()
            if (audio != null) return "https://www.bilibili.com/audio/au${audio.removePrefix("au")}"
        }
        return null
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

    private fun decodePercentEncoded(value: String): String {
        val result = encodedByteSequencePattern.replace(value.replace("+", " ")) { match ->
            ByteArray(match.value.length / 3) { index ->
                match.value.substring(index * 3 + 1, index * 3 + 3).toInt(16).toByte()
            }.decodeToString()
        }
        return decodeEntities(result)
    }

    private fun decodeEntities(value: String): String {
        var result = value
            .replace("&nbsp;", " ")
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
        result = decimalEntityPattern.replace(result) { match ->
            decodedCodePoint(match.groupValues[1].toIntOrNull()) ?: match.value
        }
        result = hexEntityPattern.replace(result) { match ->
            decodedCodePoint(match.groupValues[1].toIntOrNull(16)) ?: match.value
        }
        return result
    }

    private fun decodedCodePoint(value: Int?): String? = when (value) {
        null, in 0xD800..0xDFFF -> null
        in 0..0xFFFF -> value.toChar().toString()
        in 0x10000..0x10FFFF -> {
            val offset = value - 0x10000
            charArrayOf((0xD800 + (offset ushr 10)).toChar(), (0xDC00 + (offset and 0x3FF)).toChar())
                .concatToString()
        }
        else -> null
    }

    private fun List<RichTextRun>.trimmedRuns(): List<RichTextRun> {
        if (isEmpty()) return this
        val copy = toMutableList()
        val first = copy.firstOrNull() as? RichTextRun.Text
        if (first != null) copy[0] = first.copy(text = first.text.trimStart())
        val last = copy.lastOrNull() as? RichTextRun.Text
        if (last != null) copy[copy.lastIndex] = last.copy(text = last.text.trimEnd())
        return copy.filterNot { it is RichTextRun.Text && it.text.isEmpty() }
    }

    private fun List<RichTextRun>.plainTextValue(): String = joinToString("") {
        when (it) {
            is RichTextRun.Text -> it.text
            is RichTextRun.Emote -> it.alt
            is RichTextRun.Resource -> it.label
        }
    }

    private fun isEmptyBlock(block: ArticleBlock): Boolean = when (block) {
        is ArticleBlock.Paragraph -> block.runs.isEmpty()
        is ArticleBlock.Heading -> block.runs.isEmpty()
        is ArticleBlock.Quote -> block.runs.isEmpty()
        is ArticleBlock.ListBlock -> block.items.isEmpty()
        is ArticleBlock.CodeBlock -> block.code.isEmpty()
        else -> false
    }
}
