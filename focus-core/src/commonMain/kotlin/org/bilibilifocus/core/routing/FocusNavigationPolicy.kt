package org.bilibilifocus.core.routing

import org.bilibilifocus.core.model.FocusSettings

class FocusNavigationPolicy(settings: FocusSettings = FocusSettings.DEFAULTS) {

    sealed interface Decision {
        data object Allow : Decision
        data object Cancel : Decision
        data class Redirect(val url: String) : Decision
    }

    fun decision(url: String, currentURL: String? = null): Decision {
        val canonicalURL = canonicalWebURL(url)
        if (canonicalURL != url) {
            return Decision.Redirect(canonicalURL)
        }

        if (shouldBlock(canonicalURL, currentURL)) {
            return Decision.Cancel
        }

        return Decision.Allow
    }

    private fun shouldBlock(url: String, currentURL: String?): Boolean {
        val parsed = BiliUrl.parse(url)
        val scheme = parsed.scheme?.lowercase() ?: ""
        if (scheme in blockedSchemes) return true

        val host = parsed.host ?: ""
        if (host in blockedHosts) return true

        val lowercasedPath = parsed.path.lowercase()
        val lowercasedURL = url.lowercase()
        val isBilibiliFamilyHost = isHostWithin(host, "bilibili.com") || isHostWithin(host, "hdslb.com")
        val cameFromVideoPage = currentURL?.let {
            val currentParsed = BiliUrl.parse(it)
            currentParsed.path.startsWith("/video/") ||
                (isHostWithin(currentParsed.host.orEmpty(), "bilibili.com") &&
                    it.lowercase().contains("/video/"))
        } ?: false

        if (isBilibiliFamilyHost && lowercasedPath.contains("/download")) return true
        if (lowercasedURL.contains("openapp") || lowercasedURL.contains("launchapp")) return true
        if (cameFromVideoPage && isBilibiliFamilyHost && lowercasedURL.contains("download")) return true

        return false
    }

    private fun isHostWithin(host: String, domain: String): Boolean =
        host == domain || host.endsWith(".$domain")

    companion object {
        private val blockedSchemes = setOf(
            "bilibili", "bilibilihd", "bstar", "intent", "itms-apps", "itmss",
        )
        private val blockedHosts = setOf("app.bilibili.com")

        fun canonicalWebURL(url: String): String {
            val parsed = BiliUrl.parse(url)
            val host = parsed.host ?: return url

            val path = parsed.path.lowercase()
            val isStandardBilibiliHost =
                host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com"

            // Normalize video/bangumi hosts to www.bilibili.com
            if (isStandardBilibiliHost &&
                (path.startsWith("/video/") || path.startsWith("/bangumi/play/"))
            ) {
                return parsed.withHost("www.bilibili.com").toUrl()
            }

            // Convert blackboard player URLs to canonical video URLs
            if (isStandardBilibiliHost &&
                (path.startsWith("/blackboard/html5player.html") ||
                    path.startsWith("/blackboard/html5mobileplayer.html"))
            ) {
                val videoPath = canonicalVideoPath(parsed)
                if (videoPath != null) {
                    val filteredItems = filteredVideoQueryItems(parsed.queryItems)
                    return parsed
                        .withScheme("https")
                        .withHost("www.bilibili.com")
                        .withPath(videoPath)
                        .withQueryItems(filteredItems)
                        .withFragment(null)
                        .toUrl()
                }
            }

            // Normalize opus paths
            if (isStandardBilibiliHost && path.startsWith("/opus/")) {
                return parsed.withHost("www.bilibili.com").toUrl()
            }

            // Convert t.bilibili.com/NNNN to www.bilibili.com/opus/NNNN
            if (host == "t.bilibili.com") {
                val pathComponents = parsed.path.split("/").filter { it.isNotEmpty() }
                if (pathComponents.size == 1 && pathComponents[0].all { it.isDigit() }) {
                    return parsed
                        .withScheme("https")
                        .withHost("www.bilibili.com")
                        .withPath("/opus/${pathComponents[0]}")
                        .toUrl()
                }
            }

            // Normalize live room URLs
            if (host == "live.bilibili.com") {
                val roomID = canonicalLiveRoomID(parsed)
                if (roomID != null) {
                    return parsed
                        .withScheme("https")
                        .withHost("live.bilibili.com")
                        .withPath("/$roomID")
                        .withQueryItems(null)
                        .withFragment(null)
                        .toUrl()
                }
            }

            return url
        }

        private fun canonicalVideoPath(parsed: BiliUrl): String? {
            val bvid = parsed.queryItems.firstOrNull {
                it.lowercasedName == "bvid" && !it.value.isNullOrEmpty()
            }?.value
            if (bvid != null) return "/video/$bvid"

            val aid = parsed.queryItems.firstOrNull {
                (it.lowercasedName == "aid" || it.lowercasedName == "avid") &&
                    !it.value.isNullOrEmpty()
            }?.value
            if (aid != null) return "/video/av$aid"

            return null
        }

        private val preservedQueryNames = setOf(
            "p", "cid", "t", "start_progress", "start_progress_ms",
            "spm_id_from", "vd_source", "from_spmid", "from_source",
        )

        private fun filteredVideoQueryItems(items: List<BiliUrl.QueryItem>): List<BiliUrl.QueryItem> {
            val filtered = items.filter { it.lowercasedName in preservedQueryNames }
            return filtered.ifEmpty { null } ?: emptyList()
        }

        private fun canonicalLiveRoomID(parsed: BiliUrl): String? {
            val pathComponents = parsed.path.split("/").filter { it.isNotEmpty() }
            val numericFromPath = pathComponents.lastOrNull { it.all { c -> c.isDigit() } }
            if (numericFromPath != null) return numericFromPath

            val liveRoomKeys = setOf("room_id", "roomid", "id")
            return parsed.queryItems
                .firstOrNull { it.lowercasedName in liveRoomKeys }
                ?.value
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        }
    }
}
