package org.bilibilifocus.android

import android.app.PictureInPictureParams
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color as ComposeColor
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import org.bilibilifocus.android.playback.FocusPlaybackConnection
import org.bilibilifocus.android.playback.FocusPlaybackState
import org.bilibilifocus.android.ui.theme.BilibiliFocusTheme
import org.bilibilifocus.core.storage.SettingsRepository
import org.bilibilifocus.core.storage.SettingsStorage

class MainActivity : ComponentActivity() {
    private lateinit var playbackConnection: FocusPlaybackConnection
    private val pictureInPictureMode = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        playbackConnection = FocusPlaybackConnection(applicationContext)
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
            val playbackState by playbackConnection.state.collectAsState()
            val controller by playbackConnection.controller.collectAsState()
            var playerSurfaceRevision by remember { mutableIntStateOf(0) }

            LaunchedEffect(
                playbackState.shouldEnterPictureInPicture,
                playbackState.videoAspectRatio,
            ) {
                updatePictureInPictureParams(playbackState)
            }
            LaunchedEffect(pictureInPictureMode.value) {
                if (!pictureInPictureMode.value) {
                    withFrameNanos { }
                    playerSurfaceRevision += 1
                }
            }

            BilibiliFocusTheme(
                themeMode = settings.themeMode,
                accentColorHex = settings.accentColorHex,
            ) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    Box(modifier = Modifier.fillMaxSize()) {
                        FocusApp(
                            settingsViewModel = settingsViewModel,
                            playbackConnection = playbackConnection,
                            playerSurfaceRevision = playerSurfaceRevision,
                            isInPictureInPictureMode = pictureInPictureMode.value,
                        )
                        if (pictureInPictureMode.value) {
                            PictureInPicturePlayer(
                                player = controller,
                                modifier = Modifier.fillMaxSize(),
                            )
                        }
                    }
                }
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S &&
            playbackConnection.state.value.shouldEnterPictureInPicture
        ) {
            try {
                enterPictureInPictureMode(buildPictureInPictureParams(playbackConnection.state.value, false))
            } catch (_: IllegalArgumentException) {
                // Unsupported aspect ratios or device policy fall back to background audio.
            } catch (_: IllegalStateException) {
                // Activity lifecycle races also fall back to background audio.
            }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pictureInPictureMode.value = isInPictureInPictureMode
    }

    override fun onDestroy() {
        playbackConnection.close()
        super.onDestroy()
    }

    private fun updatePictureInPictureParams(state: FocusPlaybackState) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            setPictureInPictureParams(
                buildPictureInPictureParams(
                    state = state,
                    autoEnter = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        state.shouldEnterPictureInPicture,
                ),
            )
        } catch (_: IllegalArgumentException) {
            // Playback remains in the foreground media service when PiP is unavailable.
        } catch (_: IllegalStateException) {
            // Activity lifecycle races must not interrupt service playback.
        }
    }

    private fun buildPictureInPictureParams(
        state: FocusPlaybackState,
        autoEnter: Boolean,
    ): PictureInPictureParams {
        val ratio = FocusPictureInPicturePolicy.normalizedAspectRatio(state.videoAspectRatio)
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational((ratio * 1_000).toInt().coerceAtLeast(1), 1_000))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }
}

@OptIn(UnstableApi::class)
@androidx.compose.runtime.Composable
private fun PictureInPicturePlayer(
    player: androidx.media3.common.Player?,
    modifier: Modifier = Modifier,
) {
    AndroidView(
        factory = { context ->
            PlayerView(context).apply {
                useController = false
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                setBackgroundColor(Color.BLACK)
            }
        },
        update = { view ->
            if (view.player !== player) view.player = player
        },
        onRelease = { view -> view.player = null },
        modifier = modifier.background(ComposeColor.Black),
    )
}

internal object FocusActivityOrientationPolicy {
    fun defaultOrientation(smallestScreenWidthDp: Int): Int =
        if (smallestScreenWidthDp < 600) {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
}

internal object FocusPictureInPicturePolicy {
    fun shouldEnter(
        isConnected: Boolean,
        isNativeVideoActive: Boolean,
        isPlaying: Boolean,
    ): Boolean = isConnected && isNativeVideoActive && isPlaying

    fun normalizedAspectRatio(aspectRatio: Float): Float = aspectRatio
        .takeIf { it.isFinite() && it > 0f }
        ?.coerceIn(1f / 2.39f, 2.39f)
        ?: (16f / 9f)

    fun shouldRenderEmbeddedPlayerSurface(isInPictureInPictureMode: Boolean): Boolean =
        !isInPictureInPictureMode
}
