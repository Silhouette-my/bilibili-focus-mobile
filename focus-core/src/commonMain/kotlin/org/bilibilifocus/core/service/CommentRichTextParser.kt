package org.bilibilifocus.core.service

import io.ktor.http.parseUrl
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonArray
import org.bilibilifocus.core.model.RichTextRun

internal object CommentRichTextParser {
    fun parseImageURLs(content: JsonObject): List<String> =
        (content["pictures"] as? JsonArray).orEmpty().mapNotNull { rawPicture ->
            val picture = rawPicture as? JsonObject ?: return@mapNotNull null
            normalizedImageURL(picture.stringValueAt("img_src"))
        }

    fun parse(content: JsonObject): List<RichTextRun> {
        parseNodes(content)?.takeIf { it.isNotEmpty() }?.let { return it }

        val message = content.stringValueAt("message") ?: return emptyList()
        val replacements = mutableMapOf<String, RichTextRun>()

        content.dictionaryValueAt("emote")?.forEach { (token, rawValue) ->
            val emote = rawValue as? JsonObject ?: return@forEach
            val url = normalizedURL(
                emote.stringValueAt("gif_url")
                    ?: emote.stringValueAt("url")
                    ?: emote.stringValueAt("icon_url")
            ) ?: return@forEach
            val meta = emote.dictionaryValueAt("meta")
            val size = meta?.intValueAt("size") ?: 1
            replacements[token] = RichTextRun.Emote(
                alt = emote.stringValueAt("text") ?: token,
                url = url,
                width = size,
                height = size,
            )
        }

        content.dictionaryValueAt("jump_url")?.forEach { (token, rawValue) ->
            val target = when (rawValue) {
                is JsonPrimitive -> rawValue.content
                is JsonObject -> rawValue.stringValueAt("url") ?: rawValue.stringValueAt("jump_url")
                else -> null
            }?.let(::normalizedURL) ?: return@forEach
            if (token !in replacements) {
                replacements[token] = RichTextRun.Text(text = token, linkUrl = target)
            }
        }

        return replaceTokens(message, replacements)
    }

    private fun parseNodes(content: JsonObject): List<RichTextRun>? {
        val nodes = content.arrayValueAt("rich_text_nodes") ?: return null
        return nodes.mapNotNull { rawNode ->
            val node = rawNode as? JsonObject ?: return@mapNotNull null
            val text = node.stringValueAt("text")
                ?: node.stringValueAt("orig_text")
                ?: node.stringValueAt("word", "words")
                ?: ""
            val emojiURL = normalizedURL(
                node.stringValueAt("emoji", "icon_url")
                    ?: node.stringValueAt("emoji", "url")
                    ?: node.stringValueAt("rich", "emoji", "icon_url")
                    ?: node.stringValueAt("icon_url")
            )
            if (emojiURL != null) {
                val emoji = node.dictionaryValueAt("emoji") ?: node.dictionaryValueAt("rich", "emoji")
                RichTextRun.Emote(
                    alt = text.ifEmpty { emoji?.stringValueAt("text") ?: "[表情]" },
                    url = emojiURL,
                    width = emoji?.intValueAt("meta", "size") ?: 0,
                    height = emoji?.intValueAt("meta", "size") ?: 0,
                )
            } else if (text.isNotEmpty()) {
                RichTextRun.Text(
                    text = text,
                    linkUrl = normalizedURL(node.stringValueAt("jump_url") ?: node.stringValueAt("link")),
                )
            } else {
                null
            }
        }
    }

    private fun replaceTokens(message: String, replacements: Map<String, RichTextRun>): List<RichTextRun> {
        if (replacements.isEmpty()) return RichTextRun.plain(message)
        val tokens = replacements.keys.filter(String::isNotEmpty).sortedByDescending(String::length)
        val result = mutableListOf<RichTextRun>()
        var cursor = 0
        while (cursor < message.length) {
            var matchIndex = -1
            var matchedToken: String? = null
            for (token in tokens) {
                val index = message.indexOf(token, startIndex = cursor)
                if (index >= 0 && (matchIndex < 0 || index < matchIndex || (index == matchIndex && token.length > (matchedToken?.length ?: 0)))) {
                    matchIndex = index
                    matchedToken = token
                }
            }
            val token = matchedToken
            if (matchIndex < 0 || token == null) {
                result += RichTextRun.Text(message.substring(cursor))
                break
            }
            if (matchIndex > cursor) result += RichTextRun.Text(message.substring(cursor, matchIndex))
            replacements[token]?.let(result::add)
            cursor = matchIndex + token.length
        }
        return result
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

    private fun normalizedImageURL(raw: String?): String? {
        val value = raw?.trim()?.takeIf(String::isNotEmpty) ?: return null
        val normalized = when {
            value.startsWith("//") -> "https:$value"
            value.startsWith("http://", ignoreCase = true) -> "https://${value.substringAfter("://")}"
            value.startsWith("https://", ignoreCase = true) -> "https://${value.substringAfter("://")}"
            else -> null
        } ?: return null
        val parsed = parseUrl(normalized) ?: return null
        if (parsed.protocol.name.lowercase() != "https" || parsed.host.isBlank()) return null
        return normalized
    }
}
