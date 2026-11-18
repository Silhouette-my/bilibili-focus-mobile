package org.bilibilifocus.android.playback

import android.content.Context

class AndroidFocusPlaybackPersistence(context: Context) : FocusPlaybackPersistence {
    private val preferences = context.applicationContext.getSharedPreferences(
        "focus_playback",
        Context.MODE_PRIVATE,
    )

    init {
        // v1 had no account namespace. Loading it after an account switch could
        // submit one user's history with another user's credentials, so it is
        // deliberately discarded instead of guessed into a v2 account scope.
        preferences.edit()
            .remove(LEGACY_KEY_PROGRESS)
            .remove(LEGACY_KEY_PENDING_HISTORY)
            .apply()
    }

    override fun load(accountScope: String): FocusPlaybackPersistenceSnapshot =
        FocusPlaybackPersistenceSnapshot(
            nextRevision = preferences.getLong(scopedKey(KEY_NEXT_REVISION, accountScope), 1L),
            progress = preferences.getString(scopedKey(KEY_PROGRESS, accountScope), null)
                .orEmpty()
                .lineSequence()
                .mapNotNull(::decodeProgress)
                .toList(),
            pendingHistory = preferences.getString(
                scopedKey(KEY_PENDING_HISTORY, accountScope),
                null,
            )
                .orEmpty()
                .lineSequence()
                .mapNotNull(::decodePendingHistory)
                .toList(),
        )

    override fun save(accountScope: String, snapshot: FocusPlaybackPersistenceSnapshot) {
        val progress = snapshot.progress.joinToString("\n") {
            "${it.bvid},${it.cid},${it.positionMillis},${it.updatedAtEpochSeconds}"
        }
        val pendingHistory = snapshot.pendingHistory.joinToString("\n") {
            "${it.aid},${it.cid},${it.progressSeconds},${it.revision},${it.updatedAtEpochSeconds}"
        }
        preferences.edit()
            .putLong(scopedKey(KEY_NEXT_REVISION, accountScope), snapshot.nextRevision)
            .putString(scopedKey(KEY_PROGRESS, accountScope), progress)
            .putString(scopedKey(KEY_PENDING_HISTORY, accountScope), pendingHistory)
            .apply()
    }

    private fun decodeProgress(line: String): FocusPersistedPlaybackProgress? {
        val parts = line.split(',')
        if (parts.size != 4 || !BVID_PATTERN.matches(parts[0])) return null
        return FocusPersistedPlaybackProgress(
            bvid = parts[0],
            cid = parts[1].toLongOrNull()?.takeIf { it > 0 } ?: return null,
            positionMillis = parts[2].toLongOrNull()?.coerceAtLeast(0) ?: return null,
            updatedAtEpochSeconds = parts[3].toLongOrNull() ?: return null,
        )
    }

    private fun decodePendingHistory(line: String): FocusPendingHistoryReport? {
        val parts = line.split(',')
        if (parts.size != 5) return null
        return FocusPendingHistoryReport(
            aid = parts[0].toLongOrNull()?.takeIf { it > 0 } ?: return null,
            cid = parts[1].toLongOrNull()?.takeIf { it > 0 } ?: return null,
            progressSeconds = parts[2].toLongOrNull()?.coerceAtLeast(0) ?: return null,
            revision = parts[3].toLongOrNull()?.takeIf { it > 0 } ?: return null,
            updatedAtEpochSeconds = parts[4].toLongOrNull() ?: return null,
        )
    }

    private fun scopedKey(prefix: String, accountScope: String): String =
        "${prefix}_$accountScope"

    private companion object {
        const val LEGACY_KEY_PROGRESS = "progress_v1"
        const val LEGACY_KEY_PENDING_HISTORY = "pending_history_v1"
        const val KEY_PROGRESS = "progress_v2"
        const val KEY_PENDING_HISTORY = "pending_history_v2"
        const val KEY_NEXT_REVISION = "next_revision_v2"
        val BVID_PATTERN = Regex("(?i)^BV[0-9A-Za-z]{8,20}$")
    }
}
