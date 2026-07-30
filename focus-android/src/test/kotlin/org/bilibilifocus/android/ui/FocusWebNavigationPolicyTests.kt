package org.bilibilifocus.android.ui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

class FocusWebNavigationPolicyTests {
    @Test
    fun `https bilibili pages stay inside the webview`() {
        assertEquals(
            FocusWebNavigationDecision.Internal("https://www.bilibili.com/video/BV1TEST00001/"),
            FocusWebNavigationPolicy.decide("https://www.bilibili.com/video/BV1TEST00001/"),
        )
        assertTrue(
            FocusWebNavigationPolicy.shouldInjectBilibiliScripts(
                "https://space.bilibili.com/42",
            ),
        )
    }

    @Test
    fun `http bilibili links are upgraded before loading`() {
        assertEquals(
            FocusWebNavigationDecision.Internal("https://www.bilibili.com/video/BV1TEST00001/"),
            FocusWebNavigationPolicy.decide("http://www.bilibili.com/video/BV1TEST00001/"),
        )
        assertFalse(
            FocusWebNavigationPolicy.shouldInjectBilibiliScripts(
                "http://www.bilibili.com/video/BV1TEST00001/",
            ),
        )
    }

    @Test
    fun `external web links leave the embedded webview and custom schemes are blocked`() {
        assertEquals(
            FocusWebNavigationDecision.External("https://example.com/article"),
            FocusWebNavigationPolicy.decide("https://example.com/article"),
        )
        assertIs<FocusWebNavigationDecision.Blocked>(
            FocusWebNavigationPolicy.decide("javascript:alert(1)"),
        )
        assertIs<FocusWebNavigationDecision.Blocked>(
            FocusWebNavigationPolicy.decide("https://www.bilibili.com:8443/"),
        )
    }
}
