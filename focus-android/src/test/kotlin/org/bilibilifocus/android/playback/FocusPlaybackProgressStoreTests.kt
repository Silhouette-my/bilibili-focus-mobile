package org.bilibilifocus.android.playback

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

class FocusPlaybackProgressStoreTests {
    private val accountA = "account-v2-a"
    private val accountB = "account-v2-b"

    @Test
    fun `latest local progress is available for immediate re-entry`() {
        val store = FocusPlaybackProgressStore()

        store.record(accountA, "BV1TEST00001", cid = 101, positionMillis = 31_000)
        store.record(accountA, "bv1test00001", cid = 202, positionMillis = 87_000)

        assertEquals(
            FocusPlaybackProgress(cid = 202, positionMillis = 87_000),
            store.latestProgress(accountA, "BV1TEST00001"),
        )
        assertEquals(31_000, store.progress(accountA, "BV1TEST00001", 101)?.positionMillis)
        assertNull(store.progress(accountA, "BV1TEST00001", 303))
    }

    @Test
    fun `local progress wins while server history is propagating`() {
        assertEquals(
            87_000,
            FocusPlaybackResumePolicy.resolvePositionMillis(
                localPositionMillis = 87_000,
                serverPositionMillis = 45_000,
                durationMillis = 180_000,
            ),
        )
    }

    @Test
    fun `near-start and near-end progress restart from zero`() {
        assertEquals(
            0,
            FocusPlaybackResumePolicy.resolvePositionMillis(
                localPositionMillis = null,
                serverPositionMillis = 4_999,
                durationMillis = 180_000,
            ),
        )
        assertEquals(
            0,
            FocusPlaybackResumePolicy.resolvePositionMillis(
                localPositionMillis = null,
                serverPositionMillis = 175_000,
                durationMillis = 180_000,
            ),
        )
    }

    @Test
    fun `progress and pending history survive process recreation`() {
        val persistence = FakePlaybackPersistence()
        var now = 100L
        val first = FocusPlaybackProgressStore(
            persistence = persistence,
            nowEpochSeconds = { now },
        )

        first.record(accountA, "BV1TEST00001", cid = 101, positionMillis = 31_000)
        first.enqueueHistoryReport(
            accountScope = accountA,
            aid = 9_000_000_001,
            cid = 101,
            progressSeconds = 31,
        )

        now = 200
        val restored = FocusPlaybackProgressStore(
            persistence = persistence,
            nowEpochSeconds = { now },
        )
        assertEquals(31_000, restored.latestProgress(accountA, "bv1test00001")?.positionMillis)
        assertEquals(
            FocusPendingHistoryReport(
                aid = 9_000_000_001,
                cid = 101,
                progressSeconds = 31,
                revision = 1,
                updatedAtEpochSeconds = 100,
            ),
            restored.pendingHistoryReports(accountA).single(),
        )
    }

    @Test
    fun `outbox replaces backward progress and only acknowledges exact revision`() {
        val store = FocusPlaybackProgressStore(nowEpochSeconds = { 100 })

        val oldReport = store.enqueueHistoryReport(accountA, aid = 42, cid = 101, progressSeconds = 31)!!
        val newReport = store.enqueueHistoryReport(accountA, aid = 42, cid = 101, progressSeconds = 15)!!

        assertEquals(15, store.pendingHistoryReports(accountA).single().progressSeconds)
        assertNotEquals(oldReport.revision, newReport.revision)
        assertEquals(
            false,
            store.markHistorySubmitted(accountA, aid = 42, cid = 101, revision = oldReport.revision),
        )
        assertEquals(newReport, store.pendingHistoryReports(accountA).single())

        assertEquals(
            true,
            store.markHistorySubmitted(accountA, aid = 42, cid = 101, revision = newReport.revision),
        )
        assertEquals(emptyList(), store.pendingHistoryReports(accountA))
    }

    @Test
    fun `progress and outbox are isolated by account scope`() {
        val persistence = FakePlaybackPersistence()
        val store = FocusPlaybackProgressStore(persistence = persistence)

        store.record(accountA, "BV1TEST00001", 101, 31_000)
        store.enqueueHistoryReport(accountA, aid = 42, cid = 101, progressSeconds = 31)

        assertNull(store.latestProgress(accountB, "BV1TEST00001"))
        assertEquals(emptyList(), store.pendingHistoryReports(accountB))

        val restored = FocusPlaybackProgressStore(persistence = persistence)
        assertEquals(31_000, restored.latestProgress(accountA, "BV1TEST00001")?.positionMillis)
        assertEquals(31, restored.pendingHistoryReports(accountA).single().progressSeconds)
        assertNull(restored.latestProgress(accountB, "BV1TEST00001"))
        assertEquals(emptyList(), restored.pendingHistoryReports(accountB))
    }

    @Test
    fun `account scope prefers hashed user id and never exposes cookie values`() = runTest {
        val provider = FocusPlaybackAccountScopeProvider(
            FakeCookieProvider(
                listOf(
                    Cookie("DedeUserID", "123456", ".bilibili.com"),
                    Cookie("SESSDATA", "secret-session-a", ".bilibili.com"),
                ),
            ),
        )
        val first = provider.currentSnapshot()!!.scope
        val rotatedSession = provider.scopeFor(
            listOf(
                Cookie("DedeUserID", "123456", ".bilibili.com"),
                Cookie("SESSDATA", "secret-session-b", ".bilibili.com"),
            ),
        )
        val otherAccount = provider.scopeFor(
            listOf(Cookie("DedeUserID", "654321", ".bilibili.com")),
        )

        assertEquals(first, rotatedSession)
        assertNotEquals(first, otherAccount)
        assertEquals(false, first.contains("123456"))
        assertEquals(false, first.contains("secret-session"))
    }

    @Test
    fun `account scope falls back to an irreversible session fingerprint`() {
        val provider = FocusPlaybackAccountScopeProvider(FakeCookieProvider(emptyList()))

        val first = provider.scopeFor(
            listOf(Cookie("SESSDATA", "fallback-secret-a", "api.bilibili.com")),
        )
        val duplicateOrigins = provider.scopeFor(
            listOf(
                // A cross-host WebView snapshot can straddle an account switch.
                // Only the api.bilibili.com value used by the POST may scope it.
                Cookie("SESSDATA", "different-web-account", "www.bilibili.com"),
                Cookie("SESSDATA", "fallback-secret-a", "api.bilibili.com"),
            ),
        )
        val second = provider.scopeFor(
            listOf(Cookie("SESSDATA", "fallback-secret-b", "api.bilibili.com")),
        )

        assertEquals(first, duplicateOrigins)
        assertNotEquals(first, second)
        assertEquals(false, first.orEmpty().contains("fallback-secret-a"))
    }

    @Test
    fun `progress cache is bounded`() {
        val store = FocusPlaybackProgressStore(maximumProgressEntries = 2)

        store.record(accountA, "BV1TEST00001", 1, 1_000)
        store.record(accountA, "BV1TEST00002", 2, 2_000)
        store.record(accountA, "BV1TEST00003", 3, 3_000)

        assertNull(store.latestProgress(accountA, "BV1TEST00001"))
        assertEquals(2_000, store.latestProgress(accountA, "BV1TEST00002")?.positionMillis)
        assertEquals(3_000, store.latestProgress(accountA, "BV1TEST00003")?.positionMillis)
    }
}

private class FakePlaybackPersistence : FocusPlaybackPersistence {
    private val snapshots = mutableMapOf<String, FocusPlaybackPersistenceSnapshot>()

    override fun load(accountScope: String): FocusPlaybackPersistenceSnapshot =
        snapshots[accountScope] ?: FocusPlaybackPersistenceSnapshot()

    override fun save(accountScope: String, snapshot: FocusPlaybackPersistenceSnapshot) {
        snapshots[accountScope] = snapshot
    }
}

private class FakeCookieProvider(
    private val cookies: List<Cookie>,
) : CookieProvider {
    override suspend fun loadCookies(): List<Cookie> = cookies
}
