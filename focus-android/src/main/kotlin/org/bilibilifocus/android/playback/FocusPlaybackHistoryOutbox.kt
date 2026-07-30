package org.bilibilifocus.android.playback

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.service.VideoActionService

internal enum class FocusPlaybackHistoryDrainResult {
    DRAINED,
    BLOCKED_AUTH_OR_SCOPE,
    RETRYABLE_FAILURE,
}

internal enum class FocusPlaybackHistorySubmissionOutcome {
    DELIVERED,
    RETRYABLE_FAILURE,
    BLOCKED_AUTH_OR_SCOPE,
    PERMANENT_FAILURE,
}

/**
 * The only component allowed to physically submit and acknowledge durable
 * playback-history reports.
 *
 * Both the foreground playback service and WorkManager use this
 * application-scoped instance. Each POST resolves one fresh account snapshot,
 * verifies its scope, passes that exact cookie list to the request, and only
 * acknowledges the submitted revision.
 */
internal class FocusPlaybackHistoryOutbox(
    private val accountScopeProvider: FocusPlaybackAccountScopeProvider,
    private val progressStore: FocusPlaybackProgressStore,
    private val submitReport: suspend (
        report: FocusPendingHistoryReport,
        cookies: List<Cookie>,
    ) -> Unit,
    private val classifyFailure: (Throwable) -> FocusPlaybackHistorySubmissionOutcome =
        FocusPlaybackHistoryFailurePolicy::classify,
) {
    private val submissionMutex = Mutex()

    fun enqueue(
        accountScope: String,
        aid: Long,
        cid: Long,
        progressSeconds: Long,
    ): FocusPendingHistoryReport? = progressStore.enqueueHistoryReport(
        accountScope = accountScope,
        aid = aid,
        cid = cid,
        progressSeconds = progressSeconds,
    )

    suspend fun submitPending(
        expectedAccountScope: String,
        pending: FocusPendingHistoryReport,
    ): FocusPlaybackHistorySubmissionOutcome = submissionMutex.withLock {
        val current = progressStore.pendingHistoryReports(expectedAccountScope)
            .firstOrNull { report ->
                report.aid == pending.aid &&
                    report.cid == pending.cid &&
                    report.revision == pending.revision
            }
            ?: return@withLock FocusPlaybackHistorySubmissionOutcome.DELIVERED
        submitExactRevision(expectedAccountScope, current)
    }

    suspend fun drainCurrentAccount(): FocusPlaybackHistoryDrainResult {
        val expectedAccountScope = accountScopeProvider.currentSnapshot()?.scope
            ?: return FocusPlaybackHistoryDrainResult.BLOCKED_AUTH_OR_SCOPE
        var processedCount = 0

        while (processedCount < MAXIMUM_REPORTS_PER_DRAIN) {
            val pending = progressStore.pendingHistoryReports(expectedAccountScope).firstOrNull()
                ?: return FocusPlaybackHistoryDrainResult.DRAINED
            val result = submissionMutex.withLock {
                val current = progressStore.pendingHistoryReports(expectedAccountScope)
                    .firstOrNull { report ->
                        report.aid == pending.aid && report.cid == pending.cid
                    }
                    ?: return@withLock FocusPlaybackHistorySubmissionOutcome.DELIVERED
                submitExactRevision(expectedAccountScope, current)
            }
            when (result) {
                FocusPlaybackHistorySubmissionOutcome.DELIVERED,
                FocusPlaybackHistorySubmissionOutcome.PERMANENT_FAILURE,
                -> processedCount += 1

                FocusPlaybackHistorySubmissionOutcome.BLOCKED_AUTH_OR_SCOPE -> {
                    return FocusPlaybackHistoryDrainResult.BLOCKED_AUTH_OR_SCOPE
                }

                FocusPlaybackHistorySubmissionOutcome.RETRYABLE_FAILURE -> {
                    return FocusPlaybackHistoryDrainResult.RETRYABLE_FAILURE
                }
            }
        }

        return if (progressStore.pendingHistoryReports(expectedAccountScope).isEmpty()) {
            FocusPlaybackHistoryDrainResult.DRAINED
        } else {
            FocusPlaybackHistoryDrainResult.RETRYABLE_FAILURE
        }
    }

    private suspend fun submitExactRevision(
        expectedAccountScope: String,
        pending: FocusPendingHistoryReport,
    ): FocusPlaybackHistorySubmissionOutcome {
        return try {
            val account = accountScopeProvider.currentSnapshot()
                ?: return FocusPlaybackHistorySubmissionOutcome.BLOCKED_AUTH_OR_SCOPE
            if (account.scope != expectedAccountScope) {
                return FocusPlaybackHistorySubmissionOutcome.BLOCKED_AUTH_OR_SCOPE
            }
            submitReport(pending, account.cookies)
            progressStore.markHistorySubmitted(
                accountScope = expectedAccountScope,
                aid = pending.aid,
                cid = pending.cid,
                revision = pending.revision,
            )
            // A false acknowledgement means a newer revision replaced this
            // report during the POST. It remains durable and the drain loop
            // immediately picks up that newer revision.
            FocusPlaybackHistorySubmissionOutcome.DELIVERED
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            val outcome = classifyFailure(error)
            if (outcome == FocusPlaybackHistorySubmissionOutcome.PERMANENT_FAILURE) {
                // Remove only the revision that produced the permanent error.
                // A replacement enqueued while the POST was in flight remains
                // durable and is handled by the next drain iteration.
                progressStore.markHistorySubmitted(
                    accountScope = expectedAccountScope,
                    aid = pending.aid,
                    cid = pending.cid,
                    revision = pending.revision,
                )
            }
            outcome
        }
    }

    private companion object {
        const val MAXIMUM_REPORTS_PER_DRAIN = 100
    }
}

internal object FocusPlaybackHistoryFailurePolicy {
    private val transientApiCodes = setOf(-500, -503, -504, -509)

    fun classify(error: Throwable): FocusPlaybackHistorySubmissionOutcome = when (error) {
        VideoActionService.ServiceError.LoginRequired -> {
            FocusPlaybackHistorySubmissionOutcome.BLOCKED_AUTH_OR_SCOPE
        }

        is VideoActionService.ServiceError.Api -> when {
            error.code == -101 -> FocusPlaybackHistorySubmissionOutcome.BLOCKED_AUTH_OR_SCOPE
            error.code in transientApiCodes -> FocusPlaybackHistorySubmissionOutcome.RETRYABLE_FAILURE
            else -> FocusPlaybackHistorySubmissionOutcome.PERMANENT_FAILURE
        }

        VideoActionService.ServiceError.NoFavoriteFolder,
        is IllegalArgumentException,
        -> FocusPlaybackHistorySubmissionOutcome.PERMANENT_FAILURE

        VideoActionService.ServiceError.InvalidResponse -> {
            // The current core error does not expose its HTTP status. Retain
            // the report and let WorkManager's bounded backoff handle it.
            FocusPlaybackHistorySubmissionOutcome.RETRYABLE_FAILURE
        }

        else -> FocusPlaybackHistorySubmissionOutcome.RETRYABLE_FAILURE
    }
}
