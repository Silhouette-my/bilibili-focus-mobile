package org.bilibilifocus.android.ui

import android.content.pm.ActivityInfo
import org.bilibilifocus.core.model.VideoEpisode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FocusVideoSelectionTests {
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
}
