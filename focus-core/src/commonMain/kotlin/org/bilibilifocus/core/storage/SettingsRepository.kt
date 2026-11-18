package org.bilibilifocus.core.storage

import kotlinx.serialization.json.Json
import org.bilibilifocus.core.model.FocusSettings

class SettingsRepository(private val storage: SettingsStorage) {
    private val json = Json { ignoreUnknownKeys = true }

    fun load(): FocusSettings {
        val raw = storage.getString(FocusSettings.STORAGE_KEY) ?: return FocusSettings.DEFAULTS
        return try {
            json.decodeFromString<FocusSettings>(raw).let { it.copy(playbackPreferences = it.playbackPreferences.normalized()) }
        } catch (_: Exception) {
            FocusSettings.DEFAULTS
        }
    }

    fun save(settings: FocusSettings) {
        storage.putString(FocusSettings.STORAGE_KEY, json.encodeToString(settings))
    }
}
