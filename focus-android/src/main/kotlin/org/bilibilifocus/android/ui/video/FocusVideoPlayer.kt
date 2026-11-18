package org.bilibilifocus.android.ui.video

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.view.OrientationEventListener
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@androidx.annotation.OptIn(UnstableApi::class)
@Composable
internal fun PlayerSurface(
    player: Player?,
    showController: Boolean,
    onToggleFullscreen: () -> Unit,
    attachmentKey: Int,
    modifier: Modifier = Modifier,
) {
    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                useController = showController
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                setShowNextButton(false)
                setShowPreviousButton(false)
                setBackgroundColor(android.graphics.Color.BLACK)
                setFullscreenButtonClickListener { onToggleFullscreen() }
            }
        },
        update = { view ->
            view.useController = showController
            view.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            if (view.tag != attachmentKey || view.player !== player) {
                view.player = null
                view.player = player
                view.tag = attachmentKey
            }
            view.setFullscreenButtonClickListener { onToggleFullscreen() }
        },
        onRelease = { view ->
            view.player = null
        },
        modifier = modifier,
    )
}

@Composable
internal fun PhoneFullscreenRotationEffect(
    enabled: Boolean,
    ignoreInitialOrientation: Boolean,
    onInitialOrientationConsumed: () -> Unit,
    onLandscape: (FocusPhysicalOrientation) -> Unit,
    onPortrait: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val currentIgnoreInitialOrientation by rememberUpdatedState(ignoreInitialOrientation)
    val currentOnInitialOrientationConsumed by rememberUpdatedState(onInitialOrientationConsumed)
    val currentOnLandscape by rememberUpdatedState(onLandscape)
    val currentOnPortrait by rememberUpdatedState(onPortrait)

    DisposableEffect(context, enabled) {
        if (!enabled) return@DisposableEffect onDispose { }

        var lastOrientation: FocusPhysicalOrientation? = null
        var debounceJob: Job? = null
        val listener = object : OrientationEventListener(context.applicationContext) {
            override fun onOrientationChanged(orientation: Int) {
                val resolvedOrientation = FocusPhysicalOrientation.fromDegrees(orientation) ?: return
                if (resolvedOrientation == lastOrientation) return
                val isInitialOrientation = lastOrientation == null
                lastOrientation = resolvedOrientation

                if (isInitialOrientation) {
                    currentOnInitialOrientationConsumed()
                    // Listener activation reports a posture snapshot. Ignore this event
                    // after PiP/window mode; it is not a new physical rotation.
                    if (FocusVideoRotationPolicy.shouldIgnoreInitialOrientationEvent(
                            isInitialOrientation = isInitialOrientation,
                            ignoreInitialOrientation = currentIgnoreInitialOrientation,
                            orientation = resolvedOrientation,
                        )
                    ) {
                        return
                    }
                }

                debounceJob?.cancel()
                debounceJob = scope.launch {
                    delay(180)
                    when (resolvedOrientation) {
                        FocusPhysicalOrientation.LandscapeClockwise,
                        FocusPhysicalOrientation.LandscapeCounterClockwise
                        -> currentOnLandscape(resolvedOrientation)
                        FocusPhysicalOrientation.Portrait -> currentOnPortrait()
                    }
                }
            }
        }

        if (listener.canDetectOrientation()) listener.enable()
        onDispose {
            debounceJob?.cancel()
            listener.disable()
        }
    }
}

internal enum class FocusVideoDeviceType {
    Phone,
    Tablet;

    companion object {
        fun fromSmallestWidth(smallestScreenWidthDp: Int): FocusVideoDeviceType =
            if (smallestScreenWidthDp < 600) Phone else Tablet
    }
}

internal object FocusVideoFullscreenPolicy {
    private const val DEFAULT_ASPECT_RATIO = 16f / 9f

    fun aspectRatio(width: Int, height: Int): Float =
        if (width > 0 && height > 0) width.toFloat() / height else DEFAULT_ASPECT_RATIO

    fun isPortrait(aspectRatio: Float): Boolean =
        aspectRatio.isFinite() && aspectRatio > 0f && aspectRatio <= 1f

    fun shouldFitToWidth(containerAspectRatio: Float, videoAspectRatio: Float): Boolean =
        containerAspectRatio.isFinite() &&
            videoAspectRatio.isFinite() &&
            containerAspectRatio > 0f &&
            videoAspectRatio > 0f &&
            containerAspectRatio <= videoAspectRatio
}

internal object FocusVideoRotationPolicy {
    fun shouldArmInitialOrientationIgnore(
        isInPictureInPictureMode: Boolean,
        isInMultiWindowMode: Boolean,
    ): Boolean = isInPictureInPictureMode || isInMultiWindowMode

    fun shouldIgnoreInitialOrientationEvent(
        isInitialOrientation: Boolean,
        ignoreInitialOrientation: Boolean,
        orientation: FocusPhysicalOrientation,
    ): Boolean = isInitialOrientation &&
        (ignoreInitialOrientation || orientation == FocusPhysicalOrientation.Portrait)

    fun shouldObservePhysicalOrientation(
        isPhone: Boolean,
        isVideoLoaded: Boolean,
        prefersPortraitFullscreen: Boolean,
        isInPictureInPictureMode: Boolean,
        isInMultiWindowMode: Boolean = false,
    ): Boolean = isPhone &&
        isVideoLoaded &&
        !prefersPortraitFullscreen &&
        !isInPictureInPictureMode &&
        !isInMultiWindowMode

    fun shouldCompleteFullscreenExit(
        isPhone: Boolean,
        isCompletingFullscreenExit: Boolean,
        configurationOrientation: Int,
        isInPictureInPictureMode: Boolean,
        isInMultiWindowMode: Boolean = false,
    ): Boolean = isCompletingFullscreenExit &&
        !isInPictureInPictureMode &&
        (isInMultiWindowMode || (
            isPhone && configurationOrientation == Configuration.ORIENTATION_PORTRAIT
        ))

    fun shouldApplyActivityOrientation(
        isInPictureInPictureMode: Boolean,
        isInMultiWindowMode: Boolean = false,
    ): Boolean = !isInPictureInPictureMode && !isInMultiWindowMode
}

internal enum class FocusPhysicalOrientation {
    Portrait,
    LandscapeClockwise,
    LandscapeCounterClockwise;

    companion object {
        fun fromDegrees(degrees: Int): FocusPhysicalOrientation? = when {
            degrees == OrientationEventListener.ORIENTATION_UNKNOWN -> null
            degrees in 315..359 || degrees in 0..44 -> Portrait
            degrees in 45..134 -> LandscapeClockwise
            degrees in 225..314 -> LandscapeCounterClockwise
            // 与 iOS 保持一致：倒置和设备平放时不触发全屏切换。
            else -> null
        }
    }
}

internal fun FocusPhysicalOrientation.requestedLandscapeOrientation(): Int = when (this) {
    FocusPhysicalOrientation.LandscapeClockwise -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
    FocusPhysicalOrientation.LandscapeCounterClockwise -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
    FocusPhysicalOrientation.Portrait -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
}

internal fun android.content.Context.findActivity(): android.app.Activity? {
    var ctx: android.content.Context? = this
    while (ctx is android.content.ContextWrapper) {
        if (ctx is android.app.Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}

internal fun setSystemBarsHidden(activity: android.app.Activity?, hidden: Boolean) {
    val window = activity?.window ?: return
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
        val controller = window.insetsController
        val bars = android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars()
        if (hidden) {
            controller?.hide(bars)
            controller?.systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            controller?.show(bars)
        }
    } else {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = if (hidden) {
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        } else {
            View.SYSTEM_UI_FLAG_VISIBLE
        }
    }
}
