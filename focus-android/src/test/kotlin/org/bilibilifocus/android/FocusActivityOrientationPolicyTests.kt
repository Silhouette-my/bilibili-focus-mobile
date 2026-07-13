package org.bilibilifocus.android

import android.content.pm.ActivityInfo
import kotlin.test.Test
import kotlin.test.assertEquals

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
    }
}
