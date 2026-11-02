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
import androidx.media3.common.PlaybackException
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
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.TimeoutCancellationException
import org.bilibilifocus.android.FocusApplication
import org.bilibilifocus.android.MainActivity
import org.bilibilifocus.core.service.PlayUrlService
import org.bilibilifocus.core.model.PlayUrlResult

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
    private var recoveryJob: Job? = null
    private var stallJob: Job? = null
    private var sleepTimerJob: Job? = null
    private var recoveryResetJob: Job? = null
    private var recoveryAttempts = 0
    private var currentSource: PlayUrlResult? = null
    private var terminalError: String? = null
    private var sleepDeadlineMillis: Long = 0

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
        recoveryJob?.cancel()
        stallJob?.cancel()
        sleepTimerJob?.cancel()
        recoveryResetJob?.cancel()
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
                    .add(FocusPlaybackContract.sleepTimerCommand)
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

                FocusPlaybackContract.COMMAND_SLEEP_TIMER -> {
                    val minutes = args.getInt("minutes")
                    if (minutes !in listOf(0, 15, 30, 60)) return Futures.immediateFuture(SessionResult(SessionError.ERROR_BAD_VALUE))
                    sleepTimerJob?.cancel()
                    sleepDeadlineMillis = if (minutes == 0) 0 else System.currentTimeMillis() + minutes * 60_000L
                    if (minutes > 0) sleepTimerJob = serviceScope.launch {
                        delay(minutes * 60_000L)
                        player.pause()
                        sleepDeadlineMillis = 0
                        publishPlaybackExtras()
                    }
                    publishPlaybackExtras()
                    Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }

                else -> super.onCustomCommand(session, controller, customCommand, args)
            }
        }
    }

    private fun isApplicationController(controller: MediaSession.ControllerInfo): Boolean =
        controller.packageName == packageName

    private fun load(request: FocusPlaybackRequest): ListenableFuture<SessionResult> {
        if (!request.forceReload && currentRequest?.mediaId == request.mediaId &&
            currentRequest?.preferredQuality == request.preferredQuality && player.currentMediaItem != null && terminalError == null && player.playerError == null) {
            return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
        }

        pendingServiceStopJob?.cancel()
        pendingServiceStopJob = null
        reportCurrentPosition(force = true)
        loadJob?.cancel()
        recoveryJob?.cancel()
        recoveryJob = null
        stallJob?.cancel()
        stallJob = null
        recoveryAttempts = 0
        recoveryResetJob?.cancel()
        currentSource = null
        terminalError = null
        historyJob?.cancel()
        player.stop()
        player.clearMediaItems()
        player.playWhenReady = request.autoPlay
        player.setPlaybackSpeed(request.playbackSpeed)
        currentRequest = request
        lastReportedPositionSeconds = -1
        loadGeneration += 1
        val generation = loadGeneration
        publishPlaybackExtras()
        val resultFuture = SettableFuture.create<SessionResult>()
        loadJob = serviceScope.launch {
            try {
                val result = withTimeout(30_000) { playUrlService.fetchPlayUrl(request.bvid, request.cid, request.preferredQuality ?: 80) }

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
                currentSource = result
                applySource(request, result, request.startPositionMillis)
                publishPlaybackExtras()
                resultFuture.set(SessionResult(SessionResult.RESULT_SUCCESS))
            } catch (_: TimeoutCancellationException) {
                if (generation == loadGeneration) {
                    terminalError = "获取播放地址超时，请重试"
                    publishPlaybackExtras()
                }
                resultFuture.set(SessionResult(SessionError.ERROR_UNKNOWN, Bundle().apply { putString("message", "获取播放地址超时，请重试") }))
            } catch (_: CancellationException) {
                resultFuture.set(SessionResult(SessionResult.RESULT_SUCCESS))
            } catch (error: Exception) {
                if (generation == loadGeneration && currentRequest?.mediaId == request.mediaId) {
                    player.stop()
                    terminalError = error.message ?: "视频加载失败"
                    publishPlaybackExtras()
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
        recoveryJob?.cancel()
        recoveryJob = null
        stallJob?.cancel()
        stallJob = null
        sleepTimerJob?.cancel()
        recoveryResetJob?.cancel()
        sleepDeadlineMillis = 0
        historyJob?.cancel()
        historyJob = null
        historySubmissionJob = null
        pendingServiceStopJob?.cancel()
        currentRequest = null
        currentSource = null
        terminalError = null
        lastReportedPositionSeconds = -1
        player.stop()
        player.clearMediaItems()
        publishPlaybackExtras()
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
        override fun onPlaybackStateChanged(playbackState: Int) {
            stallJob?.cancel()
            stallJob = null
            if (playbackState == Player.STATE_BUFFERING && player.playWhenReady && recoveryJob?.isActive != true) {
                val generation = loadGeneration
                val position = player.currentPosition
                stallJob = serviceScope.launch {
                    delay(FocusPlaybackRecoveryPolicy.STALL_TIMEOUT_MILLIS)
                    if (generation == loadGeneration && player.playWhenReady && player.playbackState == Player.STATE_BUFFERING &&
                        player.currentPosition <= position + 500) recoverPlayback()
                }
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            if (FocusPlaybackRecoveryPolicy.canRecover(error.errorCode, recoveryAttempts)) recoverPlayback()
            else {
                terminalError = error.localizedMessage ?: "播放失败，请重试"
                publishPlaybackExtras()
            }
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            if (!playWhenReady) {
                stallJob?.cancel()
                stallJob = null
            } else if (player.playbackState == Player.STATE_BUFFERING) onPlaybackStateChanged(Player.STATE_BUFFERING)
        }

        override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
            if (player.playbackState == Player.STATE_BUFFERING) onPlaybackStateChanged(Player.STATE_BUFFERING)
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            historyJob?.cancel()
            historyJob = null
            recoveryResetJob?.cancel()
            recoveryResetJob = null
            if (isPlaying) {
                val generation = loadGeneration
                val position = player.currentPosition
                recoveryResetJob = serviceScope.launch {
                    delay(30_000)
                    if (generation == loadGeneration && player.isPlaying && player.currentPosition >= position + 10_000) recoveryAttempts = 0
                }
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

    private fun applySource(request: FocusPlaybackRequest, result: PlayUrlResult, positionMillis: Long) {
        val factory = DefaultHttpDataSource.Factory().setUserAgent(result.userAgent)
            .setDefaultRequestProperties(FocusPlaybackMediaRequestPolicy.headers(result.referer))
        val metadata = MediaMetadata.Builder().setTitle(request.title).setArtist(request.author)
            .setArtworkUri(request.artworkUrl?.let(Uri::parse)).setMediaType(MediaMetadata.MEDIA_TYPE_VIDEO).build()
        val item = MediaItem.Builder().setMediaId(request.mediaId).setUri(result.videoUrl).setMediaMetadata(metadata).build()
        val video = ProgressiveMediaSource.Factory(factory).createMediaSource(item)
        val source = result.audioUrl?.let { audioUrl ->
            val audio = ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(audioUrl))
            MergingMediaSource(video, audio)
        } ?: video
        player.setMediaSource(source, positionMillis.coerceAtLeast(0))
        player.prepare()
    }

    private fun recoverPlayback() {
        val request = currentRequest ?: return
        if (recoveryJob?.isActive == true) return
        if (recoveryAttempts >= FocusPlaybackRecoveryPolicy.MAX_ATTEMPTS) {
            terminalError = "播放中断，自动恢复未成功，请重试"
            player.stop()
            publishPlaybackExtras()
            return
        }
        recoveryAttempts += 1
        val attempt = recoveryAttempts
        val generation = loadGeneration
        val position = player.currentPosition.coerceAtLeast(0)
        terminalError = null
        recoveryJob = serviceScope.launch {
            publishPlaybackExtras(recovering = true)
            try {
                val source = currentSource
                val backup = source?.backupVideoUrls?.firstOrNull()
                val refreshed = if (attempt == 1 && backup != null) source.copy(
                    videoUrl = backup,
                    backupVideoUrls = source.backupVideoUrls.drop(1),
                    audioUrl = source.backupAudioUrls.firstOrNull() ?: source.audioUrl,
                    backupAudioUrls = source.backupAudioUrls.drop(1),
                ) else withTimeout(20_000) {
                    val quality = FocusPlaybackRecoveryPolicy.qualityForRecovery(request.preferredQuality, source?.quality ?: 80, source?.availableQualities?.map { it.id }.orEmpty(), attempt)
                    playUrlService.fetchPlayUrl(request.bvid, request.cid, quality)
                }
                if (generation != loadGeneration || currentRequest?.mediaId != request.mediaId) return@launch
                currentSource = refreshed
                applySource(request, refreshed, position)
            } catch (_: TimeoutCancellationException) {
                if (generation == loadGeneration) {
                    terminalError = "播放恢复超时，请重试"
                    player.stop()
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (generation == loadGeneration) {
                    // A fresh play-url API rejection is terminal: do not loop on credentials or permissions.
                    terminalError = error.message ?: "播放恢复失败，请重试"
                    player.stop()
                }
            } finally {
                if (generation == loadGeneration) {
                    recoveryJob = null
                    publishPlaybackExtras()
                    if (terminalError == null && player.playbackState == Player.STATE_BUFFERING) playerListener.onPlaybackStateChanged(Player.STATE_BUFFERING)
                }
            }
        }
    }

    private fun publishPlaybackExtras(recovering: Boolean = false) {
        if (!::mediaSession.isInitialized) return
        mediaSession.setSessionExtras(Bundle().apply {
            putString("media_id", currentRequest?.mediaId)
            putString("playback_error", terminalError)
            putBoolean("recovering", recovering)
            putInt("delivered_quality", currentSource?.quality ?: 0)
            putIntArray("quality_ids", currentSource?.availableQualities?.map { it.id }?.toIntArray() ?: intArrayOf())
            putStringArrayList("quality_titles", ArrayList(currentSource?.availableQualities?.map { it.title }.orEmpty()))
            putLong("sleep_deadline", sleepDeadlineMillis)
        })
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

internal object FocusPlaybackRecoveryPolicy {
    const val MAX_ATTEMPTS = 2
    const val STALL_TIMEOUT_MILLIS = 10_000L
    fun canRecover(errorCode: Int, attempts: Int): Boolean = attempts < MAX_ATTEMPTS && errorCode in 2000..2005
    fun qualityForRecovery(preferredQuality: Int?, deliveredQuality: Int, available: List<Int>, attempt: Int): Int {
        if (preferredQuality != null) return preferredQuality
        if (attempt < 2) return deliveredQuality
        return available.filter { it < deliveredQuality }.maxOrNull() ?: when {
            deliveredQuality > 64 -> 64
            deliveredQuality > 32 -> 32
            else -> deliveredQuality
        }
    }
}

internal object FocusPlaybackMediaRequestPolicy {
    fun headers(referer: String): Map<String, String> =
        mapOf("Referer" to referer)
}
