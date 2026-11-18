package org.bilibilifocus.android.playback

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import org.bilibilifocus.android.FocusApplication
import java.util.concurrent.TimeUnit

class FocusPlaybackHistoryWorker(
    appContext: Context,
    workerParameters: WorkerParameters,
) : CoroutineWorker(appContext, workerParameters) {
    override suspend fun doWork(): Result {
        val application = applicationContext as? FocusApplication
            ?: return Result.failure()
        return when (application.appGraph.playbackHistoryOutbox.drainCurrentAccount()) {
            FocusPlaybackHistoryDrainResult.DRAINED,
            FocusPlaybackHistoryDrainResult.BLOCKED_AUTH_OR_SCOPE,
            -> Result.success()

            FocusPlaybackHistoryDrainResult.RETRYABLE_FAILURE -> {
                if (FocusPlaybackHistoryWorkPolicy.shouldRetry(runAttemptCount)) {
                    Result.retry()
                } else {
                    // Reports remain durable. A later app/service lifecycle
                    // enqueue starts a fresh attempt. Completing successfully
                    // also lets a successor appended during this final run
                    // execute instead of inheriting a terminal failure.
                    Result.success()
                }
            }
        }
    }
}

internal object FocusPlaybackHistoryWorkScheduler {
    private const val UNIQUE_WORK_NAME = "focus-playback-history-outbox-v1"

    fun enqueue(context: Context) {
        val request = OneTimeWorkRequestBuilder<FocusPlaybackHistoryWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                FocusPlaybackHistoryWorkPolicy.BACKOFF_SECONDS,
                TimeUnit.SECONDS,
            )
            .addTag(UNIQUE_WORK_NAME)
            .build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            UNIQUE_WORK_NAME,
            FocusPlaybackHistoryWorkPolicy.existingWorkPolicy,
            request,
        )
    }
}

internal object FocusPlaybackHistoryWorkPolicy {
    const val BACKOFF_SECONDS = 30L
    val existingWorkPolicy: ExistingWorkPolicy = ExistingWorkPolicy.APPEND_OR_REPLACE
    private const val MAXIMUM_RUN_ATTEMPTS = 5

    fun shouldRetry(runAttemptCount: Int): Boolean =
        runAttemptCount.coerceAtLeast(0) < MAXIMUM_RUN_ATTEMPTS - 1
}
