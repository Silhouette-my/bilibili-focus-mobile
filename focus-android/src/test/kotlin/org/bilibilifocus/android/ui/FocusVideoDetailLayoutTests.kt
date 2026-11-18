package org.bilibilifocus.android.ui

import org.bilibilifocus.android.ui.video.FocusVideoDetailLayoutPolicy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FocusVideoDetailLayoutTests {
    @Test
    fun `landscape tablet uses fixed video and independently scrollable detail column`() {
        assertTrue(FocusVideoDetailLayoutPolicy.usesSidePanel(1280f, 720f))
        assertTrue(FocusVideoDetailLayoutPolicy.usesSidePanel(960f, 600f))
    }

    @Test
    fun `portrait tablet and phone keep one column`() {
        assertFalse(FocusVideoDetailLayoutPolicy.usesSidePanel(800f, 1200f))
        assertFalse(FocusVideoDetailLayoutPolicy.usesSidePanel(1000f, 1200f))
        assertFalse(FocusVideoDetailLayoutPolicy.usesSidePanel(412f, 800f))
        assertFalse(FocusVideoDetailLayoutPolicy.usesSidePanel(900f, 380f))
    }

    @Test
    fun `narrow or short multiwindow falls back based on actual available space`() {
        assertFalse(FocusVideoDetailLayoutPolicy.usesSidePanel(959f, 600f))
        assertFalse(FocusVideoDetailLayoutPolicy.usesSidePanel(1200f, 399f))
        assertFalse(FocusVideoDetailLayoutPolicy.usesSidePanel(1000f, 900f))
        assertTrue(FocusVideoDetailLayoutPolicy.usesSidePanel(1100f, 700f))
    }

    @Test
    fun `detail column remains readable without consuming an oversized share`() {
        assertEquals(320f, FocusVideoDetailLayoutPolicy.sidePanelWidth(960f))
        assertEquals(384f, FocusVideoDetailLayoutPolicy.sidePanelWidth(1200f))
        assertEquals(420f, FocusVideoDetailLayoutPolicy.sidePanelWidth(1800f))
    }

    @Test
    fun `single column player leaves room for details for landscape and portrait media`() {
        assertEquals(225f, FocusVideoDetailLayoutPolicy.inlinePlayerHeight(400f, 800f, 16f / 9f))
        assertEquals(184f, FocusVideoDetailLayoutPolicy.inlinePlayerHeight(800f, 400f, 16f / 9f))
        assertEquals(592f, FocusVideoDetailLayoutPolicy.inlinePlayerHeight(400f, 800f, 9f / 16f))
        assertEquals(562.5f, FocusVideoDetailLayoutPolicy.inlinePlayerHeight(1000f, 1000f, 16f / 9f))
    }
}
