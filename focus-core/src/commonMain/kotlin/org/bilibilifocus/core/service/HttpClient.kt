package org.bilibilifocus.core.service

data class HttpRequest(
    val url: String,
    val headers: Map<String, String> = emptyMap(),
)

data class HttpResponse(
    val statusCode: Int,
    val body: String,
)

data class BinaryHttpResponse(
    val statusCode: Int,
    val body: ByteArray,
)

interface HttpClient {
    suspend fun get(url: String, headers: Map<String, String> = emptyMap()): HttpResponse
    suspend fun getBytes(url: String, headers: Map<String, String> = emptyMap()): BinaryHttpResponse {
        val response = get(url, headers)
        return BinaryHttpResponse(response.statusCode, response.body.encodeToByteArray())
    }
    suspend fun post(url: String, body: String = "", headers: Map<String, String> = emptyMap()): HttpResponse
}
