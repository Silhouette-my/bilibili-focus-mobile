package org.bilibilifocus.android

import android.content.pm.ActivityInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import org.bilibilifocus.android.ui.theme.BilibiliFocusTheme
import org.bilibilifocus.core.storage.SettingsRepository
import org.bilibilifocus.core.storage.SettingsStorage

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        requestedOrientation = FocusActivityOrientationPolicy.defaultOrientation(
            resources.configuration.smallestScreenWidthDp,
        )
        setContent {
            val settingsViewModel = remember {
                FocusSettingsViewModel(
                    SettingsRepository(SettingsStorage(applicationContext)),
                )
            }
            val settings by settingsViewModel.settings.collectAsState()

            BilibiliFocusTheme(
                themeMode = settings.themeMode,
                accentColorHex = settings.accentColorHex,
            ) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    FocusApp(settingsViewModel = settingsViewModel)
                }
            }
        }
    }
}

internal object FocusActivityOrientationPolicy {
    fun defaultOrientation(smallestScreenWidthDp: Int): Int =
        if (smallestScreenWidthDp < 600) {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
}
