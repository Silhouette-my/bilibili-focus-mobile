package org.bilibilifocus.core.service

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class BiliDiagnosticEvent(
    val method: String,
    val target: String,
    val statusCode: Int?,
    val durationMilliseconds: Long,
    val responseBytes: Int?,
    val failureType: String?,
)

@Serializable
data class BiliDiagnosticSnapshot(
    val schemaVersion: Int = 1,
    val loginHealth: LoginHealth,
    val events: List<BiliDiagnosticEvent>,
) {
    fun toJson(prettyPrinted: Boolean = false): String =
        Json {
            encodeDefaults = true
            prettyPrint = prettyPrinted
        }.encodeToString(this)
}

/**
 * Applies a second redaction boundary when events leave the local ring buffer.
 */
object BiliDiagnostics {
    suspend fun snapshot(
        loginHealth: LoginHealth,
        eventSink: InMemoryNetworkEventSink,
    ): BiliDiagnosticSnapshot =
        BiliDiagnosticSnapshot(
            loginHealth = loginHealth,
            events = eventSink.snapshot().map(::sanitize),
        )

    private fun sanitize(event: NetworkEvent): BiliDiagnosticEvent =
        BiliDiagnosticEvent(
            method = sanitizeMethod(event.method),
            target = redactedNetworkTarget(event.target),
            statusCode = event.statusCode?.takeIf { it in 100..599 },
            durationMilliseconds = event.durationMillis.coerceAtLeast(0),
            responseBytes = event.responseBytes?.coerceAtLeast(0),
            failureType = sanitizeFailureType(event.failureType),
        )

    private fun sanitizeMethod(method: String): String {
        val normalized = method.uppercase()
        return normalized.takeIf {
            it in setOf("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE")
        } ?: "OTHER"
    }

    private fun sanitizeFailureType(failureType: String?): String? {
        val normalized = failureType?.lowercase() ?: return null
        return when {
            "cancel" in normalized -> "cancelled"
            "timeout" in normalized || "timedout" in normalized -> "timeout"
            listOf("url", "network", "socket", "connect", "host", "dns", "io")
                .any { it in normalized } -> "network_unavailable"
            else -> "transport_error"
        }
    }
}
