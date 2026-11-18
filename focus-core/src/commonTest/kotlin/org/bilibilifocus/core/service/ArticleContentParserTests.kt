package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.model.ArticleBlock
import org.bilibilifocus.core.model.RichTextRun
import org.bilibilifocus.core.model.TextAlignment
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class ArticleContentParserTests {
    @Test
    fun `encoded code and numeric entities preserve Chinese and supplementary Unicode`() {
        val blocks = ArticleContentParser.parse("""
            <pre codecontent="%E6%B5%8B%E8%AF%95%20%F0%9F%98%80%2B100%"></pre>
            <p>&#128512; &#x1F600; &#xD800;</p>
        """.trimIndent())
        assertEquals("测试 😀+100%", assertIs<ArticleBlock.CodeBlock>(blocks[0]).code)
        val text = assertIs<ArticleBlock.Paragraph>(blocks[1]).runs.joinToString("") { (it as RichTextRun.Text).text }
        assertEquals("😀 😀 &#xD800;", text)
    }

    @Test
    fun `modern ops preserve blocks inline styles images and resources`() {
        val blocks = ArticleContentParser.parse(
            """
            {"ops":[
              {"insert":"标题"},{"attributes":{"header":2},"insert":"\n"},
              {"attributes":{"bold":true,"underline":true,"color":"#fb7299","link":"//www.bilibili.com/video/BV1TEST"},"insert":"链接"},
              {"attributes":{"align":"center"},"insert":"\n"},
              {"attributes":{"class":"normal-img"},"insert":{"native-image":{"url":"//i0.hdslb.com/article.jpg","width":1200,"height":800,"alt":"图注"}}},
              {"insert":{"native-video":{"title":"相关视频","bvid":"BV1TEST"}}},
              {"insert":{"cut-off":true}}
            ]}
            """.trimIndent()
        )

        val heading = assertIs<ArticleBlock.Heading>(blocks[0])
        assertEquals(2, heading.level)
        assertEquals("标题", (heading.runs.single() as RichTextRun.Text).text)

        val paragraph = assertIs<ArticleBlock.Paragraph>(blocks[1])
        assertEquals(TextAlignment.CENTER, paragraph.alignment)
        val linked = assertIs<RichTextRun.Text>(paragraph.runs.single())
        assertTrue(linked.bold)
        assertTrue(linked.underline)
        assertEquals("#fb7299", linked.color)
        assertEquals("https://www.bilibili.com/video/BV1TEST", linked.linkUrl)

        val image = assertIs<ArticleBlock.Image>(blocks[2])
        assertEquals("https://i0.hdslb.com/article.jpg", image.url)
        assertEquals(1200, image.width)
        assertEquals("图注", image.caption)

        val resource = assertIs<ArticleBlock.Resource>(blocks[3])
        assertEquals("相关视频", resource.title)
        assertEquals("https://www.bilibili.com/video/BV1TEST", resource.url)
        assertIs<ArticleBlock.Divider>(blocks[4])
    }

    @Test
    fun `legacy html preserves structure lazy images captions lists code and divider`() {
        val blocks = ArticleContentParser.parse(
            """
            <h2>旧版标题</h2>
            <p style="text-align: center">普通<strong>粗体</strong><span style="color:#00a1d6">蓝色</span><a href="//www.bilibili.com/read/cv2">链接</a></p>
            <blockquote>引用</blockquote>
            <ol><li>第一项</li><li>第二项</li></ol>
            <pre data-lang="kotlin">val answer = 42</pre>
            <figure><img data-src="//i0.hdslb.com/lazy.webp" width="640" height="360"><figcaption>图片说明</figcaption></figure>
            <hr>
            """.trimIndent()
        )

        assertIs<ArticleBlock.Heading>(blocks[0])
        val paragraph = assertIs<ArticleBlock.Paragraph>(blocks[1])
        assertEquals(TextAlignment.CENTER, paragraph.alignment)
        assertEquals(listOf("普通", "粗体", "蓝色", "链接"), paragraph.runs.map { (it as RichTextRun.Text).text })
        assertTrue((paragraph.runs[1] as RichTextRun.Text).bold)
        assertEquals("#00a1d6", (paragraph.runs[2] as RichTextRun.Text).color)
        assertEquals("https://www.bilibili.com/read/cv2", (paragraph.runs[3] as RichTextRun.Text).linkUrl)
        assertIs<ArticleBlock.Quote>(blocks[2])
        assertEquals(2, assertIs<ArticleBlock.ListBlock>(blocks[3]).items.size)
        assertEquals("val answer = 42", assertIs<ArticleBlock.CodeBlock>(blocks[4]).code)
        val image = assertIs<ArticleBlock.Image>(blocks[5])
        assertEquals("图片说明", image.caption)
        assertEquals(640, image.width)
        assertIs<ArticleBlock.Divider>(blocks[6])
    }
}

class CommentRichTextParserTests {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `fallback parser keeps punctuation links newlines and adjacent longest emotes`() {
        val content = json.parseToJsonElement(
            """
            {
              "message":"前[doge_大][doge][doge]\n去链接，未知[猫]",
              "emote":{
                "[doge]":{"url":"//i0.hdslb.com/doge.webp","gif_url":"//i0.hdslb.com/doge.gif","text":"[doge]","meta":{"size":2}},
                "[doge_大]":{"url":"//i0.hdslb.com/doge-big.gif","text":"[doge_大]","meta":{"size":3}}
              },
              "jump_url":{"链接":{"url":"https://www.bilibili.com/video/BV1TEST"}}
            }
            """.trimIndent()
        ) as JsonObject

        val runs = CommentRichTextParser.parse(content)

        assertEquals("前[doge_大][doge][doge]\n去链接，未知[猫]", runs.joinToString("") {
            when (it) {
                is RichTextRun.Text -> it.text
                is RichTextRun.Emote -> it.alt
                is RichTextRun.Resource -> it.label
            }
        })
        val emotes = runs.filterIsInstance<RichTextRun.Emote>()
        assertEquals(listOf("[doge_大]", "[doge]", "[doge]"), emotes.map(RichTextRun.Emote::alt))
        assertTrue(emotes.first().animated)
        assertEquals("https://i0.hdslb.com/doge.gif", emotes[1].url)
        assertEquals(3, emotes.first().width)
        assertEquals(
            "https://www.bilibili.com/video/BV1TEST",
            runs.filterIsInstance<RichTextRun.Text>().first { it.text == "链接" }.linkUrl,
        )
    }

    @Test
    fun `rich text nodes take precedence and keep original order`() {
        val content = json.parseToJsonElement(
            """
            {"message":"不应使用", "rich_text_nodes":[
              {"type":"RICH_TEXT_NODE_TYPE_TEXT","text":"开始"},
              {"type":"RICH_TEXT_NODE_TYPE_EMOJI","orig_text":"[doge]","emoji":{"icon_url":"//i0.hdslb.com/doge.webp","meta":{"size":2}}},
              {"type":"RICH_TEXT_NODE_TYPE_TEXT","text":"链接","jump_url":"https://www.bilibili.com/read/cv1"}
            ]}
            """.trimIndent()
        ) as JsonObject

        val runs = CommentRichTextParser.parse(content)

        assertEquals(3, runs.size)
        assertEquals("开始", assertIs<RichTextRun.Text>(runs[0]).text)
        assertEquals("[doge]", assertIs<RichTextRun.Emote>(runs[1]).alt)
        assertEquals("https://www.bilibili.com/read/cv1", assertIs<RichTextRun.Text>(runs[2]).linkUrl)
    }
}
