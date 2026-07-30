package org.bilibilifocus.android.playback

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class FocusPlaybackMediaRequestPolicyTests {
    @Test
    fun `media request headers retain referer without forwarding cookies`() {
        val headers = FocusPlaybackMediaRequestPolicy.headers(
            "https://www.bilibili.com/video/BV1xx411c7mD/",
        )

        assertEquals(
            "https://www.bilibili.com/video/BV1xx411c7mD/",
            headers["Referer"],
        )
        assertFalse(headers.keys.any { it.equals("Cookie", ignoreCase = true) })
    }
}
