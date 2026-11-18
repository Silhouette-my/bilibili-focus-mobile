package org.bilibilifocus.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp

@Composable
fun FocusBrowserScreen(
    initialUrl: String,
    userScript: String? = null,
) {
    val uriHandler = LocalUriHandler.current
    var isLoading by remember { mutableStateOf(true) }
    var currentUrl by remember { mutableStateOf(initialUrl) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    Box(modifier = Modifier.fillMaxSize()) {
        if (errorMessage != null) {
            Column(
                modifier = Modifier.fillMaxSize().padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    "页面加载失败",
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(
                    errorMessage ?: "",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
                Button(
                    onClick = {
                        errorMessage = null
                        isLoading = true
                    },
                    modifier = Modifier.padding(top = 16.dp),
                ) {
                    Text("重试")
                }
            }
        } else {
            FocusWebView(
                url = currentUrl,
                userScript = userScript,
                onUrlChanged = { currentUrl = it },
                onPageStarted = { isLoading = true },
                onPageFinished = { isLoading = false },
                onError = { errorMessage = it },
                onOpenExternal = { externalURL ->
                    runCatching { uriHandler.openUri(externalURL) }
                },
            )

            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center),
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}
