package org.bilibilifocus.android

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.bilibilifocus.core.model.DynamicCard
import org.bilibilifocus.core.model.FocusDynamicFilterKind
import org.bilibilifocus.core.model.FocusSettings
import org.bilibilifocus.core.storage.SettingsRepository

class FocusSettingsViewModel(
    private val repository: SettingsRepository,
) {
    private val _settings = MutableStateFlow(repository.load())
    val settings: StateFlow<FocusSettings> = _settings.asStateFlow()

    fun update(transform: (FocusSettings) -> FocusSettings) {
        val updated = transform(_settings.value)
        if (updated == _settings.value) return
        _settings.value = updated
        repository.save(updated)
    }

    fun reset() {
        _settings.value = FocusSettings.DEFAULTS
        repository.save(FocusSettings.DEFAULTS)
    }

    fun dynamicKindsFor(author: DynamicCard.Author): Set<FocusDynamicFilterKind> {
        return _settings.value.perAuthorDynamicFilters[authorFilterKey(author)]
            ?: _settings.value.dynamicVisibleKinds
    }

    fun setDynamicKindEnabled(
        author: DynamicCard.Author,
        kind: FocusDynamicFilterKind,
        enabled: Boolean,
    ) {
        if (kind == FocusDynamicFilterKind.ALL) return
        update { settings ->
            val key = authorFilterKey(author)
            val current = settings.perAuthorDynamicFilters[key]
                ?: settings.dynamicVisibleKinds
            val next = if (enabled) current + kind else current - kind
            if (next.none { it != FocusDynamicFilterKind.ALL }) {
                return@update settings
            }
            settings.copy(
                perAuthorDynamicFilters = settings.perAuthorDynamicFilters + (key to next),
            )
        }
    }

    companion object {
        fun authorFilterKey(author: DynamicCard.Author): String =
            if (author.mid > 0) "mid:${author.mid}" else "name:${author.name}"
    }
}
