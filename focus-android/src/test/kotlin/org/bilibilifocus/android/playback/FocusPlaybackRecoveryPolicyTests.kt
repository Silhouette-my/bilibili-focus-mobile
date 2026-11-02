package org.bilibilifocus.android.playback

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FocusPlaybackRecoveryPolicyTests {
    @Test fun `network recovery is bounded and decoder failures are terminal`() {
        assertTrue(FocusPlaybackRecoveryPolicy.canRecover(2001, 0))
        assertTrue(FocusPlaybackRecoveryPolicy.canRecover(2004, 1))
        assertFalse(FocusPlaybackRecoveryPolicy.canRecover(2001, 2))
        assertFalse(FocusPlaybackRecoveryPolicy.canRecover(4001, 0))
        assertFalse(FocusPlaybackRecoveryPolicy.canRecover(6004, 0))
    }

    @Test fun `automatic recovery lowers quality only after the first attempt`() {
        assertEquals(80, FocusPlaybackRecoveryPolicy.qualityForRecovery(null, 80, listOf(80, 64, 32), 1))
        assertEquals(64, FocusPlaybackRecoveryPolicy.qualityForRecovery(null, 80, listOf(80, 64, 32), 2))
        assertEquals(32, FocusPlaybackRecoveryPolicy.qualityForRecovery(null, 64, listOf(80, 64, 32), 2))
        assertEquals(32, FocusPlaybackRecoveryPolicy.qualityForRecovery(null, 32, listOf(32), 2))
    }

    @Test fun `manual quality is never silently lowered`() {
        assertEquals(120, FocusPlaybackRecoveryPolicy.qualityForRecovery(120, 80, listOf(80, 64, 32), 2))
    }
}
