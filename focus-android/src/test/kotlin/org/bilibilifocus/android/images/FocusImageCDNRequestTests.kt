package org.bilibilifocus.android.images

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FocusImageCDNRequestTests {
    @Test
    fun upgradesKnownHTTPImagesWithoutChangingSignedPathOrQuery() {
        assertEquals(
            "https://i2.hdslb.com/bfs/archive/a.jpg@100w.webp?signature=a%2Fb&v=1#part",
            FocusImageCDNRequest.canonicalURL("http://i2.hdslb.com/bfs/archive/a.jpg@100w.webp?signature=a%2Fb&v=1#part"),
        )
        assertEquals("https://i0.hdslb.com/bfs/new_dyn/a.gif", FocusImageCDNRequest.canonicalURL("//i0.hdslb.com/bfs/new_dyn/a.gif"))
        assertEquals(
            "https://i2.hdslb.com/bfs/archive/cover.jpg@768w_768h_0e.webp",
            FocusImageCDNRequest.thumbnailURL(FocusImageCDNRequest.canonicalURL("http://i2.hdslb.com/bfs/archive/cover.jpg"), 600),
        )
        listOf(
            "http://other.test/bfs/archive/a.jpg", "http://i0.hdslb.com.evil.test/a.jpg",
            "http://user@i0.hdslb.com/a.jpg", "http://i0.hdslb.com:80/a.jpg", "invalid image URL",
        ).forEach { assertEquals(it, FocusImageCDNRequest.canonicalURL(it)) }
    }

    @Test
    fun usesSameStableBucketsAndNonCroppingTransformAsIOS() {
        assertEquals(
            "https://i0.hdslb.com/bfs/archive/cover.jpg@384w_384h_0e.webp",
            FocusImageCDNRequest.thumbnailURL("https://i0.hdslb.com/bfs/archive/cover.jpg", 300),
        )
        assertEquals(
            "https://i1.hdslb.com/bfs/new_dyn/long.png@768w_768h_0e.webp",
            FocusImageCDNRequest.thumbnailURL("https://i1.hdslb.com/bfs/new_dyn/long.png@100w.webp", 768),
        )
        assertEquals(
            "https://i0.hdslb.com/bfs/face/a.jpg@4096w_4096h_0e.webp",
            FocusImageCDNRequest.thumbnailURL("https://i0.hdslb.com/bfs/face/a.jpg", 8_000),
        )
    }

    @Test
    fun leavesSignedAnimatedAndUnknownSourcesUnchanged() {
        listOf(
            "https://i0.hdslb.com/bfs/archive/cover.jpg?token=secret",
            "https://i0.hdslb.com/bfs/archive/cover.jpg#fragment",
            "https://i0.hdslb.com.evil.test/bfs/archive/cover.jpg",
            "https://other.test/bfs/archive/cover.jpg",
            "https://i0.hdslb.com/bfs/emote/emote.png",
            "https://i0.hdslb.com/bfs/new_dyn/animation.gif",
            "https://i0.hdslb.com/bfs/new_dyn/animation.apng",
            "https://user@i0.hdslb.com/bfs/face/avatar.jpg",
            "https://i0.hdslb.com:444/bfs/face/avatar.jpg",
            "not an image URL",
        ).forEach { source -> assertNull(FocusImageCDNRequest.thumbnailURL(source, 128), source) }
    }
}
