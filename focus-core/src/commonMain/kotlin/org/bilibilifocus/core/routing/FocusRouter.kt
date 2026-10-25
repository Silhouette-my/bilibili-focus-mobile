package org.bilibilifocus.core.routing

import org.bilibilifocus.core.model.FocusEntry
import org.bilibilifocus.core.model.FocusSettings

class FocusRouter(private val settings: FocusSettings = FocusSettings.DEFAULTS) {

    constructor(
        redirectEnabled: Boolean,
        defaultEntry: FocusEntry,
    ) : this(
        FocusSettings(
            redirectEnabled = redirectEnabled,
            defaultEntry = defaultEntry,
        )
    )

    sealed interface Decision {
        data object Allow : Decision
        data class Redirect(val entry: FocusEntry) : Decision
    }

    fun entry(entry: FocusEntry? = null): FocusEntry = entry ?: settings.defaultEntry

    fun entryRoute(entry: FocusEntry? = null): AppRoute {
        return when (this.entry(entry)) {
            FocusEntry.DYNAMIC, FocusEntry.SEARCH -> AppRoute.DynamicFeed
        }
    }

    fun decision(url: String): Decision {
        if (!settings.redirectEnabled) {
            return Decision.Allow
        }

        val parsed = BiliUrl.parse(url)
        val host = parsed.host ?: return Decision.Allow

        if (host !in homepageHosts) return Decision.Allow
        if (parsed.path !in homepagePaths) return Decision.Allow

        return Decision.Redirect(entry())
    }

    fun redirectTarget(url: String): FocusEntry? {
        return when (val decision = decision(url)) {
            is Decision.Redirect -> decision.entry
            else -> null
        }
    }

    companion object {
        private val homepageHosts = setOf("bilibili.com", "www.bilibili.com", "m.bilibili.com")
        private val homepagePaths = setOf("", "/", "/index.html")
    }
}
