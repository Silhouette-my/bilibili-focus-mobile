package org.bilibilifocus.core.model

import kotlinx.serialization.Serializable

@Serializable
data class DynamicCard(
    val id: String,
    val kind: Kind,
    val author: Author,
    val publishTime: String,
    val text: String,
    val coverURLs: List<String>,
    val targetURL: String,
    val videoURL: String? = null,
    val quotedCard: QuotedCard? = null,
) {
    @Serializable
    enum class Kind {
        TEXT,
        IMAGE,
        VIDEO,
        ARTICLE_LIKE,
    }

    @Serializable
    data class Author(
        val name: String,
        val mid: Long = 0,
        val avatarURL: String? = null,
    )

    @Serializable
    data class QuotedCard(
        val id: String = "",
        val kind: Kind = Kind.TEXT,
        val author: Author = Author(name = ""),
        val publishTime: String = "",
        val title: String = "",
        val text: String = "",
        val coverURLs: List<String> = emptyList(),
        val targetURL: String? = null,
        val videoURL: String? = null,
        val unavailableTip: String? = null,
    )
}
