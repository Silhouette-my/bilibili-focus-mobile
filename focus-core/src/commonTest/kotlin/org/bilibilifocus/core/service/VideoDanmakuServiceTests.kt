package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.VideoDanmakuMode
import org.bilibilifocus.core.model.VideoDanmakuSegmentScheduler
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class VideoDanmakuServiceTests {
    @Test
    fun `unknown length delimited fields skip to next tag and reject truncation`() {
        val reader = ProtobufReader(ProtoBuilder()
            .bytes(99, ByteArray(64 * 1024))
            .varint(8, 42)
            .build())
        reader.skip(reader.readTag()!!)
        assertEquals(ProtobufTag(8, 0), reader.readTag())
        assertEquals(42L, reader.readVarint())
        assertFalse(reader.hasRemaining)

        val truncated = ProtobufReader(byteArrayOf(0x0a, 0x04, 0x01))
        assertFailsWith<ProtobufDecodingException> { truncated.skip(truncated.readTag()!!) }
    }

    @Test
    fun `view and segment decoders handle supported modes and unknown fields`() {
        val view = VideoDanmakuDecoder.decodeView(viewFixture())
        val segment = VideoDanmakuDecoder.decodeSegment(segmentFixture())

        assertEquals(360_000L, view.segmentDurationMillis)
        assertEquals(2, view.totalSegments)
        assertEquals(3L, view.count)
        assertFalse(view.isClosed)
        assertEquals(
            listOf(VideoDanmakuMode.SCROLLING, VideoDanmakuMode.TOP, VideoDanmakuMode.BOTTOM),
            segment.danmakus.map { it.mode },
        )
        assertEquals("第一条弹幕", segment.danmakus.first().content)
        assertEquals(0xff3366, segment.danmakus.first().colorRgb)
        assertNull(segment.danmakus[1].colorRgb)
        assertEquals(listOf(20, 10, 1), segment.danmakus.map { it.weight })
    }

    @Test
    fun `closed marker and truncated protobuf are handled explicitly`() {
        assertTrue(VideoDanmakuDecoder.decodeSegment(byteArrayOf(0x10, 0x01)).isClosed)
        assertFailsWith<ProtobufDecodingException> {
            VideoDanmakuDecoder.decodeSegment(byteArrayOf(0x0a, 0x05, 0x08))
        }
    }

    @Test
    fun `view keeps a positive server segment duration below the fallback`() {
        val view = VideoDanmakuDecoder.decodeView(viewFixture(segmentDurationMillis = 60_000))

        assertEquals(60_000L, view.segmentDurationMillis)
    }

    @Test
    fun `segment scheduler prefetches only inside boundary and respects total`() {
        assertEquals(
            listOf(1),
            VideoDanmakuSegmentScheduler.segmentIndexes(329_999, 360_000, 3),
        )
        assertEquals(
            listOf(1, 2),
            VideoDanmakuSegmentScheduler.segmentIndexes(330_000, 360_000, 3),
        )
        assertEquals(
            listOf(2),
            VideoDanmakuSegmentScheduler.segmentIndexes(360_000, 360_000, 3),
        )
        assertEquals(
            listOf(1),
            VideoDanmakuSegmentScheduler.segmentIndexes(350_000, 360_000, 1),
        )
        assertEquals(
            listOf(1, 2),
            VideoDanmakuSegmentScheduler.segmentIndexes(330_000, 0, 3),
        )
    }

    @Test
    fun `service signs segments refreshes rejected wbi and carries cookies`() = runTest {
        val http = DanmakuFixtureHttpClient()
        val service = VideoInfoService(
            cookieProvider = object : CookieProvider {
                override suspend fun loadCookies(): List<Cookie> = listOf(
                    Cookie("SESSDATA", "fixture-session", ".bilibili.com")
                )
            },
            httpClient = http,
        )

        val view = service.fetchDanmakuView(aid = 42, cid = 4201)
        val segment = service.fetchDanmakuSegment(aid = 42, cid = 4201, segmentIndex = 2)

        assertEquals(2, view.totalSegments)
        assertEquals(3, segment.danmakus.size)
        assertEquals(2, http.navRequests)
        assertEquals(2, http.segmentRequests)
        val segmentUrl = http.requestedUrls.last { "/seg.so" in it }
        assertTrue("oid=4201" in segmentUrl)
        assertTrue("pid=42" in segmentUrl)
        assertTrue("segment_index=2" in segmentUrl)
        assertTrue("web_location=1550101" in segmentUrl)
        assertTrue("wts=" in segmentUrl)
        assertTrue("w_rid=" in segmentUrl)
        assertTrue(http.lastHeaders["Cookie"]?.contains("SESSDATA=fixture-session") == true)
        assertEquals("https://www.bilibili.com/", http.lastHeaders["Referer"])
    }

    private class DanmakuFixtureHttpClient : HttpClient {
        var navRequests = 0
        var segmentRequests = 0
        val requestedUrls = mutableListOf<String>()
        var lastHeaders: Map<String, String> = emptyMap()

        override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
            requestedUrls += url
            lastHeaders = headers
            if (url.contains("/x/web-interface/nav")) {
                navRequests += 1
                return HttpResponse(
                    200,
                    """{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png","sub_url":"https://i0.hdslb.com/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png"}}}""",
                )
            }
            error("Unexpected text request: $url")
        }

        override suspend fun getBytes(url: String, headers: Map<String, String>): BinaryHttpResponse {
            requestedUrls += url
            lastHeaders = headers
            return when {
                url.contains("/x/v2/dm/web/view") -> BinaryHttpResponse(200, viewFixture())
                url.contains("/x/v2/dm/wbi/web/seg.so") -> {
                    segmentRequests += 1
                    if (segmentRequests == 1) {
                        BinaryHttpResponse(200, " \n {\"code\":-403,\"message\":\"expired\"}".encodeToByteArray())
                    } else {
                        BinaryHttpResponse(200, segmentFixture())
                    }
                }
                else -> error("Unexpected binary request: $url")
            }
        }

        override suspend fun post(
            url: String,
            body: String,
            headers: Map<String, String>,
        ): HttpResponse = error("Unexpected POST: $url")
    }

    companion object {
        private fun viewFixture(segmentDurationMillis: Long = 360_000): ByteArray {
            val segment = ProtoBuilder()
                .varint(1, segmentDurationMillis)
                .varint(2, 2)
                .build()
            return ProtoBuilder()
                .varint(1, 0)
                .bytes(4, segment)
                .varint(8, 3)
                .bytes(99, byteArrayOf(1, 2, 3))
                .fixed32(98, 0x12345678)
                .fixed64(97, 0x123456789abcdef0)
                .build()
        }

        private fun segmentFixture(): ByteArray = ProtoBuilder()
            .bytes(1, danmakuElement(1, 1_000, 1, 25, 0xff3366, "第一条弹幕", 20))
            .bytes(1, danmakuElement(2, 2_000, 5, 36, 60_001, "顶部", 10))
            .bytes(1, danmakuElement(3, 3_000, 4, 18, 0xffffff, "底部", 1))
            .bytes(1, danmakuElement(4, 4_000, 7, 25, 0xffffff, "高级弹幕", 99))
            .build()

        private fun danmakuElement(
            id: Long,
            progress: Long,
            mode: Long,
            fontSize: Long,
            color: Long,
            content: String,
            weight: Long,
        ): ByteArray = ProtoBuilder()
            .varint(1, id)
            .varint(2, progress)
            .varint(3, mode)
            .varint(4, fontSize)
            .varint(5, color)
            .bytes(7, content.encodeToByteArray())
            .varint(9, weight)
            .varint(11, 0)
            .bytes(30, byteArrayOf(9, 8, 7))
            .build()
    }
}

private class ProtoBuilder {
    private val bytes = mutableListOf<Byte>()

    fun varint(field: Int, value: Long): ProtoBuilder = apply {
        appendVarint((field.toLong() shl 3) or 0)
        appendVarint(value)
    }

    fun bytes(field: Int, value: ByteArray): ProtoBuilder = apply {
        appendVarint((field.toLong() shl 3) or 2)
        appendVarint(value.size.toLong())
        bytes.addAll(value.toList())
    }

    fun fixed32(field: Int, value: Int): ProtoBuilder = apply {
        appendVarint((field.toLong() shl 3) or 5)
        repeat(4) { shift -> bytes += (value ushr (shift * 8)).toByte() }
    }

    fun fixed64(field: Int, value: Long): ProtoBuilder = apply {
        appendVarint((field.toLong() shl 3) or 1)
        repeat(8) { shift -> bytes += (value ushr (shift * 8)).toByte() }
    }

    fun build(): ByteArray = bytes.toByteArray()

    private fun appendVarint(rawValue: Long) {
        var value = rawValue
        while (true) {
            if (value and 0x7f.inv().toLong() == 0L) {
                bytes += value.toByte()
                return
            }
            bytes += ((value and 0x7f) or 0x80).toByte()
            value = value ushr 7
        }
    }
}
