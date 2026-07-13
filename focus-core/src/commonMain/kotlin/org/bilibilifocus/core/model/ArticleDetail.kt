package org.bilibilifocus.core.model

import kotlinx.serialization.Serializable

@Serializable
data class ArticleDetail(
    val cvid: Long,
    val title: String,
    val author: ArticleAuthor,
    val publishTime: Long,
    val stats: ArticleStats,
    val bannerUrl: String,
    val blocks: List<ArticleBlock>,
    val tags: List<String>,
    val originalURL: String,
)

@Serializable
data class ArticleAuthor(
    val mid: Long,
    val name: String,
    val avatarURL: String,
)

@Serializable
data class ArticleStats(
    val views: Long,
    val likes: Long,
    val coins: Long,
    val favorites: Long,
    val comments: Long,
)

@Serializable
sealed class ArticleBlock {
    @Serializable
    data class Paragraph(val runs: List<RichTextRun>, val alignment: TextAlignment = TextAlignment.START) : ArticleBlock()

    @Serializable
    data class Heading(val runs: List<RichTextRun>, val level: Int) : ArticleBlock()

    @Serializable
    data class Image(val url: String, val width: Int, val height: Int, val caption: String = "") : ArticleBlock()

    @Serializable
    data class CodeBlock(val code: String, val language: String = "") : ArticleBlock()

    @Serializable
    data class Quote(val runs: List<RichTextRun>) : ArticleBlock()

    @Serializable
    data class ListBlock(val ordered: Boolean, val items: List<List<RichTextRun>>) : ArticleBlock()

    @Serializable
    data class Resource(val title: String, val url: String) : ArticleBlock()

    @Serializable
    data object Divider : ArticleBlock()
}

@Serializable
enum class TextAlignment {
    START,
    CENTER,
    END,
}
