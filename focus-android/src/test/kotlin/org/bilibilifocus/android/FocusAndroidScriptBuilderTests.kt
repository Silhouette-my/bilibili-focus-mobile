package org.bilibilifocus.android

import org.bilibilifocus.core.injection.FocusRuleCatalog
import org.bilibilifocus.core.injection.FocusScriptBuilder as CoreScriptBuilder
import org.bilibilifocus.core.model.FocusPageRule
import org.bilibilifocus.core.model.FocusSettings
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FocusAndroidScriptBuilderTests {
    @Test
    fun `android uses the complete shared runtime for both injection phases`() {
        val settings = FocusSettings.DEFAULTS.copy(debugMode = true)
        val rules = FocusRuleCatalog.defaultRules.filter { it.match("search.bilibili.com", "/all") }
        val expected = listOf(FocusPageRule.RunPhase.DOCUMENT_START, FocusPageRule.RunPhase.DOCUMENT_END)
            .joinToString("\n") { CoreScriptBuilder.makeUserScript(it, settings, rules) }
        assertEquals(expected, FocusScriptBuilder.buildUserScript("https://search.bilibili.com/all?keyword=test", settings))
    }

    @Test
    fun `unmatched or malformed URLs have no injection`() {
        assertNull(FocusScriptBuilder.buildUserScript("https://example.com/"))
        assertNull(FocusScriptBuilder.buildUserScript("not a URL"))
    }
}
