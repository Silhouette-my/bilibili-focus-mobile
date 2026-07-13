package org.bilibilifocus.core.routing

object ArticleURL {
    fun extractCvid(rawURL: String): Long? {
        val value = rawURL.trim()
        Regex("""(?:https?:)?//(?:www\.|m\.)?bilibili\.com/read/cv(\d+)""", RegexOption.IGNORE_CASE)
            .find(value)?.groupValues?.getOrNull(1)?.toLongOrNull()?.let { return it }
        Regex("""bilibili://article/(?:cv)?(\d+)""", RegexOption.IGNORE_CASE)
            .find(value)?.groupValues?.getOrNull(1)?.toLongOrNull()?.let { return it }

        val mobile = Regex("""(?:https?:)?//(?:www\.|m\.)?bilibili\.com/read/mobile(?:\?|[^#]*&)id=(\d+)""", RegexOption.IGNORE_CASE)
            .find(value)?.groupValues?.getOrNull(1)?.toLongOrNull()
        return mobile
    }

    fun canonicalURL(rawURL: String): String? = extractCvid(rawURL)?.let(::canonicalURL)

    fun canonicalURL(cvid: Long): String = "https://www.bilibili.com/read/cv$cvid"
}
