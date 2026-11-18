package org.bilibilifocus.android.playback

import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.cookie.CookieRequestPolicy
import org.bilibilifocus.core.service.BiliApiContractCatalog
import java.security.MessageDigest

data class FocusPlaybackProgress(
    val cid: Long,
    val positionMillis: Long,
)

data class FocusPendingHistoryReport(
    val aid: Long,
    val cid: Long,
    val progressSeconds: Long,
    val revision: Long,
    val updatedAtEpochSeconds: Long,
)

data class FocusPersistedPlaybackProgress(
    val bvid: String,
    val cid: Long,
    val positionMillis: Long,
    val updatedAtEpochSeconds: Long,
)

data class FocusPlaybackPersistenceSnapshot(
    val nextRevision: Long = 1,
    val progress: List<FocusPersistedPlaybackProgress> = emptyList(),
    val pendingHistory: List<FocusPendingHistoryReport> = emptyList(),
)

interface FocusPlaybackPersistence {
    fun load(accountScope: String): FocusPlaybackPersistenceSnapshot
    fun save(accountScope: String, snapshot: FocusPlaybackPersistenceSnapshot)
}

private object NoOpFocusPlaybackPersistence : FocusPlaybackPersistence {
    override fun load(accountScope: String): FocusPlaybackPersistenceSnapshot =
        FocusPlaybackPersistenceSnapshot()

    override fun save(accountScope: String, snapshot: FocusPlaybackPersistenceSnapshot) = Unit
}

/**
 * An in-memory cookie snapshot paired with a stable, irreversible account key.
 * Only [scope] may cross into persistence or MediaSession bundles.
 */
data class FocusPlaybackAccountSnapshot(
    val scope: String,
    val cookies: List<Cookie>,
)

/**
 * Derives the playback persistence namespace from the same CookieProvider used
 * by API services. DedeUserID is preferred because session cookies can rotate;
 * all source values are SHA-256 hashed before leaving this class.
 */
class FocusPlaybackAccountScopeProvider(
    private val cookieProvider: CookieProvider,
) {
    suspend fun currentSnapshot(): FocusPlaybackAccountSnapshot? {
        val cookies = cookieProvider.loadCookies()
        val scope = scopeFor(cookies) ?: return null
        return FocusPlaybackAccountSnapshot(scope = scope, cookies = cookies)
    }

    fun scopeFor(cookies: List<Cookie>): String? {
        // Scope exactly the cookies that the history POST can send. If WebView
        // changes account while its per-host snapshot is being collected,
        // unrelated host entries cannot create a mixed/phantom account scope.
        val requestCookies = CookieRequestPolicy.matchingCookies(
            cookies,
            BiliApiContractCatalog.require("video.operate.report_history").url,
        )
        val userIDs = requestCookies
            .asSequence()
            .filter { it.name == DEDE_USER_ID }
            .map { it.value.trim() }
            .filter(String::isNotEmpty)
            .distinct()
            .sorted()
            .toList()

        val identityMaterial = if (userIDs.size == 1) {
            lengthPrefixed("mid", userIDs.single())
        } else {
            val fallback = requestCookies
                .asSequence()
                .filter { it.name in FALLBACK_IDENTITY_COOKIE_NAMES && it.value.isNotEmpty() }
                .map { it.name to it.value }
                .distinct()
                .sortedWith(compareBy<Pair<String, String>>({ it.first }, { it.second }))
                .toList()
            if (fallback.isEmpty()) return null
            buildString {
                fallback.forEach { (name, value) ->
                    append(lengthPrefixed(name, value))
                }
            }
        }

        return "$SCOPE_VERSION-${sha256(identityMaterial)}"
    }

    private fun lengthPrefixed(name: String, value: String): String =
        "${name.length}:$name:${value.length}:$value;"

    private fun sha256(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.encodeToByteArray())
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    private companion object {
        const val DEDE_USER_ID = "DedeUserID"
        const val SCOPE_VERSION = "account-v2"
        val FALLBACK_IDENTITY_COOKIE_NAMES = setOf(
            "SESSDATA",
            "DedeUserID__ckMd5",
        )
    }
}

/**
 * Bounded, account-scoped local playback state and durable history outbox.
 *
 * Every operation requires an irreversible account scope. Pending reports are
 * replaced by the newest revision, including when the user seeks backwards.
 * A network completion acknowledges only the exact revision it submitted.
 */
class FocusPlaybackProgressStore(
    private val persistence: FocusPlaybackPersistence = NoOpFocusPlaybackPersistence,
    private val nowEpochSeconds: () -> Long = { System.currentTimeMillis() / 1_000 },
    private val maximumProgressEntries: Int = 200,
    private val maximumPendingReports: Int = 100,
) {
    private data class StoredProgress(
        val bvid: String,
        val progress: FocusPlaybackProgress,
        val updatedAtEpochSeconds: Long,
    )

    private data class ScopedState(
        val positionsByMediaId: LinkedHashMap<String, StoredProgress> = linkedMapOf(),
        val latestMediaIdByBvid: MutableMap<String, String> = mutableMapOf(),
        val pendingHistoryByMediaId: LinkedHashMap<String, FocusPendingHistoryReport> =
            linkedMapOf(),
        var nextRevision: Long = 1,
    )

    init {
        require(maximumProgressEntries > 0)
        require(maximumPendingReports > 0)
    }

    private val stateByAccountScope = mutableMapOf<String, ScopedState>()

    @Synchronized
    fun record(
        accountScope: String,
        bvid: String,
        cid: Long,
        positionMillis: Long,
    ) {
        if (accountScope.isBlank() || bvid.isBlank() || cid <= 0) return
        val state = stateFor(accountScope)
        val normalizedBvid = bvid.lowercase()
        val mediaId = mediaId(normalizedBvid, cid)
        state.positionsByMediaId.remove(mediaId)
        state.positionsByMediaId[mediaId] = StoredProgress(
            bvid = normalizedBvid,
            progress = FocusPlaybackProgress(
                cid = cid,
                positionMillis = positionMillis.coerceAtLeast(0),
            ),
            updatedAtEpochSeconds = nowEpochSeconds(),
        )
        state.latestMediaIdByBvid[normalizedBvid] = mediaId
        trimProgress(state)
        persist(accountScope, state)
    }

    @Synchronized
    fun progress(accountScope: String, bvid: String, cid: Long): FocusPlaybackProgress? =
        stateFor(accountScope).positionsByMediaId[mediaId(bvid, cid)]?.progress

    @Synchronized
    fun latestProgress(accountScope: String, bvid: String): FocusPlaybackProgress? {
        val state = stateFor(accountScope)
        return state.latestMediaIdByBvid[bvid.lowercase()]
            ?.let(state.positionsByMediaId::get)
            ?.progress
    }

    @Synchronized
    fun enqueueHistoryReport(
        accountScope: String,
        aid: Long,
        cid: Long,
        progressSeconds: Long,
    ): FocusPendingHistoryReport? {
        if (accountScope.isBlank() || aid <= 0 || cid <= 0) return null
        val state = stateFor(accountScope)
        val report = FocusPendingHistoryReport(
            aid = aid,
            cid = cid,
            progressSeconds = progressSeconds.coerceAtLeast(0),
            revision = takeNextRevision(state),
            updatedAtEpochSeconds = nowEpochSeconds(),
        )
        val key = historyId(aid, cid)
        state.pendingHistoryByMediaId.remove(key)
        state.pendingHistoryByMediaId[key] = report
        while (state.pendingHistoryByMediaId.size > maximumPendingReports) {
            state.pendingHistoryByMediaId.remove(state.pendingHistoryByMediaId.keys.first())
        }
        persist(accountScope, state)
        return report
    }

    @Synchronized
    fun pendingHistoryReports(accountScope: String): List<FocusPendingHistoryReport> =
        stateFor(accountScope).pendingHistoryByMediaId.values.toList()

    @Synchronized
    fun markHistorySubmitted(
        accountScope: String,
        aid: Long,
        cid: Long,
        revision: Long,
    ): Boolean {
        val state = stateFor(accountScope)
        val key = historyId(aid, cid)
        val pending = state.pendingHistoryByMediaId[key] ?: return false
        if (pending.revision != revision) return false
        state.pendingHistoryByMediaId.remove(key)
        persist(accountScope, state)
        return true
    }

    private fun stateFor(accountScope: String): ScopedState =
        stateByAccountScope.getOrPut(accountScope) {
            restore(persistence.load(accountScope))
        }

    private fun restore(snapshot: FocusPlaybackPersistenceSnapshot): ScopedState {
        val state = ScopedState()
        snapshot.progress
            .filter { it.bvid.isNotBlank() && it.cid > 0 }
            .sortedBy(FocusPersistedPlaybackProgress::updatedAtEpochSeconds)
            .takeLast(maximumProgressEntries)
            .forEach { persisted ->
                val normalizedBvid = persisted.bvid.lowercase()
                val key = mediaId(normalizedBvid, persisted.cid)
                state.positionsByMediaId[key] = StoredProgress(
                    bvid = normalizedBvid,
                    progress = FocusPlaybackProgress(
                        cid = persisted.cid,
                        positionMillis = persisted.positionMillis.coerceAtLeast(0),
                    ),
                    updatedAtEpochSeconds = persisted.updatedAtEpochSeconds,
                )
                state.latestMediaIdByBvid[normalizedBvid] = key
            }

        snapshot.pendingHistory
            .filter { it.aid > 0 && it.cid > 0 && it.revision > 0 }
            .sortedWith(
                compareBy<FocusPendingHistoryReport>(
                    FocusPendingHistoryReport::updatedAtEpochSeconds,
                    FocusPendingHistoryReport::revision,
                ),
            )
            .forEach { report ->
                state.pendingHistoryByMediaId[historyId(report.aid, report.cid)] = report
            }
        while (state.pendingHistoryByMediaId.size > maximumPendingReports) {
            state.pendingHistoryByMediaId.remove(state.pendingHistoryByMediaId.keys.first())
        }

        val largestRevision = state.pendingHistoryByMediaId.values.maxOfOrNull {
            it.revision
        } ?: 0
        state.nextRevision = snapshot.nextRevision
            .takeIf { it > largestRevision && it > 0 }
            ?: nextAfter(largestRevision)
        return state
    }

    private fun takeNextRevision(state: ScopedState): Long {
        val revision = state.nextRevision.takeIf { it > 0 } ?: 1
        state.nextRevision = nextAfter(revision)
        return revision
    }

    private fun nextAfter(revision: Long): Long =
        if (revision == Long.MAX_VALUE) 1 else revision + 1

    private fun mediaId(bvid: String, cid: Long): String = "${bvid.lowercase()}:$cid"

    private fun historyId(aid: Long, cid: Long): String = "$aid:$cid"

    private fun trimProgress(state: ScopedState) {
        while (state.positionsByMediaId.size > maximumProgressEntries) {
            val oldestKey = state.positionsByMediaId.keys.first()
            val removed = state.positionsByMediaId.remove(oldestKey) ?: continue
            if (state.latestMediaIdByBvid[removed.bvid] == oldestKey) {
                state.latestMediaIdByBvid.remove(removed.bvid)
            }
        }
    }

    private fun persist(accountScope: String, state: ScopedState) {
        runCatching {
            persistence.save(
                accountScope,
                FocusPlaybackPersistenceSnapshot(
                    nextRevision = state.nextRevision,
                    progress = state.positionsByMediaId.values.map {
                        FocusPersistedPlaybackProgress(
                            bvid = it.bvid,
                            cid = it.progress.cid,
                            positionMillis = it.progress.positionMillis,
                            updatedAtEpochSeconds = it.updatedAtEpochSeconds,
                        )
                    },
                    pendingHistory = state.pendingHistoryByMediaId.values.toList(),
                ),
            )
        }
    }
}

internal object FocusPlaybackResumePolicy {
    private const val MINIMUM_RESUME_POSITION_MILLIS = 5_000L
    private const val END_RESTART_WINDOW_MILLIS = 5_000L

    fun resolvePositionMillis(
        localPositionMillis: Long?,
        serverPositionMillis: Long?,
        durationMillis: Long,
    ): Long {
        val position = (localPositionMillis ?: serverPositionMillis ?: 0).coerceAtLeast(0)
        if (position < MINIMUM_RESUME_POSITION_MILLIS) return 0
        if (durationMillis > 0 && position >= durationMillis - END_RESTART_WINDOW_MILLIS) return 0
        return if (durationMillis > 0) position.coerceAtMost(durationMillis) else position
    }
}
