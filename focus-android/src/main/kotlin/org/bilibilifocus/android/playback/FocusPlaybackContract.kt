package org.bilibilifocus.android.playback

import android.os.Bundle
import androidx.media3.session.SessionCommand

data class FocusPlaybackRequest(
    val bvid: String,
    val aid: Long,
    val cid: Long,
    val title: String,
    val author: String,
    val artworkUrl: String?,
    val durationSeconds: Long,
    val accountScope: String?,
    val startPositionMillis: Long = 0,
    val autoPlay: Boolean = true,
    val preferredQuality: Int? = null,
    val playbackSpeed: Float = 1f,
    val forceReload: Boolean = false,
) {
    val mediaId: String = "$bvid:$cid:${accountScope.orEmpty()}"

    fun toBundle(): Bundle = Bundle().apply {
        putString(FocusPlaybackContract.KEY_BVID, bvid)
        putLong(FocusPlaybackContract.KEY_AID, aid)
        putLong(FocusPlaybackContract.KEY_CID, cid)
        putString(FocusPlaybackContract.KEY_TITLE, title)
        putString(FocusPlaybackContract.KEY_AUTHOR, author)
        putString(FocusPlaybackContract.KEY_ARTWORK_URL, artworkUrl)
        putLong(FocusPlaybackContract.KEY_DURATION_SECONDS, durationSeconds)
        putString(FocusPlaybackContract.KEY_ACCOUNT_SCOPE, accountScope)
        putLong(FocusPlaybackContract.KEY_START_POSITION_MILLIS, startPositionMillis)
        putBoolean(FocusPlaybackContract.KEY_AUTO_PLAY, autoPlay)
        preferredQuality?.let { putInt("quality", it) }
        putFloat("speed", playbackSpeed)
        putBoolean("force_reload", forceReload)
    }

    companion object {
        fun fromBundle(bundle: Bundle): FocusPlaybackRequest? {
            val bvid = bundle.getString(FocusPlaybackContract.KEY_BVID)?.takeIf(String::isNotBlank)
                ?: return null
            val cid = bundle.getLong(FocusPlaybackContract.KEY_CID)
            if (cid <= 0) return null
            return FocusPlaybackRequest(
                bvid = bvid,
                aid = bundle.getLong(FocusPlaybackContract.KEY_AID),
                cid = cid,
                title = bundle.getString(FocusPlaybackContract.KEY_TITLE).orEmpty(),
                author = bundle.getString(FocusPlaybackContract.KEY_AUTHOR).orEmpty(),
                artworkUrl = bundle.getString(FocusPlaybackContract.KEY_ARTWORK_URL),
                durationSeconds = bundle.getLong(FocusPlaybackContract.KEY_DURATION_SECONDS),
                accountScope = bundle.getString(FocusPlaybackContract.KEY_ACCOUNT_SCOPE)
                    ?.takeIf(String::isNotBlank),
                startPositionMillis = bundle.getLong(FocusPlaybackContract.KEY_START_POSITION_MILLIS),
                autoPlay = bundle.getBoolean(FocusPlaybackContract.KEY_AUTO_PLAY, true),
                preferredQuality = bundle.getInt("quality").takeIf { bundle.containsKey("quality") && it > 0 },
                playbackSpeed = bundle.getFloat("speed", 1f).takeIf { it.isFinite() && it in 0.5f..3f } ?: 1f,
                forceReload = bundle.getBoolean("force_reload", false),
            )
        }
    }
}

object FocusPlaybackContract {
    const val COMMAND_LOAD = "org.bilibilifocus.android.playback.LOAD"
    const val COMMAND_STOP = "org.bilibilifocus.android.playback.STOP"
    const val COMMAND_SLEEP_TIMER = "org.bilibilifocus.android.playback.SLEEP_TIMER"

    val loadCommand: SessionCommand
        get() = SessionCommand(COMMAND_LOAD, Bundle.EMPTY)
    val stopCommand: SessionCommand
        get() = SessionCommand(COMMAND_STOP, Bundle.EMPTY)
    val sleepTimerCommand: SessionCommand
        get() = SessionCommand(COMMAND_SLEEP_TIMER, Bundle.EMPTY)

    internal const val KEY_BVID = "bvid"
    internal const val KEY_AID = "aid"
    internal const val KEY_CID = "cid"
    internal const val KEY_TITLE = "title"
    internal const val KEY_AUTHOR = "author"
    internal const val KEY_ARTWORK_URL = "artwork_url"
    internal const val KEY_DURATION_SECONDS = "duration_seconds"
    internal const val KEY_ACCOUNT_SCOPE = "account_scope"
    internal const val KEY_START_POSITION_MILLIS = "start_position_millis"
    internal const val KEY_AUTO_PLAY = "auto_play"
}
