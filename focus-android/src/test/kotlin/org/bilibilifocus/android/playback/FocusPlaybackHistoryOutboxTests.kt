package org.bilibilifocus.android.playback

import androidx.work.ExistingWorkPolicy
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlin.test.assertFailsWith
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
    fun `deletion waits for in flight post retires old matching revisions and preserves new events`() = runTest {
        val cookies = accountCookies("10001", "session-a")
        val provider = FocusPlaybackAccountScopeProvider(SequencedCookieProvider(listOf(cookies)))
        val account = provider.scopeFor(cookies)!!
        val otherAccount = provider.scopeFor(accountCookies("20002", "session-b"))!!
        val store = FocusPlaybackProgressStore()
        store.record(account, "BV-DELETED", 101, 10_000)
        val first = store.enqueueHistoryReport(account, 42, 101, 10)!!
        val oldOtherPart = store.enqueueHistoryReport(account, 42, 102, 20)!!
        val unrelated = store.enqueueHistoryReport(account, 43, 103, 30)!!
        val otherUser = store.enqueueHistoryReport(otherAccount, 42, 101, 40)!!
        val reportStarted = CompletableDeferred<Unit>()
        val releaseReport = CompletableDeferred<Unit>()
        val deletionStarted = CompletableDeferred<Unit>()
        val releaseDeletion = CompletableDeferred<Unit>()
        val submissions = mutableListOf<FocusPendingHistoryReport>()
        val outbox = FocusPlaybackHistoryOutbox(provider, store, submitReport = { report, _ ->
            submissions += report
            if (report.revision == first.revision) { reportStarted.complete(Unit); releaseReport.await() }
            else throw IOException("offline after deletion")
        })
        val draining = async(start = CoroutineStart.UNDISPATCHED) { outbox.drainCurrentAccount() }
        reportStarted.await()
        val deleting = async(start = CoroutineStart.UNDISPATCHED) {
            outbox.mutateRemoteHistory(10001, 42) { deletionStarted.complete(Unit); releaseDeletion.await() }
        }
        assertFalse(deletionStarted.isCompleted)
        releaseReport.complete(Unit)
        deletionStarted.await()
        val replacement = store.enqueueHistoryReport(account, 42, 102, 50)!!
        releaseDeletion.complete(Unit)
        deleting.await()
        draining.await()
        assertFalse(submissions.any { it.revision == oldOtherPart.revision })
        assertEquals(listOf(unrelated, replacement), store.pendingHistoryReports(account))
        assertEquals(listOf(otherUser), store.pendingHistoryReports(otherAccount))
        assertEquals(10_000L, store.progress(account, "BV-DELETED", 101)?.positionMillis)
    }

    @Test
    fun `failed deletion keeps queue and clear retires only events captured before request`() = runTest {
        val cookies = accountCookies("10001", "session-a")
        val provider = FocusPlaybackAccountScopeProvider(SequencedCookieProvider(listOf(cookies)))
        val account = provider.scopeFor(cookies)!!
        val store = FocusPlaybackProgressStore()
        val old = store.enqueueHistoryReport(account, 42, 101, 10)!!
        val outbox = FocusPlaybackHistoryOutbox(provider, store, submitReport = { _, _ -> })
        assertFailsWith<IOException> { outbox.mutateRemoteHistory(10001, null) { throw IOException("offline") } }
        assertEquals(listOf(old), store.pendingHistoryReports(account))
        var replacement: FocusPendingHistoryReport? = null
        outbox.mutateRemoteHistory(10001, null) { replacement = store.enqueueHistoryReport(account, 42, 101, 30) }
        assertEquals(listOf(replacement!!), store.pendingHistoryReports(account))
    }

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
