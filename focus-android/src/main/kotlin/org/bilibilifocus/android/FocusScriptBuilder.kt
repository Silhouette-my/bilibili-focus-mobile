package org.bilibilifocus.android

import java.net.URI
import org.bilibilifocus.core.injection.FocusRuleCatalog
import org.bilibilifocus.core.injection.FocusScriptBuilder as CoreScriptBuilder
import org.bilibilifocus.core.model.FocusPageRule
import org.bilibilifocus.core.model.FocusSettings

/** Adapts the shared runtime to the WebView's existing single injection hook. */
object FocusScriptBuilder {
    fun buildUserScript(
        url: String,
        settings: FocusSettings = FocusSettings.DEFAULTS,
    ): String? {
        val uri = runCatching { URI(url.trim()) }.getOrNull() ?: return null
        val host = uri.host?.lowercase() ?: return null
        val rules = FocusRuleCatalog.defaultRules.filter { it.match(host, uri.path.orEmpty()) }
        if (rules.isEmpty()) return null
        // Keep onPageFinished timing while sharing helpers, feature isolation
        // and mutation/navigation observers rather than concatenating scripts.
        return listOf(FocusPageRule.RunPhase.DOCUMENT_START, FocusPageRule.RunPhase.DOCUMENT_END)
            .joinToString("\n") { phase -> CoreScriptBuilder.makeUserScript(phase, settings, rules) }
    }
}
