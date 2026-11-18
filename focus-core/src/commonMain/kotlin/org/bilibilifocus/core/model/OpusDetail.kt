package org.bilibilifocus.core.model

data class OpusDetail(
    val id: String,
    val commentId: Long,
    val author: OpusAuthor,
    val publishTime: String,
    val paragraphs: List<Paragraph>,
    /** Comment area type from `basic.comment_type`; 0 when the API did not say. */
    val commentType: Int = 0,
) {
    data class Paragraph(val blocks: List<OpusBlock>)
}

data class OpusAuthor(
    val name: String,
    val mid: Long,
    val avatarURL: String,
)

sealed class OpusBlock {
    data class Text(val nodes: List<RichTextRun>) : OpusBlock()
    data class Image(val pics: List<OpusImage>) : OpusBlock()
    data class Code(val lang: String, val content: String) : OpusBlock()
    data class Quote(val nodes: List<RichTextRun>) : OpusBlock()
    data class Reference(val reference: OpusReference) : OpusBlock()
}

data class OpusReference(
    val authorName: String = "",
    val authorMid: Long = 0L,
    val authorAvatar: String = "",
    val publishTime: String = "",
    val title: String = "",
    val textRuns: List<RichTextRun> = emptyList(),
    val images: List<OpusImage> = emptyList(),
    val targetURL: String? = null,
    val badgeText: String = "",
    val unavailableTip: String? = null,
)

data class OpusImage(
    val url: String,
    val width: Int,
    val height: Int,
)
