package org.bilibilifocus.core.service

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.bilibilifocus.core.injection.readBundleResource

@Serializable
data class BiliApiContract(
    val url: String,
    val method: String,
    @SerialName("verify") val requiresAuthentication: Boolean,
    @SerialName("wbi") val usesWbi: Boolean,
    @SerialName("noCsrf") val skipsCsrf: Boolean,
)

@Serializable
data class BiliApiContractSource(
    val repository: String,
    val validatedCommit: String,
    val strategy: String,
)

@Serializable
data class BiliApiContractSnapshot(
    val schemaVersion: Int,
    val source: BiliApiContractSource,
    val endpoints: Map<String, BiliApiContract>,
)

object BiliApiContractCatalog {
    val snapshot: BiliApiContractSnapshot by lazy {
        Json { ignoreUnknownKeys = true }
            .decodeFromString<BiliApiContractSnapshot>(
                readBundleResource("bilibili-api-contracts.json"),
            )
            .also {
                check(it.schemaVersion == 1) {
                    "Unsupported bilibili-api contract schema ${it.schemaVersion}"
                }
            }
    }

    fun endpoint(key: String): BiliApiContract? = snapshot.endpoints[key]

    fun require(key: String): BiliApiContract =
        checkNotNull(endpoint(key)) { "Missing bilibili-api contract: $key" }
}
