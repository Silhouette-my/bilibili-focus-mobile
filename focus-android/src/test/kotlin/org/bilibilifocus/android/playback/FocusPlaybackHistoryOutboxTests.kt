package org.bilibilifocus.android.playback

import androidx.work.ExistingWorkPolicy
import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.service.VideoActionService
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FocusPlaybackHistoryOutboxTests {
    @Test
    fun `drain submits and acknowledges with the exact account cookie snapshot`() = runTest {
        val cookies = accountCookies("10001", "session-a")
        val accountScopeProvider = FocusPlaybackAccountScopeProvider(
            SequencedCookieProvider(listOf(cookies)),
        )
        val accountScope = accountScopeProvider.scopeFor(cookies)!!
        val store = FocusPlaybackProgressStore()
        val pending = store.enqueueHistoryReport(accountScope, aid = 42, cid = 101, progressSeconds = 31)!!
        var submittedReport: FocusPendingHistoryReport? = null
        var submittedCookies: List<Cookie>? = null
        val outbox = FocusPlaybackHistoryOutbox(
            accountScopeProvider = accountScopeProvider,
            progressStore = store,
            submitReport = { report, snapshot ->
                submittedReport = report
                submittedCookies = snapshot
            },
        )

        assertEquals(FocusPlaybackHistoryDrainResult.DRAINED, outbox.drainCurrentAccount())
        assertEquals(pending, submittedReport)
        assertEquals(cookies, submittedCookies)
        assertEquals(emptyList(), store.pendingHistoryReports(accountScope))
    }

    @Test
    fun `account switch between drain and post retains the original report`() = runTest {
        val accountA = accountCookies("10001", "session-a")
        val accountB = accountCookies("20002", "session-b")
        val accountScopeProvider = FocusPlaybackAccountScopeProvider(
            SequencedCookieProvider(listOf(accountA, accountB)),
        )
        val accountScopeA = accountScopeProvider.scopeFor(accountA)!!
        val store = FocusPlaybackProgressStore()
        val pending = store.enqueueHistoryReport(accountScopeA, aid = 42, cid = 101, progressSeconds = 31)!!
        var submitCount = 0
        val outbox = FocusPlaybackHistoryOutbox(
            accountScopeProvider = accountScopeProvider,
            progressStore = store,
            submitReport = { _, _ -> submitCount += 1 },
        )

        assertEquals(
            FocusPlaybackHistoryDrainResult.BLOCKED_AUTH_OR_SCOPE,
            outbox.drainCurrentAccount(),
        )
        assertEquals(0, submitCount)
        assertEquals(listOf(pending), store.pendingHistoryReports(accountScopeA))
    }

    @Test
    fun `new revision created during post is retained and drained next`() = runTest {
        val cookies = accountCookies("10001", "session-a")
        val accountScopeProvider = FocusPlaybackAccountScopeProvider(
            SequencedCookieProvider(listOf(cookies)),
        )
        val accountScope = accountScopeProvider.scopeFor(cookies)!!
        val store = FocusPlaybackProgressStore(nowEpochSeconds = { 100 })
        val first = store.enqueueHistoryReport(
            accountScope,
            aid = 42,
            cid = 101,
            progressSeconds = 31,
        )!!
        val submissions = mutableListOf<FocusPendingHistoryReport>()
        var replacement: FocusPendingHistoryReport? = null
        val outbox = FocusPlaybackHistoryOutbox(
            accountScopeProvider = accountScopeProvider,
            progressStore = store,
            submitReport = { report, _ ->
                submissions += report
                if (report.revision == first.revision) {
                    replacement = store.enqueueHistoryReport(
                        accountScope,
                        aid = report.aid,
                        cid = report.cid,
                        progressSeconds = 15,
                    )
                }
            },
        )

        assertEquals(FocusPlaybackHistoryDrainResult.DRAINED, outbox.drainCurrentAccount())
        assertEquals(listOf(first.revision, replacement!!.revision), submissions.map { it.revision })
        assertEquals(listOf(31L, 15L), submissions.map { it.progressSeconds })
        assertEquals(emptyList(), store.pendingHistoryReports(accountScope))
    }

    @Test
    fun `permanent failure discards only its exact revision`() = runTest {
        val cookies = accountCookies("10001", "session-a")
        val accountScopeProvider = FocusPlaybackAccountScopeProvider(
            SequencedCookieProvider(listOf(cookies)),
        )
        val accountScope = accountScopeProvider.scopeFor(cookies)!!
        val store = FocusPlaybackProgressStore(nowEpochSeconds = { 100 })
        val first = store.enqueueHistoryReport(
            accountScope,
            aid = 42,
            cid = 101,
            progressSeconds = 31,
        )!!
        var replacement: FocusPendingHistoryReport? = null
        val outbox = FocusPlaybackHistoryOutbox(
            accountScopeProvider = accountScopeProvider,
            progressStore = store,
            submitReport = { report, _ ->
                replacement = store.enqueueHistoryReport(
                    accountScope,
                    aid = report.aid,
                    cid = report.cid,
                    progressSeconds = 15,
                )
                throw VideoActionService.ServiceError.Api(-400, "invalid progress")
            },
        )

        assertEquals(
            FocusPlaybackHistorySubmissionOutcome.PERMANENT_FAILURE,
            outbox.submitPending(accountScope, first),
        )
        assertEquals(listOf(replacement!!), store.pendingHistoryReports(accountScope))
    }

    @Test
    fun `drain discards permanent poison and continues with later reports`() = runTest {
        val cookies = accountCookies("10001", "session-a")
        val accountScopeProvider = FocusPlaybackAccountScopeProvider(
            SequencedCookieProvider(listOf(cookies)),
        )
        val accountScope = accountScopeProvider.scopeFor(cookies)!!
        val store = FocusPlaybackProgressStore(nowEpochSeconds = { 100 })
        val poison = store.enqueueHistoryReport(
            accountScope,
            aid = 42,
            cid = 101,
            progressSeconds = 31,
        )!!
        val deliverable = store.enqueueHistoryReport(
            accountScope,
            aid = 43,
            cid = 102,
            progressSeconds = 45,
        )!!
        val submissions = mutableListOf<FocusPendingHistoryReport>()
        val outbox = FocusPlaybackHistoryOutbox(
            accountScopeProvider = accountScopeProvider,
            progressStore = store,
            submitReport = { report, _ ->
                submissions += report
                if (report == poison) {
                    throw VideoActionService.ServiceError.Api(-400, "invalid parameters")
                }
            },
        )

        assertEquals(FocusPlaybackHistoryDrainResult.DRAINED, outbox.drainCurrentAccount())
        assertEquals(listOf(poison, deliverable), submissions)
        assertEquals(emptyList(), store.pendingHistoryReports(accountScope))
    }

    @Test
    fun `network failure retries and retains the report`() = runTest {
        val cookies = accountCookies("10001", "session-a")
        val accountScopeProvider = FocusPlaybackAccountScopeProvider(
            SequencedCookieProvider(listOf(cookies)),
        )
        val accountScope = accountScopeProvider.scopeFor(cookies)!!

        val transientStore = FocusPlaybackProgressStore()
        val transient = transientStore.enqueueHistoryReport(
            accountScope,
            aid = 42,
            cid = 101,
            progressSeconds = 31,
        )!!
        val transientOutbox = FocusPlaybackHistoryOutbox(
            accountScopeProvider = accountScopeProvider,
            progressStore = transientStore,
            submitReport = { _, _ -> throw IOException("offline") },
        )
        assertEquals(
            FocusPlaybackHistoryDrainResult.RETRYABLE_FAILURE,
            transientOutbox.drainCurrentAccount(),
        )
        assertEquals(listOf(transient), transientStore.pendingHistoryReports(accountScope))
    }

    @Test
    fun `authentication failure remains blocked and retains the report`() = runTest {
        val cookies = accountCookies("10001", "session-a")
        val accountScopeProvider = FocusPlaybackAccountScopeProvider(
            SequencedCookieProvider(listOf(cookies)),
        )
        val accountScope = accountScopeProvider.scopeFor(cookies)!!

        val authStore = FocusPlaybackProgressStore()
        val blocked = authStore.enqueueHistoryReport(
            accountScope,
            aid = 42,
            cid = 101,
            progressSeconds = 31,
        )!!
        val authOutbox = FocusPlaybackHistoryOutbox(
            accountScopeProvider = accountScopeProvider,
            progressStore = authStore,
            submitReport = { _, _ -> throw VideoActionService.ServiceError.LoginRequired },
        )
        assertEquals(
            FocusPlaybackHistoryDrainResult.BLOCKED_AUTH_OR_SCOPE,
            authOutbox.drainCurrentAccount(),
        )
        assertEquals(listOf(blocked), authStore.pendingHistoryReports(accountScope))
    }

    @Test
    fun `work policy appends a successor and bounds retry attempts`() {
        assertEquals(
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            FocusPlaybackHistoryWorkPolicy.existingWorkPolicy,
        )
        assertTrue(FocusPlaybackHistoryWorkPolicy.shouldRetry(0))
        assertTrue(FocusPlaybackHistoryWorkPolicy.shouldRetry(3))
        assertFalse(FocusPlaybackHistoryWorkPolicy.shouldRetry(4))
        assertFalse(FocusPlaybackHistoryWorkPolicy.shouldRetry(Int.MAX_VALUE))
    }
}

private class SequencedCookieProvider(
    snapshots: List<List<Cookie>>,
) : CookieProvider {
    private val snapshots = snapshots.toMutableList()
    private var lastSnapshot = snapshots.lastOrNull().orEmpty()

    override suspend fun loadCookies(): List<Cookie> {
        if (snapshots.isNotEmpty()) {
            lastSnapshot = snapshots.removeAt(0)
        }
        return lastSnapshot
    }
}

private fun accountCookies(mid: String, session: String): List<Cookie> = listOf(
    Cookie("DedeUserID", mid, ".bilibili.com"),
    Cookie("SESSDATA", session, ".bilibili.com"),
    Cookie("bili_jct", "csrf-$mid", ".bilibili.com"),
)
