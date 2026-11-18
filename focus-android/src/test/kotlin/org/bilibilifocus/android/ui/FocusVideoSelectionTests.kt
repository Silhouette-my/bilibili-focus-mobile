package org.bilibilifocus.android.ui

import android.content.pm.ActivityInfo
import org.bilibilifocus.android.ui.video.FocusPhysicalOrientation
import org.bilibilifocus.android.ui.video.FocusVideoDeviceType
import org.bilibilifocus.android.ui.video.FocusVideoFullscreenPolicy
import org.bilibilifocus.android.ui.video.FocusVideoRotationPolicy
import org.bilibilifocus.android.ui.video.historyPositionForRequestedPage
import org.bilibilifocus.android.ui.video.currentVideoEpisodeIndex
import org.bilibilifocus.android.ui.video.commentImageGalleryRequest
import org.bilibilifocus.android.ui.video.parseRequestedCid
import org.bilibilifocus.android.ui.video.parseRequestedHistoryPositionMillis
import org.bilibilifocus.android.ui.video.parseRequestedPage
import org.bilibilifocus.android.ui.video.requestedLandscapeOrientation
import org.bilibilifocus.android.ui.video.resolveActivePage
import org.bilibilifocus.android.ui.video.videoEpisodeURL
import org.bilibilifocus.core.model.VideoAuthor
import org.bilibilifocus.core.model.VideoEpisode
import org.bilibilifocus.core.model.VideoInfo
import org.bilibilifocus.core.model.VideoPage
import org.bilibilifocus.core.model.VideoStats
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FocusVideoSelectionTests {
    @Test
    fun `comment gallery keeps clicked comment image index when URLs repeat`() {
        val images = listOf("https://i0.hdslb.com/same.jpg", "https://i0.hdslb.com/other.jpg", "https://i0.hdslb.com/same.jpg")

        val request = commentImageGalleryRequest(
            imageURLs = images,
            imageIndex = 2,
            referer = "https://www.bilibili.com/video/BV1TEST00001",
        )

        assertEquals(images, request.images)
        assertEquals(2, request.initialIndex)
    }

    @Test
    fun `history item link carries its part and saved position`() {
        val item = org.bilibilifocus.core.model.HistoryItem(
            title = "测试视频",
            coverURL = "",
            bvid = "BV1TEST00001",
            cid = 202,
            authorName = "UP",
            viewAt = 1,
            progress = 87,
            duration = 180,
        )
        val url = historyItemVideoURL(item)

        assertEquals(
            "https://www.bilibili.com/video/BV1TEST00001/?cid=202&focus_history_position_ms=87000",
            url,
        )
        assertEquals(202, parseRequestedCid(url))
        assertEquals(87_000, parseRequestedHistoryPositionMillis(url))
        assertEquals(
            null,
            parseRequestedHistoryPositionMillis("https://www.bilibili.com/video/BV1TEST00001/"),
        )
    }

    @Test
    fun `history item uses page when cid is absent and restarts completed items`() {
        val item = org.bilibilifocus.core.model.HistoryItem(
            title = "测试视频",
            coverURL = "",
            bvid = "BV1TEST00001",
            page = 3,
            authorName = "UP",
            viewAt = 1,
            progress = -1,
            duration = 180,
        )

        val url = historyItemVideoURL(item)

        assertEquals(
            "https://www.bilibili.com/video/BV1TEST00001/?p=3&focus_history_position_ms=0",
            url,
        )
        assertEquals(3, parseRequestedPage(url))
        assertEquals(0, parseRequestedHistoryPositionMillis(url))
        assertEquals(
            "https://www.bilibili.com/video/BV1TEST00001/",
            historyItemVideoURL(item.copy(page = 0, progress = 0)),
        )
        assertEquals(
            "https://www.bilibili.com/video/BV1TEST00001/",
            historyItemVideoURL(item.copy(page = 0, progress = 87)),
        )
        assertEquals(
            "https://www.bilibili.com/video/BV1TEST00001/?p=3",
            historyItemVideoURL(item.copy(progress = Long.MAX_VALUE)),
        )
    }

    @Test
    fun `history position is used only for its requested part`() {
        assertEquals(
            87_000,
            historyPositionForRequestedPage(
                positionMillis = 87_000,
                requestedPageNumber = null,
                requestedPageCid = 202,
                activePageNumber = 2,
                activePageCid = 202,
            ),
        )
        assertEquals(
            null,
            historyPositionForRequestedPage(
                positionMillis = 87_000,
                requestedPageNumber = null,
                requestedPageCid = 202,
                activePageNumber = 1,
                activePageCid = 101,
            ),
        )
        assertEquals(
            87_000,
            historyPositionForRequestedPage(
                positionMillis = 87_000,
                requestedPageNumber = 3,
                requestedPageCid = null,
                activePageNumber = 3,
                activePageCid = 303,
            ),
        )
        assertEquals(
            null,
            historyPositionForRequestedPage(
                positionMillis = 87_000,
                requestedPageNumber = null,
                requestedPageCid = null,
                activePageNumber = 1,
                activePageCid = 101,
            ),
        )
    }

    @Test
    fun `server resume selects the last page unless the url explicitly selects one`() {
        val info = videoInfo()

        assertEquals(
            202,
            resolveActivePage(
                info = info,
                selectedCid = null,
                requestedPageNumber = null,
                requestedPageCid = null,
                resumeCid = 202,
            )?.cid,
        )
        assertEquals(
            101,
            resolveActivePage(
                info = info,
                selectedCid = null,
                requestedPageNumber = 1,
                requestedPageCid = null,
                resumeCid = 202,
            )?.cid,
        )
    }

    @Test
    fun `physical rotation keeps clockwise and counterclockwise landscape distinct`() {
        assertEquals(FocusPhysicalOrientation.Portrait, FocusPhysicalOrientation.fromDegrees(0))
        assertEquals(FocusPhysicalOrientation.Portrait, FocusPhysicalOrientation.fromDegrees(359))
        assertEquals(
            FocusPhysicalOrientation.LandscapeClockwise,
            FocusPhysicalOrientation.fromDegrees(90),
        )
        assertEquals(
            FocusPhysicalOrientation.LandscapeCounterClockwise,
            FocusPhysicalOrientation.fromDegrees(270),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            FocusPhysicalOrientation.LandscapeClockwise.requestedLandscapeOrientation(),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FocusPhysicalOrientation.LandscapeCounterClockwise.requestedLandscapeOrientation(),
        )
        assertEquals(null, FocusPhysicalOrientation.fromDegrees(180))
    }

    @Test
    fun `fullscreen orientation follows video dimensions`() {
        assertEquals(
            true,
            FocusVideoFullscreenPolicy.isPortrait(
                FocusVideoFullscreenPolicy.aspectRatio(width = 1080, height = 1920),
            ),
        )
        assertEquals(
            false,
            FocusVideoFullscreenPolicy.isPortrait(
                FocusVideoFullscreenPolicy.aspectRatio(width = 1920, height = 1080),
            ),
        )
        assertEquals(
            true,
            FocusVideoFullscreenPolicy.isPortrait(
                FocusVideoFullscreenPolicy.aspectRatio(width = 1080, height = 1080),
            ),
        )
        assertEquals(
            false,
            FocusVideoFullscreenPolicy.isPortrait(
                FocusVideoFullscreenPolicy.aspectRatio(width = 0, height = 0),
            ),
        )
        assertEquals(
            true,
            FocusVideoFullscreenPolicy.shouldFitToWidth(
                containerAspectRatio = 9f / 19.5f,
                videoAspectRatio = 9f / 16f,
            ),
        )
        assertEquals(
            false,
            FocusVideoFullscreenPolicy.shouldFitToWidth(
                containerAspectRatio = 19.5f / 9f,
                videoAspectRatio = 16f / 9f,
            ),
        )
    }

    @Test
    fun `picture in picture freezes app fullscreen rotation decisions`() {
        assertTrue(
            FocusVideoRotationPolicy.shouldObservePhysicalOrientation(
                isPhone = true,
                isVideoLoaded = true,
                prefersPortraitFullscreen = false,
                isInPictureInPictureMode = false,
            ),
        )
        assertFalse(
            FocusVideoRotationPolicy.shouldObservePhysicalOrientation(
                isPhone = true,
                isVideoLoaded = true,
                prefersPortraitFullscreen = false,
                isInPictureInPictureMode = true,
            ),
        )
        assertFalse(
            FocusVideoRotationPolicy.shouldObservePhysicalOrientation(
                isPhone = true,
                isVideoLoaded = true,
                prefersPortraitFullscreen = false,
                isInPictureInPictureMode = false,
                isInMultiWindowMode = true,
            ),
        )
        assertFalse(
            FocusVideoRotationPolicy.shouldApplyActivityOrientation(
                isInPictureInPictureMode = false,
                isInMultiWindowMode = true,
            ),
        )
        assertTrue(
            FocusVideoRotationPolicy.shouldCompleteFullscreenExit(
                isPhone = true,
                isCompletingFullscreenExit = true,
                configurationOrientation = android.content.res.Configuration.ORIENTATION_LANDSCAPE,
                isInPictureInPictureMode = false,
                isInMultiWindowMode = true,
            ),
        )
        assertFalse(
            FocusVideoRotationPolicy.shouldCompleteFullscreenExit(
                isPhone = true,
                isCompletingFullscreenExit = true,
                configurationOrientation = android.content.res.Configuration.ORIENTATION_PORTRAIT,
                isInPictureInPictureMode = true,
            ),
        )
        assertFalse(FocusVideoRotationPolicy.shouldApplyActivityOrientation(true))
        assertTrue(FocusVideoRotationPolicy.shouldApplyActivityOrientation(false))
    }

    @Test
    fun `multiwindow return ignores the listener snapshot then accepts the next rotation`() {
        var ignoreInitialOrientation = false

        // Entering the Xiaomi-style app window arms a one-shot ignore that survives exit.
        if (FocusVideoRotationPolicy.shouldArmInitialOrientationIgnore(
                isInPictureInPictureMode = false,
                isInMultiWindowMode = true,
            )
        ) {
            ignoreInitialOrientation = true
        }
        // Returning to the full window re-enables the listener; its first landscape report
        // is only the current posture, not a new rotate gesture.
        assertTrue(
            FocusVideoRotationPolicy.shouldIgnoreInitialOrientationEvent(
                isInitialOrientation = true,
                ignoreInitialOrientation = ignoreInitialOrientation,
                orientation = FocusPhysicalOrientation.LandscapeClockwise,
            ),
        )
        ignoreInitialOrientation = false // onInitialOrientationConsumed
        assertFalse(
            FocusVideoRotationPolicy.shouldIgnoreInitialOrientationEvent(
                isInitialOrientation = false,
                ignoreInitialOrientation = ignoreInitialOrientation,
                orientation = FocusPhysicalOrientation.LandscapeClockwise,
            ),
        )
    }

    @Test
    fun `fullscreen exit completes in multiwindow even when it expands past tablet breakpoint`() {
        val phoneWidthType = FocusVideoDeviceType.fromSmallestWidth(599)
        val expandedWindowType = FocusVideoDeviceType.fromSmallestWidth(600)

        assertTrue(
            FocusVideoRotationPolicy.shouldCompleteFullscreenExit(
                isPhone = phoneWidthType == FocusVideoDeviceType.Phone,
                isCompletingFullscreenExit = true,
                configurationOrientation = android.content.res.Configuration.ORIENTATION_LANDSCAPE,
                isInPictureInPictureMode = false,
                isInMultiWindowMode = true,
            ),
        )
        assertTrue(
            FocusVideoRotationPolicy.shouldCompleteFullscreenExit(
                isPhone = expandedWindowType == FocusVideoDeviceType.Phone,
                isCompletingFullscreenExit = true,
                configurationOrientation = android.content.res.Configuration.ORIENTATION_LANDSCAPE,
                isInPictureInPictureMode = false,
                isInMultiWindowMode = true,
            ),
        )
        assertFalse(
            FocusVideoRotationPolicy.shouldCompleteFullscreenExit(
                isPhone = false,
                isCompletingFullscreenExit = true,
                configurationOrientation = android.content.res.Configuration.ORIENTATION_LANDSCAPE,
                isInPictureInPictureMode = false,
                isInMultiWindowMode = false,
            ),
        )
    }

    @Test
    fun `current episode remains resolvable in a long selection list`() {
        val episodes = (1..120).map { index ->
            VideoEpisode(
                bvid = "BV${index.toString().padStart(10, '0')}",
                aid = index.toLong(),
                cid = (10_000 + index).toLong(),
                title = "第 $index 集",
            )
        }

        assertEquals(86, currentVideoEpisodeIndex(episodes, "BV0000000087", 10_087))
        assertEquals(86, currentVideoEpisodeIndex(episodes, "bv0000000087", 10_087))
        assertEquals(-1, currentVideoEpisodeIndex(episodes, "BV9999999999"))

        val repeatedBvidEpisodes = episodes.toMutableList().apply {
            this[86] = this[86].copy(bvid = "BVREPEATED01", cid = 20_087)
            this[87] = this[87].copy(bvid = "BVREPEATED01", cid = 3_000_000_088)
        }
        assertEquals(
            87,
            currentVideoEpisodeIndex(repeatedBvidEpisodes, "bvrepeated01", 3_000_000_088),
        )
        assertEquals(
            "https://www.bilibili.com/video/BVREPEATED01/?cid=3000000088",
            videoEpisodeURL(repeatedBvidEpisodes[87]),
        )
        assertEquals(
            3_000_000_088,
            parseRequestedCid(videoEpisodeURL(repeatedBvidEpisodes[87])),
        )
    }

    private fun videoInfo() = VideoInfo(
        bvid = "BV1TEST00001",
        aid = 42,
        cid = 101,
        title = "测试视频",
        description = "",
        coverURL = "",
        duration = 180,
        publishDate = 0,
        author = VideoAuthor(name = "测试UP", mid = 7, avatarURL = ""),
        stats = VideoStats(
            views = 0,
            likes = 0,
            coins = 0,
            favorites = 0,
            shares = 0,
            danmaku = 0,
            comments = 0,
        ),
        pages = listOf(
            VideoPage(pageNumber = 1, cid = 101, title = "P1", duration = 90),
            VideoPage(pageNumber = 2, cid = 202, title = "P2", duration = 90),
        ),
        lastPlaybackCid = 202,
        lastPlaybackPositionMillis = 87_000,
    )
}
