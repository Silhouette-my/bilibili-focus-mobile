package org.bilibilifocus.core.routing

fun urlEncode(value: String): String {
    val sb = StringBuilder()
    val hexDigits = "0123456789ABCDEF"
    // Encode the whole string first so UTF-16 surrogate pairs stay together.
    for (byte in value.encodeToByteArray()) {
        val octet = byte.toInt() and 0xFF
        val char = octet.toChar()
        when (char) {
            in 'a'..'z', in 'A'..'Z', in '0'..'9', '-', '_', '.', '~' -> sb.append(char)
            else -> {
                sb.append('%')
                sb.append(hexDigits[octet ushr 4])
                sb.append(hexDigits[octet and 0x0F])
            }
        }
    }
    return sb.toString()
}

/**
 * Lightweight URL component parser that avoids platform-specific dependencies.
 * Handles the subset of URL parsing needed for Bilibili navigation rules.
 */
data class BiliUrl(
    val scheme: String?,
    val host: String?,
    val path: String,
    val queryItems: List<QueryItem>,
    val fragment: String?,
) {
    data class QueryItem(val name: String, val value: String?) {
        val lowercasedName: String get() = name.lowercase()
    }

    val absoluteString: String
        get() {
            val sb = StringBuilder()
            if (scheme != null) {
                sb.append(scheme)
                sb.append("://")
            }
            sb.append(host ?: "")
            sb.append(path)
            if (queryItems.isNotEmpty()) {
                sb.append("?")
                sb.append(queryItems.joinToString("&") { "${it.name}=${it.value ?: ""}" })
            }
            if (fragment != null) {
                sb.append("#")
                sb.append(fragment)
            }
            return sb.toString()
        }

    fun withHost(newHost: String): BiliUrl = copy(host = newHost)

    fun withPath(newPath: String): BiliUrl = copy(path = newPath)

    fun withScheme(newScheme: String): BiliUrl = copy(scheme = newScheme)

    fun withQueryItems(newItems: List<QueryItem>?): BiliUrl = copy(queryItems = newItems ?: emptyList())

    fun withFragment(newFragment: String?): BiliUrl = copy(fragment = newFragment)

    fun toUrl(): String = absoluteString

    companion object {
        fun parse(urlString: String): BiliUrl {
            val trimmed = urlString.trim()

            // Parse scheme
            val schemeEnd = trimmed.indexOf("://")
            val (scheme, afterScheme) = if (schemeEnd > 0) {
                trimmed.substring(0, schemeEnd) to trimmed.substring(schemeEnd + 3)
            } else {
                null to trimmed
            }

            // Split fragment
            val fragmentIndex = afterScheme.indexOf('#')
            val (beforeFragment, fragment) = if (fragmentIndex >= 0) {
                afterScheme.substring(0, fragmentIndex) to afterScheme.substring(fragmentIndex + 1)
            } else {
                afterScheme to null
            }

            // Split query
            val queryIndex = beforeFragment.indexOf('?')
            val (hostPath, queryString) = if (queryIndex >= 0) {
                beforeFragment.substring(0, queryIndex) to beforeFragment.substring(queryIndex + 1)
            } else {
                beforeFragment to null
            }

            // Split host and path
            val pathIndex = hostPath.indexOf('/')
            val (host, path) = if (pathIndex >= 0) {
                hostPath.substring(0, pathIndex).lowercase() to hostPath.substring(pathIndex)
            } else {
                hostPath.lowercase() to "/"
            }

            // Parse query items
            val queryItems = if (!queryString.isNullOrEmpty()) {
                queryString.split("&").mapNotNull { pair ->
                    val eqIndex = pair.indexOf('=')
                    if (eqIndex >= 0) {
                        QueryItem(pair.substring(0, eqIndex), pair.substring(eqIndex + 1))
                    } else if (pair.isNotEmpty()) {
                        QueryItem(pair, null)
                    } else {
                        null
                    }
                }
            } else {
                emptyList()
            }

            return BiliUrl(
                scheme = scheme,
                host = host,
                path = path,
                queryItems = queryItems,
                fragment = fragment,
            )
        }
    }
}
