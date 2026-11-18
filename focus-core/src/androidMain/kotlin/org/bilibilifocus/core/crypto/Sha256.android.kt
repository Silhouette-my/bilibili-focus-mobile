package org.bilibilifocus.core.crypto

import java.security.MessageDigest

internal actual fun sha256Hex(input: String): String =
    MessageDigest.getInstance("SHA-256")
        .digest(input.encodeToByteArray())
        .joinToString("") { "%02x".format(it) }
