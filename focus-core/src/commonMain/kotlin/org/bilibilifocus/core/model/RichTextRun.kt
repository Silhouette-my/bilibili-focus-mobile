package org.bilibilifocus.core.model

import kotlinx.serialization.Serializable

@Serializable
sealed class RichTextRun {
    @Serializable
    data class Text(
        val text: String,
        val bold: Boolean = false,
        val italic: Boolean = false,
        val underline: Boolean = false,
        val strikethrough: Boolean = false,
        val color: String? = null,
        val linkUrl: String? = null,
    ) : RichTextRun()

    @Serializable
    data class Emote(
        val alt: String,
        val url: String,
        val width: Int = 0,
        val height: Int = 0,
        val animated: Boolean = isAnimatedImageURL(url),
    ) : RichTextRun()

    @Serializable
    data class Resource(
        val label: String,
        val url: String,
    ) : RichTextRun()

    companion object {
        fun plain(text: String): List<RichTextRun> =
            if (text.isEmpty()) emptyList() else listOf(Text(text))

        private fun isAnimatedImageURL(url: String): Boolean {
            val value = url.substringBefore('?').lowercase()
            return value.endsWith(".gif") || value.endsWith(".webp") || value.endsWith(".apng")
        }
    }
}

fun List<RichTextRun>.plainText(): String = joinToString(separator = "") { run ->
    when (run) {
        is RichTextRun.Text -> run.text
        is RichTextRun.Emote -> run.alt
        is RichTextRun.Resource -> run.label
    }
}
