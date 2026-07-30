package org.bilibilifocus.android.ui

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.os.Build
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.viewinterop.AndroidView
import java.net.URI

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun FocusWebView(
    url: String,
    userScript: String? = null,
    onUrlChanged: (String) -> Unit = {},
    onPageStarted: () -> Unit = {},
    onPageFinished: (String) -> Unit = {},
    onError: (String) -> Unit = {},
    onOpenExternal: (String) -> Unit = {},
) {
    val isDarkMode = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val currentDarkMode by rememberUpdatedState(isDarkMode)
    val currentUserScript by rememberUpdatedState(userScript)
    val currentOnUrlChanged by rememberUpdatedState(onUrlChanged)
    val currentOnPageStarted by rememberUpdatedState(onPageStarted)
    val currentOnPageFinished by rememberUpdatedState(onPageFinished)
    val currentOnError by rememberUpdatedState(onError)
    val currentOnOpenExternal by rememberUpdatedState(onOpenExternal)
    AndroidView(
        factory = { context ->
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                settings.allowContentAccess = false
                settings.allowFileAccess = false
                settings.databaseEnabled = true
                settings.setSupportZoom(true)
                settings.builtInZoomControls = true
                settings.displayZoomControls = false
                settings.loadWithOverviewMode = true
                settings.useWideViewPort = true
                settings.userAgentString = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    settings.safeBrowsingEnabled = true
                }

                webViewClient = object : WebViewClient() {
                    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                        super.onPageStarted(view, url, favicon)
                        currentOnPageStarted()
                    }

                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        if (url != null) {
                            if (FocusWebNavigationPolicy.shouldInjectBilibiliScripts(url)) {
                                view?.evaluateJavascript(buildBilibiliThemeScript(currentDarkMode), null)
                                currentUserScript?.let { script ->
                                    view?.evaluateJavascript(script, null)
                                }
                            }
                            currentOnPageFinished(url)
                        }
                    }

                    override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) {
                        super.doUpdateVisitedHistory(view, url, isReload)
                        if (url != null) {
                            currentOnUrlChanged(url)
                        }
                    }

                    override fun onReceivedError(
                        view: WebView?,
                        request: WebResourceRequest?,
                        error: WebResourceError?,
                    ) {
                        if (request?.isForMainFrame == true && error != null) {
                            currentOnError("${error.errorCode}: ${error.description}")
                        }
                    }

                    override fun shouldOverrideUrlLoading(
                        view: WebView?,
                        request: WebResourceRequest?,
                    ): Boolean {
                        val requestUrl = request?.url?.toString() ?: return false
                        return when (val decision = FocusWebNavigationPolicy.decide(requestUrl)) {
                            is FocusWebNavigationDecision.Internal -> {
                                if (decision.url != requestUrl) {
                                    view?.loadUrl(decision.url)
                                    true
                                } else {
                                    false
                                }
                            }
                            is FocusWebNavigationDecision.External -> {
                                currentOnOpenExternal(decision.url)
                                true
                            }
                            FocusWebNavigationDecision.Blocked -> true
                        }
                    }
                }
            }
        },
        update = { webView ->
            when (val decision = FocusWebNavigationPolicy.decide(url)) {
                is FocusWebNavigationDecision.Internal -> {
                    webView.tag = null
                    if (webView.url != decision.url) {
                        webView.loadUrl(decision.url)
                    } else if (FocusWebNavigationPolicy.shouldInjectBilibiliScripts(decision.url)) {
                        webView.evaluateJavascript(buildBilibiliThemeScript(currentDarkMode), null)
                    }
                }
                is FocusWebNavigationDecision.External -> {
                    val tag = "external:${decision.url}"
                    if (webView.tag != tag) {
                        webView.tag = tag
                        currentOnOpenExternal(decision.url)
                    }
                }
                FocusWebNavigationDecision.Blocked -> {
                    val tag = "blocked:$url"
                    if (webView.tag != tag) {
                        webView.tag = tag
                        currentOnError("已阻止不受支持的链接")
                    }
                }
            }
        },
    )
}

internal sealed interface FocusWebNavigationDecision {
    data class Internal(val url: String) : FocusWebNavigationDecision
    data class External(val url: String) : FocusWebNavigationDecision
    data object Blocked : FocusWebNavigationDecision
}

internal object FocusWebNavigationPolicy {
    fun decide(rawURL: String): FocusWebNavigationDecision {
        val uri = runCatching { URI(rawURL) }.getOrNull()
            ?: return FocusWebNavigationDecision.Blocked
        val scheme = uri.scheme?.lowercase() ?: return FocusWebNavigationDecision.Blocked
        if (scheme != "http" && scheme != "https") return FocusWebNavigationDecision.Blocked
        val host = uri.host?.lowercase() ?: return FocusWebNavigationDecision.Blocked
        val isBilibili = host == "bilibili.com" || host.endsWith(".bilibili.com")
        if (!isBilibili) return FocusWebNavigationDecision.External(rawURL)
        if (uri.port != -1 && uri.port != 80 && uri.port != 443) {
            return FocusWebNavigationDecision.Blocked
        }
        if (scheme == "https" && uri.port != 80) {
            return FocusWebNavigationDecision.Internal(rawURL)
        }

        val upgraded = URI(
            "https",
            uri.userInfo,
            uri.host,
            if (uri.port == 80) -1 else uri.port,
            uri.path,
            uri.query,
            uri.fragment,
        ).toString()
        return FocusWebNavigationDecision.Internal(upgraded)
    }

    fun shouldInjectBilibiliScripts(rawURL: String): Boolean =
        decide(rawURL) is FocusWebNavigationDecision.Internal &&
            runCatching { URI(rawURL).scheme.equals("https", ignoreCase = true) }.getOrDefault(false)
}
