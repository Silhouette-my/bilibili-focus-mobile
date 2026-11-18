package org.bilibilifocus.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.LinkAnnotation
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.bilibilifocus.android.ui.video.copyableCommentText
import org.bilibilifocus.core.model.RichTextRun
import org.bilibilifocus.core.model.VideoComment

class FocusCommentCopyAndRichTextTests {
    @Test
    fun copyableCommentTextPreservesEmoteAltAndFallsBackToRawContent() {
        val richComment = VideoComment(
            rpid = 1L,
            mid = 10L,
            authorName = "测试用户",
            avatarURL = "",
            content = "fallback",
            contentRuns = listOf(
                RichTextRun.Text("太好笑了"),
                RichTextRun.Emote(alt = "[doge]", url = "https://i0.hdslb.com/bfs/emote/doge.png"),
                RichTextRun.Resource(label = "@UP主", url = "https://space.bilibili.com/42"),
            ),
            likeCount = 0L,
            replyCount = 0L,
            publishTime = 0L,
        )
        assertEquals("太好笑了[doge]@UP主", copyableCommentText(richComment))

        val emptyRunsComment = richComment.copy(
            content = "原始纯文本评论",
            contentRuns = emptyList(),
        )
        assertEquals("原始纯文本评论", copyableCommentText(emptyRunsComment))
    }

    @Test
    fun buildRichTextContentKeepsEmoteAltAndLinkAnnotationsForSelectionAndClicks() {
        val clickedURLs = mutableListOf<String>()
        val runs = listOf(
            RichTextRun.Text("先看"),
            RichTextRun.Emote(alt = "[doge]", url = "https://i0.hdslb.com/bfs/emote/doge.png"),
            RichTextRun.Text("和"),
            RichTextRun.Resource(label = "@B站官方", url = "https://space.bilibili.com/2"),
            RichTextRun.Text("链接", linkUrl = "https://www.bilibili.com/video/BV1xx411c7mD"),
        )

        val model = buildRichTextContent(
            runs = runs,
            linkColor = Color.Blue,
            onOpenURL = { clickedURLs += it },
        )

        assertEquals("先看[doge]和@B站官方链接", model.annotatedString.text)
        assertTrue(!model.annotatedString.text.contains('\uFFFC'))
        assertEquals(1, model.emotes.size)
        assertEquals("[doge]", model.emotes.single().run.alt)

        val linkRanges = model.annotatedString.getLinkAnnotations(0, model.annotatedString.length)
        assertEquals(2, linkRanges.size)
        assertTrue(linkRanges.all { it.item is LinkAnnotation.Clickable })

        (linkRanges[0].item as LinkAnnotation.Clickable).linkInteractionListener?.onClick(linkRanges[0].item)
        (linkRanges[1].item as LinkAnnotation.Clickable).linkInteractionListener?.onClick(linkRanges[1].item)
        assertEquals(
            listOf(
                "https://space.bilibili.com/2",
                "https://www.bilibili.com/video/BV1xx411c7mD",
            ),
            clickedURLs,
        )
    }
}
