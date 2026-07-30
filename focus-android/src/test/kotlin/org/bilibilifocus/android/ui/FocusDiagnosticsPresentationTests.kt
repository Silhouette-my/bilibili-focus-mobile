package org.bilibilifocus.android.ui

import org.bilibilifocus.core.service.BiliDiagnosticEvent
import org.bilibilifocus.core.service.LoginHealth
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class FocusDiagnosticsPresentationTests {
    @Test
    fun `every finite login health state has a stable label`() {
        val labels = LoginHealth.entries.associateWith(::diagnosticHealthLabel)

        assertEquals(LoginHealth.entries.size, labels.size)
        assertFalse(labels.values.any(String::isBlank))
    }

    @Test
    fun `defense in depth removes query and fragment from displayed target`() {
        assertEquals(
            "https://api.bilibili.com/x/web-interface/nav",
            safeDiagnosticTarget(
                "https://api.bilibili.com/x/web-interface/nav?keyword=secret#private",
            ),
        )
    }

    @Test
    fun `event metadata only uses bounded diagnostic fields`() {
        val metadata = diagnosticEventMetadata(
            BiliDiagnosticEvent(
                method = "GET",
                target = "https://api.bilibili.com/x/web-interface/nav",
                statusCode = null,
                durationMilliseconds = 42,
                responseBytes = 128,
                failureType = "network_unavailable",
            ),
        )

        assertEquals("42 ms · 128 B · 网络不可用", metadata)
        assertFalse(metadata.contains("secret"))
    }
}
