package org.bilibilifocus.android.playback

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionError
import androidx.media3.session.SessionResult
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.bilibilifocus.android.FocusApplication
import org.bilibilifocus.android.MainActivity
import org.bilibilifocus.core.service.PlayUrlService

@OptIn(UnstableApi::class)
class FocusPlaybackService : MediaSessionService() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var player: ExoPlayer
    private lateinit var mediaSession: MediaSession
    private lateinit var playUrlService: PlayUrlService
    private lateinit var playbackProgressStore: FocusPlaybackProgressStore
    private lateinit var playbackHistoryOutbox: FocusPlaybackHistoryOutbox
    private var loadJob: Job? = null
    private var historyJob: Job? = null
    private var historySubmissionJob: Job? = null
    private var outboxFlushJob: Job? = null
    private var pendingServiceStopJob: Job? = null
    private var currentRequest: FocusPlaybackRequest? = null
    private var lastReportedPositionSeconds: Long = -1
    private var loadGeneration: Long = 0

    override fun onCreate() {
        super.onCreate()
        val appGraph = (application as FocusApplication).appGraph
        playUrlService = appGraph.playUrlService
        playbackProgressStore = appGraph.playbackProgressStore
        playbackHistoryOutbox = appGraph.playbackHistoryOutbox
        outboxFlushJob = serviceScope.launch {
            val result = playbackHistoryOutbox.drainCurrentAccount()
            if (result == FocusPlaybackHistoryDrainResult.RETRYABLE_FAILURE) {
                FocusPlaybackHistoryWorkScheduler.enqueue(this@FocusPlaybackService)
            }
        }
        player = ExoPlayer.Builder(this).build().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .build(),
                true,
            )
            setHandleAudioBecomingNoisy(true)
            addListener(playerListener)
        }

        val activityIntent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val sessionActivity = PendingIntent.getActivity(
            this,
            0,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        mediaSession = MediaSession.Builder(this, player)
            .setSessionActivity(sessionActivity)
            .setCallback(sessionCallback)
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession = mediaSession

    override fun onDestroy() {
        loadJob?.cancel()
        historyJob?.cancel()
        historySubmissionJob?.cancel()
        outboxFlushJob?.cancel()
        pendingServiceStopJob?.cancel()
        player.removeListener(playerListener)
        mediaSession.release()
        player.release()
        serviceScope.cancel()
        super.onDestroy()
    }

    private val sessionCallback = object : MediaSession.Callback {
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
        ): MediaSession.ConnectionResult {
            val commandsBuilder = MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS.buildUpon()
            if (isApplicationController(controller)) {
                commandsBuilder
                    .add(FocusPlaybackContract.loadCommand)
                    .add(FocusPlaybackContract.stopCommand)
            }
            return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                .setAvailableSessionCommands(commandsBuilder.build())
                .build()
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> {
            if (!isApplicationController(controller)) {
                return Futures.immediateFuture(
                    SessionResult(SessionError.ERROR_PERMISSION_DENIED),
                )
            }
            return when (customCommand.customAction) {
                FocusPlaybackContract.COMMAND_LOAD -> {
                    val request = FocusPlaybackRequest.fromBundle(args)
                        ?: return Futures.immediateFuture(
                            SessionResult(SessionError.ERROR_BAD_VALUE),
                        )
                    load(request)
                }

                FocusPlaybackContract.COMMAND_STOP -> {
                    stopPlayback()
                    Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }

                else -> super.onCustomCommand(session, controller, customCommand, args)
            }
        }
    }

    private fun isApplicationController(controller: MediaSession.ControllerInfo): Boolean =
        controller.packageName == packageName

    private fun load(request: FocusPlaybackRequest): ListenableFuture<SessionResult> {
        if (currentRequest?.mediaId == request.mediaId && player.currentMediaItem != null) {
            return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
        }

        pendingServiceStopJob?.cancel()
        pendingServiceStopJob = null
        reportCurrentPosition(force = true)
        loadJob?.cancel()
        historyJob?.cancel()
        player.stop()
        player.clearMediaItems()
        currentRequest = request
        lastReportedPositionSeconds = -1
        loadGeneration += 1
        val generation = loadGeneration
        val resultFuture = SettableFuture.create<SessionResult>()
        loadJob = serviceScope.launch {
            try {
                val result = playUrlService.fetchPlayUrl(request.bvid, request.cid)
                val requestHeaders = FocusPlaybackMediaRequestPolicy.headers(result.referer)
                val dataSourceFactory = DefaultHttpDataSource.Factory()
                    .setUserAgent(result.userAgent)
                    .setDefaultRequestProperties(requestHeaders)
                val metadata = MediaMetadata.Builder()
                    .setTitle(request.title)
                    .setArtist(request.author)
                    .setArtworkUri(request.artworkUrl?.let(Uri::parse))
                    .setMediaType(MediaMetadata.MEDIA_TYPE_VIDEO)
                    .build()
                val videoItem = MediaItem.Builder()
                    .setMediaId(request.mediaId)
                    .setUri(result.videoUrl)
                    .setMediaMetadata(metadata)
                    .build()
                val videoSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(videoItem)
                val mediaSource = result.audioUrl?.let { audioUrl ->
                    val audioItem = MediaItem.Builder()
                        .setMediaId("${request.mediaId}:audio")
                        .setUri(audioUrl)
                        .build()
                    val audioSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                        .createMediaSource(audioItem)
                    MergingMediaSource(videoSource, audioSource)
                } ?: videoSource

                if (!FocusPlaybackLoadPolicy.shouldApply(
                        requestGeneration = generation,
                        activeGeneration = loadGeneration,
                        requestMediaId = request.mediaId,
                        activeMediaId = currentRequest?.mediaId,
                    )
                ) {
                    resultFuture.set(SessionResult(SessionResult.RESULT_SUCCESS))
                    return@launch
                }
                player.setMediaSource(mediaSource, request.startPositionMillis.coerceAtLeast(0))
                player.prepare()
                player.playWhenReady = request.autoPlay
                resultFuture.set(SessionResult(SessionResult.RESULT_SUCCESS))
            } catch (_: CancellationException) {
                resultFuture.set(SessionResult(SessionResult.RESULT_SUCCESS))
            } catch (error: Exception) {
                if (generation == loadGeneration && currentRequest?.mediaId == request.mediaId) {
                    player.stop()
                }
                val extras = Bundle().apply {
                    putString("message", error.message ?: "视频加载失败")
                }
                resultFuture.set(SessionResult(SessionError.ERROR_UNKNOWN, extras))
            }
        }
        return resultFuture
    }

    private fun stopPlayback() {
        val finalHistoryReport = captureCurrentPosition(force = true)
        val inFlightHistorySubmission = historySubmissionJob
        loadGeneration += 1
        loadJob?.cancel()
        loadJob = null
        historyJob?.cancel()
        historyJob = null
        historySubmissionJob = null
        pendingServiceStopJob?.cancel()
        currentRequest = null
        lastReportedPositionSeconds = -1
        player.stop()
        player.clearMediaItems()
        when {
            finalHistoryReport != null -> {
                inFlightHistorySubmission?.cancel()
                pendingServiceStopJob = serviceScope.launch {
                    submitHistoryReport(finalHistoryReport)
                    if (currentRequest == null) {
                        stopSelf()
                    }
                }
            }

            inFlightHistorySubmission?.isActive == true -> {
                pendingServiceStopJob = serviceScope.launch {
                    inFlightHistorySubmission.join()
                    if (currentRequest == null) {
                        stopSelf()
                    }
                }
            }

            else -> stopSelf()
        }
    }

    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            historyJob?.cancel()
            historyJob = null
            if (isPlaying) {
                historyJob = serviceScope.launch {
                    while (true) {
                        delay(15_000)
                        reportCurrentPosition(force = false)
                    }
                }
            } else {
                reportCurrentPosition(force = true)
            }
        }
    }

    private fun reportCurrentPosition(force: Boolean) {
        val report = captureCurrentPosition(force) ?: return
        historySubmissionJob?.cancel()
        historySubmissionJob = serviceScope.launch {
            submitHistoryReport(report)
        }
    }

    private fun captureCurrentPosition(force: Boolean): FocusPlaybackHistoryReport? {
        val request = currentRequest ?: return null
        val positionMillis = player.currentPosition.coerceAtLeast(0)
        request.accountScope?.let { accountScope ->
            playbackProgressStore.record(
                accountScope = accountScope,
                bvid = request.bvid,
                cid = request.cid,
                positionMillis = positionMillis,
            )
        }
        if (request.aid <= 0 || request.cid <= 0) return null
        val seconds = positionMillis / 1_000
        if (!FocusPlaybackHistoryPolicy.shouldReport(seconds, lastReportedPositionSeconds, force)) return null
        lastReportedPositionSeconds = seconds
        return FocusPlaybackHistoryReport(
            aid = request.aid,
            cid = request.cid,
            progressSeconds = seconds,
            accountScope = request.accountScope,
        )
    }

    private suspend fun submitHistoryReport(report: FocusPlaybackHistoryReport) {
        val accountScope = report.accountScope ?: return
        val pending = playbackHistoryOutbox.enqueue(
            accountScope = accountScope,
            aid = report.aid,
            cid = report.cid,
            progressSeconds = report.progressSeconds,
        ) ?: return
        // WorkManager persists the retry intent before the opportunistic
        // foreground POST, covering service/process teardown after enqueue.
        FocusPlaybackHistoryWorkScheduler.enqueue(this)
        val result = playbackHistoryOutbox.submitPending(accountScope, pending)
        if (result == FocusPlaybackHistorySubmissionOutcome.RETRYABLE_FAILURE) {
            FocusPlaybackHistoryWorkScheduler.enqueue(this)
        }
    }
}

private data class FocusPlaybackHistoryReport(
    val aid: Long,
    val cid: Long,
    val progressSeconds: Long,
    val accountScope: String?,
)

internal object FocusPlaybackHistoryPolicy {
    fun shouldReport(positionSeconds: Long, lastPositionSeconds: Long, force: Boolean): Boolean {
        if (positionSeconds == lastPositionSeconds) return false
        return force || lastPositionSeconds < 0 ||
            kotlin.math.abs(positionSeconds - lastPositionSeconds) >= 15
    }
}

internal object FocusPlaybackLoadPolicy {
    fun shouldApply(
        requestGeneration: Long,
        activeGeneration: Long,
        requestMediaId: String,
        activeMediaId: String?,
    ): Boolean = requestGeneration == activeGeneration && requestMediaId == activeMediaId
}

internal object FocusPlaybackMediaRequestPolicy {
    fun headers(referer: String): Map<String, String> =
        mapOf("Referer" to referer)
}
