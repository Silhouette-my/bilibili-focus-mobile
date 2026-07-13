package org.bilibilifocus.android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.bilibilifocus.android.playback.FocusPlaybackHistoryPolicy
import org.bilibilifocus.android.playback.FocusPlaybackLoadPolicy

class FocusPictureInPicturePolicyTests {
    @Test
    fun entersOnlyForConnectedActivePlayingVideo() {
        assertTrue(FocusPictureInPicturePolicy.shouldEnter(true, true, true))
        assertFalse(FocusPictureInPicturePolicy.shouldEnter(false, true, true))
        assertFalse(FocusPictureInPicturePolicy.shouldEnter(true, false, true))
        assertFalse(FocusPictureInPicturePolicy.shouldEnter(true, true, false))
    }

    @Test
    fun normalizesAspectRatioToAndroidPipLimits() {
        assertEquals(16f / 9f, FocusPictureInPicturePolicy.normalizedAspectRatio(Float.NaN))
        assertEquals(2.39f, FocusPictureInPicturePolicy.normalizedAspectRatio(4f))
        assertEquals(1f / 2.39f, FocusPictureInPicturePolicy.normalizedAspectRatio(0.2f))
        assertEquals(9f / 16f, FocusPictureInPicturePolicy.normalizedAspectRatio(9f / 16f))
    }

    @Test
    fun rendersOnlyTheDedicatedPlayerSurfaceWhileInPictureInPicture() {
        assertTrue(FocusPictureInPicturePolicy.shouldRenderEmbeddedPlayerSurface(false))
        assertFalse(FocusPictureInPicturePolicy.shouldRenderEmbeddedPlayerSurface(true))
    }

    @Test
    fun keepsPlaybackForApplicationBackgroundButStopsForVideoRouteDeparture() {
        assertFalse(
            FocusPlaybackRoutePolicy.shouldStop(
                isLeavingVideoRoute = false,
                isApplicationBackgrounding = true,
            ),
        )
        assertTrue(
            FocusPlaybackRoutePolicy.shouldStop(
                isLeavingVideoRoute = true,
                isApplicationBackgrounding = false,
            ),
        )
    }

    @Test
    fun ignoresSupersededPlaybackAddressResultsEvenForSameMedia() {
        assertTrue(FocusPlaybackLoadPolicy.shouldApply(2, 2, "BV1:1", "BV1:1"))
        assertFalse(FocusPlaybackLoadPolicy.shouldApply(1, 2, "BV1:1", "BV1:1"))
        assertFalse(FocusPlaybackLoadPolicy.shouldApply(2, 2, "BV1:1", "BV1:2"))
    }

    @Test
    fun reportsHistoryPeriodicallyAndAlwaysReportsChangedFinalPosition() {
        assertTrue(FocusPlaybackHistoryPolicy.shouldReport(0, -1, force = false))
        assertFalse(FocusPlaybackHistoryPolicy.shouldReport(10, 0, force = false))
        assertTrue(FocusPlaybackHistoryPolicy.shouldReport(15, 0, force = false))
        assertTrue(FocusPlaybackHistoryPolicy.shouldReport(10, 0, force = true))
        assertFalse(FocusPlaybackHistoryPolicy.shouldReport(10, 10, force = true))
    }
}
