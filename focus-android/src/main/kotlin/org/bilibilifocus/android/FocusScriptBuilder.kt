package org.bilibilifocus.android

import android.util.Base64
import org.bilibilifocus.core.injection.FocusRuleCatalog
import org.bilibilifocus.core.model.FocusFeature
import org.bilibilifocus.core.model.FocusPageRule
import org.bilibilifocus.core.model.FocusSettings

object FocusScriptBuilder {
    fun buildUserScript(
        url: String,
        settings: FocusSettings = FocusSettings.DEFAULTS,
    ): String? {
        val (host, path) = parseURL(url) ?: return null

        val rules = FocusRuleCatalog.defaultRules.filter { it.match(host, path) }
        if (rules.isEmpty()) return null

        val startRules = rules.filter { it.runPhase == FocusPageRule.RunPhase.DOCUMENT_START }
        val endRules = rules.filter { it.runPhase == FocusPageRule.RunPhase.DOCUMENT_END }

        val startCSS = startRules.flatMap { rule ->
            rule.features.filter { it.isEnabled(settings) }.map { it.css }.filter { it.isNotBlank() }
        }.joinToString("\n")

        val endCSS = endRules.flatMap { rule ->
            rule.features.filter { it.isEnabled(settings) }.map { it.css }.filter { it.isNotBlank() }
        }.joinToString("\n")

        val scripts = endRules.flatMap { rule ->
            rule.features.filter { it.isEnabled(settings) }.mapNotNull { it.script }.filter { it.isNotBlank() }
        }

        val metaViewport = startRules.mapNotNull { it.metaViewport }.lastOrNull()

        return buildString {
            append("(function(){")
            append("var helpers={featureState:{}};")

            if (!metaViewport.isNullOrBlank()) {
                val safeVP = metaViewport.replace("\\", "\\\\").replace("'", "\\'")
                append("var vp=document.querySelector('meta[name=\"viewport\"]');")
                append("if(vp)vp.content='$safeVP';")
                append("else{var m=document.createElement('meta');m.name='viewport';")
                append("m.content='$safeVP';document.head.appendChild(m);}")
            }

            fun injectCSS(css: String) {
                if (css.isBlank()) return
                val encoded = Base64.encodeToString(css.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
                append("var s=document.createElement('style');")
                append("s.textContent=atob('$encoded');")
                append("document.head.appendChild(s);")
            }

            injectCSS(startCSS)
            injectCSS(endCSS)

            scripts.forEach { script ->
                append(script)
                append(";")
            }

            append("})();")
        }.takeIf { it.isNotBlank() }
    }

    private fun FocusFeature.isEnabled(settings: FocusSettings): Boolean = when (settingKey) {
        null -> true
        FocusFeature.SettingKey.REDIRECT_ENABLED -> settings.redirectEnabled
        FocusFeature.SettingKey.PLAYER_MASK_ENABLED -> settings.playerMaskEnabled
        FocusFeature.SettingKey.SEARCH_MASK_ENABLED -> settings.searchMaskEnabled
        FocusFeature.SettingKey.DYNAMIC_MASK_ENABLED -> settings.dynamicMaskEnabled
        FocusFeature.SettingKey.DEBUG_MODE -> settings.debugMode
    }

    private fun parseURL(url: String): Pair<String, String>? {
        val stripped = url.trim()
        if (stripped.isEmpty()) return null

        val noProtocol = stripped.substringAfter("://", stripped)
        val host = noProtocol.substringBefore("/").substringBefore("?")
            .lowercase().removePrefix("www.")
        val path = "/" + noProtocol.substringAfter("/", "").substringBefore("?")

        return host to path
    }
}
