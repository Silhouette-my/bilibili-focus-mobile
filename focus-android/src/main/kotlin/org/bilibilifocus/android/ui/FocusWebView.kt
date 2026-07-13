package org.bilibilifocus.android.ui

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.viewinterop.AndroidView

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun FocusWebView(
    url: String,
    userScript: String? = null,
    onUrlChanged: (String) -> Unit = {},
    onPageStarted: () -> Unit = {},
    onPageFinished: (String) -> Unit = {},
    onError: (String) -> Unit = {},
) {
    val isDarkMode = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val currentDarkMode by rememberUpdatedState(isDarkMode)
    val currentUserScript by rememberUpdatedState(userScript)
    val currentOnUrlChanged by rememberUpdatedState(onUrlChanged)
    val currentOnPageStarted by rememberUpdatedState(onPageStarted)
    val currentOnPageFinished by rememberUpdatedState(onPageFinished)
    val currentOnError by rememberUpdatedState(onError)
    AndroidView(
        factory = { context ->
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                settings.allowContentAccess = true
                settings.databaseEnabled = true
                settings.setSupportZoom(true)
                settings.builtInZoomControls = true
                settings.displayZoomControls = false
                settings.loadWithOverviewMode = true
                settings.useWideViewPort = true
                settings.userAgentString = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

                webViewClient = object : WebViewClient() {
                    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                        super.onPageStarted(view, url, favicon)
                        currentOnPageStarted()
                    }

                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        if (url != null) {
                            view?.evaluateJavascript(buildBilibiliThemeScript(currentDarkMode), null)
                            currentOnPageFinished(url)
                            currentUserScript?.let { script ->
                                view?.evaluateJavascript(script, null)
                            }
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
                        val scheme = request?.url?.scheme ?: return false

                        // Keep web URLs in WebView
                        if (scheme == "https" || scheme == "http") {
                            return false
                        }

                        // Silently consume bilibili:// and other app schemes — don't try to open them
                        return true
                    }
                }
            }
        },
        update = { webView ->
            if (webView.url != url) {
                webView.loadUrl(url)
            } else {
                webView.evaluateJavascript(buildBilibiliThemeScript(currentDarkMode), null)
            }
        },
    )
}
