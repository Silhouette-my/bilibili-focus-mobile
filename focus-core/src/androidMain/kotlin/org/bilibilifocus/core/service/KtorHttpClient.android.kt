package org.bilibilifocus.core.service

import io.ktor.client.HttpClient as KtorClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.get
import io.ktor.client.request.headers
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.URLProtocol
import io.ktor.http.contentType
import io.ktor.http.path

class KtorHttpClient : HttpClient {
    private val client = KtorClient(OkHttp)

    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
        val response = client.get(url) {
            headers {
                for ((key, value) in headers) {
                    append(key, value)
                }
            }
        }
        return HttpResponse(
            statusCode = response.status.value,
            body = response.bodyAsText(),
        )
    }

    override suspend fun getBytes(url: String, headers: Map<String, String>): BinaryHttpResponse {
        val response = client.get(url) {
            headers {
                for ((key, value) in headers) {
                    append(key, value)
                }
            }
        }
        return BinaryHttpResponse(
            statusCode = response.status.value,
            body = response.body(),
        )
    }

    override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse {
        val response = client.post(url) {
            headers {
                for ((key, value) in headers) {
                    append(key, value)
                }
            }
            contentType(ContentType.Application.FormUrlEncoded)
            setBody(body)
        }
        return HttpResponse(
            statusCode = response.status.value,
            body = response.bodyAsText(),
        )
    }

    override fun close() {
        client.close()
    }
}
