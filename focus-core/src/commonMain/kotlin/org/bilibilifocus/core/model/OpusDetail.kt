package org.bilibilifocus.core.model

data class OpusDetail(
    val id: String,
    val commentId: Long,
    val author: OpusAuthor,
    val publishTime: String,
    val paragraphs: List<Paragraph>,
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
}

data class OpusImage(
    val url: String,
    val width: Int,
    val height: Int,
)
