package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.LoginAccount

/**
 * 当前登录账号信息。基于 x/web-interface/nav：登录态、mid、昵称、头像、等级。
 * 未登录时返回 isLogin = false（不抛异常），由上层决定是否提示登录。
 */
class AccountService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object InvalidResponse : ServiceError("接口返回无效数据")
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchLoginAccount(): LoginAccount {
        val url = BiliApiContractCatalog.require("credential.info.valid").url
        val response = httpClient.get(url, buildHeaders(url))
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse

        val payload = json.parseToJsonElement(response.body) as? JsonObject
            ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: -1
        val data = payload.dictionaryValueAt("data") ?: return loggedOutAccount()
        val isLogin = code == 0 && data.stringValueAt("isLogin") == "true"
        if (!isLogin) {
            return loggedOutAccount()
        }

        return LoginAccount(
            isLogin = true,
            mid = data.longValueAt("mid") ?: 0L,
            name = data.stringValueAt("uname") ?: "",
            avatarURL = data.stringValueAt("face") ?: "",
            level = data.intValueAt("level_info", "current_level") ?: 0,
        )
    }

    private fun loggedOutAccount(): LoginAccount =
        LoginAccount(isLogin = false, mid = 0L, name = "", avatarURL = "", level = 0)

    private suspend fun buildHeaders(targetUrl: String): Map<String, String> {
        val headers = mutableMapOf(
            "User-Agent" to userAgent,
            "Referer" to "https://www.bilibili.com/",
            "Accept" to "application/json, text/plain, */*",
        )
        return cookieProvider.attachCookies(headers, targetUrl)
    }
}
