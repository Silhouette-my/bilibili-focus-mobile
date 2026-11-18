package org.bilibilifocus.android.ui.video

import kotlin.test.Test
import kotlin.test.assertEquals

class FocusVideoSeekBarTest {
    @Test fun seekFractionClamps() {
        assertEquals(0f, seekFraction(-5f, 100f))
        assertEquals(0.5f, seekFraction(50f, 100f))
        assertEquals(1f, seekFraction(500f, 100f))
        assertEquals(0f, seekFraction(10f, 0f))
    }

    @Test fun fractionOfHandlesUnknownDuration() {
        assertEquals(0f, fractionOf(10, 0))
        assertEquals(0.25f, fractionOf(25, 100))
        assertEquals(1f, fractionOf(200, 100))
    }
}
