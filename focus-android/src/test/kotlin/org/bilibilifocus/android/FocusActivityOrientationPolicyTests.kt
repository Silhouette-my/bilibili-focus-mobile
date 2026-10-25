package org.bilibilifocus.android

import android.content.pm.ActivityInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FocusActivityOrientationPolicyTests {
    @Test
    fun `phones default to portrait while tablets keep system orientation`() {
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT,
            FocusActivityOrientationPolicy.defaultOrientation(smallestScreenWidthDp = 599),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED,
            FocusActivityOrientationPolicy.defaultOrientation(smallestScreenWidthDp = 600),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED,
            FocusActivityOrientationPolicy.defaultOrientation(
                smallestScreenWidthDp = 480,
                isInMultiWindowMode = true,
            ),
        )
    }

    @Test
    fun `multiwindow callback does not change orientation while in PiP`() {
        assertFalse(FocusActivityOrientationPolicy.shouldApplyMultiWindowCallbackOrientation(true))
        assertTrue(FocusActivityOrientationPolicy.shouldApplyMultiWindowCallbackOrientation(false))
    }
}
