package org.bilibilifocus.android.images

import coil.size.Scale
import org.bilibilifocus.core.model.DynamicCard
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class FocusDynamicImageRequestsTests {
    private val layout = FocusDynamicImageLayout(contentWidth = 900, avatarSize = 132, imageGap = 24)

    @Test
    fun matchesVisibleCardDimensionsAndScaleForEachCoverLayout() {
        val video = card("video", DynamicCard.Kind.VIDEO, covers = listOf("http://i0.hdslb.com/bfs/archive/video.jpg"))
        val photo = card("photo", DynamicCard.Kind.IMAGE, covers = listOf("https://i0.hdslb.com/bfs/new_dyn/photo.png"))
        val album = card("album", covers = listOf("https://i0.hdslb.com/bfs/new_dyn/1.jpg", "https://i0.hdslb.com/bfs/new_dyn/2.jpg"))
        assertEquals(FocusDynamicImageRequest("https://i0.hdslb.com/bfs/archive/video.jpg", 900, 506, Scale.FILL), layout.cover(video, video.coverURLs.single()))
        assertEquals(675, layout.cover(photo, photo.coverURLs.single()).height)
        assertEquals(Scale.FIT, layout.cover(photo, photo.coverURLs.single()).scale)
        assertEquals(438, layout.cover(album, album.coverURLs.first()).width)
        assertEquals(438, layout.cover(album, album.coverURLs.first()).height)
        assertEquals(Scale.FILL, layout.cover(album, album.coverURLs.first()).scale)
        val prefetched = layout.prefetchRequests(listOf(video, photo, album), null)
        listOf(video, photo, album).forEach { item ->
            item.coverURLs.forEach { assertTrue(layout.cover(item, it) in prefetched) }
        }
        assertEquals("https://i0.hdslb.com/bfs/archive/video.jpg@1024w_1024h_0e.webp", FocusImageCDNRequest.thumbnailURL(prefetched.first { it.source == "https://i0.hdslb.com/bfs/archive/video.jpg" }.source, 900))
    }

    @Test
    fun followsReadingPositionWithinEightCardsAndOnlyTwoCoversEach() {
        val cards = (0 until 20).map { card(it.toString()) }
        val requests = layout.prefetchRequests(cards, "5")
        assertEquals(24, requests.size)
        assertEquals((5..12).map { "https://i0.hdslb.com/bfs/face/$it.jpg" }, requests.filter { it.width == 132 }.map { it.source })
        assertTrue(requests.none { it.source.endsWith("-2.jpg") })
        assertEquals(layout.prefetchRequests(cards, null), layout.prefetchRequests(cards, "removed-card"))
    }

    @Test
    fun deduplicatesCanonicalEquivalentSourcesWithoutMergingDifferentDecodeSizes() {
        val a = card("a").copy(author = DynamicCard.Author("a", avatarURL = "http://i0.hdslb.com/bfs/face/shared.jpg"))
        val b = card("b").copy(author = DynamicCard.Author("b", avatarURL = "https://i0.hdslb.com/bfs/face/shared.jpg"))
        val requests = layout.prefetchRequests(listOf(a, b), null)
        assertEquals(1, requests.count { it.source.endsWith("shared.jpg") })
        val sameSourceAsCover = a.copy(coverURLs = listOf("https://i0.hdslb.com/bfs/face/shared.jpg"))
        assertEquals(2, layout.prefetchRequests(listOf(sameSourceAsCover), null).count { it.source.endsWith("shared.jpg") })
    }

    private fun card(id: String, kind: DynamicCard.Kind = DynamicCard.Kind.IMAGE, covers: List<String> = (0..2).map { "https://i0.hdslb.com/bfs/new_dyn/$id-$it.jpg" }) = DynamicCard(
        id, kind, DynamicCard.Author(id, avatarURL = "https://i0.hdslb.com/bfs/face/$id.jpg"), "", "", covers, "https://t.bilibili.com/$id",
    )
}
