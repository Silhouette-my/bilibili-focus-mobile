package org.bilibilifocus.android.playback

import android.content.ComponentName
import android.content.Context
import androidx.core.content.ContextCompat
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.session.MediaController
import androidx.media3.session.SessionResult
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.bilibilifocus.android.FocusPictureInPicturePolicy

data class FocusPlaybackState(
    val isConnected: Boolean = false,
    val isNativeVideoActive: Boolean = false,
    val isPlaying: Boolean = false,
    val mediaId: String? = null,
    val playbackSpeed: Float = 1f,
    val videoAspectRatio: Float = 16f / 9f,
    val errorMessage: String? = null,
) {
    val shouldEnterPictureInPicture: Boolean
        get() = FocusPictureInPicturePolicy.shouldEnter(
            isConnected = isConnected,
            isNativeVideoActive = isNativeVideoActive,
            isPlaying = isPlaying,
        )
}

class FocusPlaybackConnection(context: Context) {
    private val appContext = context.applicationContext
    private val mainExecutor = ContextCompat.getMainExecutor(appContext)
    private val controllerFuture: ListenableFuture<MediaController>
    private var pendingRequest: FocusPlaybackRequest? = null
    private val _controller = MutableStateFlow<MediaController?>(null)
    val controller: StateFlow<MediaController?> = _controller.asStateFlow()
    private val _state = MutableStateFlow(FocusPlaybackState())
    val state: StateFlow<FocusPlaybackState> = _state.asStateFlow()

    init {
        val token = SessionToken(
            appContext,
            ComponentName(appContext, FocusPlaybackService::class.java),
        )
        controllerFuture = MediaController.Builder(appContext, token).buildAsync()
        controllerFuture.addListener(
            {
                try {
                    val controller = controllerFuture.get()
                    controller.addListener(playerListener)
                    _controller.value = controller
                    updateFromPlayer(controller)
                    pendingRequest?.let {
                        pendingRequest = null
                        sendLoad(controller, it)
                    }
                } catch (error: Exception) {
                    _state.value = _state.value.copy(
                        isConnected = false,
                        errorMessage = error.message ?: "无法连接播放服务",
                    )
                }
            },
            mainExecutor,
        )
    }

    fun load(request: FocusPlaybackRequest) {
        _state.value = _state.value.copy(
            isNativeVideoActive = true,
            errorMessage = null,
        )
        val controller = _controller.value
        if (controller == null) {
            pendingRequest = request
        } else {
            sendLoad(controller, request)
        }
    }

    fun stop() {
        pendingRequest = null
        _state.value = _state.value.copy(
            isNativeVideoActive = false,
            isPlaying = false,
            mediaId = null,
            errorMessage = null,
        )
        _controller.value?.let { controller ->
            val future = controller.sendCustomCommand(FocusPlaybackContract.stopCommand, android.os.Bundle.EMPTY)
            observeCommandResult(future)
        }
    }

    fun markNativeVideoActive(active: Boolean) {
        _state.value = _state.value.copy(isNativeVideoActive = active)
    }

    fun clearError() {
        _state.value = _state.value.copy(errorMessage = null)
    }

    fun close() {
        _controller.value?.removeListener(playerListener)
        _controller.value = null
        _state.value = _state.value.copy(isConnected = false)
        MediaController.releaseFuture(controllerFuture)
    }

    private fun sendLoad(controller: MediaController, request: FocusPlaybackRequest) {
        val future = controller.sendCustomCommand(
            FocusPlaybackContract.loadCommand,
            request.toBundle(),
        )
        observeCommandResult(future)
    }

    private fun observeCommandResult(future: ListenableFuture<SessionResult>) {
        future.addListener(
            {
                try {
                    val result = future.get()
                    if (result.resultCode != SessionResult.RESULT_SUCCESS) {
                        _state.value = _state.value.copy(
                            errorMessage = result.extras.getString("message") ?: "播放请求失败",
                        )
                    }
                } catch (error: Exception) {
                    _state.value = _state.value.copy(
                        errorMessage = error.message ?: "播放请求失败",
                    )
                }
            },
            mainExecutor,
        )
    }

    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _controller.value?.let(::updateFromPlayer)
        }

        override fun onMediaItemTransition(mediaItem: androidx.media3.common.MediaItem?, reason: Int) {
            _controller.value?.let(::updateFromPlayer)
        }

        override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
            _controller.value?.let(::updateFromPlayer)
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            val ratio = if (videoSize.width > 0 && videoSize.height > 0) {
                (videoSize.width * videoSize.pixelWidthHeightRatio) / videoSize.height.toFloat()
            } else {
                _state.value.videoAspectRatio
            }
            if (ratio.isFinite() && ratio > 0f) {
                _state.value = _state.value.copy(videoAspectRatio = ratio)
            }
        }

        override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
            _state.value = _state.value.copy(errorMessage = error.localizedMessage ?: "播放失败")
        }
    }

    private fun updateFromPlayer(controller: MediaController) {
        _state.value = _state.value.copy(
            isConnected = true,
            isPlaying = controller.isPlaying,
            mediaId = controller.currentMediaItem?.mediaId,
            playbackSpeed = controller.playbackParameters.speed,
        )
    }
}
