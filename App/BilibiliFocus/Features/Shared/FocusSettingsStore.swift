#if canImport(UIKit)
import Combine
import FocusCore
import Foundation

@MainActor
final class FocusSettingsStore: ObservableObject {
    @Published var settings: FocusSettings {
        didSet {
            settings.save(to: userDefaults)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.settings = FocusSettings.load(from: userDefaults)
    }

    func reset() {
        settings = .defaults
    }

    func dynamicKinds(for author: DynamicCard.Author) -> Set<FocusDynamicFilterKind> {
        let key = authorFilterKey(for: author)
        return settings.perAuthorDynamicFilters[key] ?? Set(FocusDynamicFilterKind.allCases)
    }

    func setDynamicKinds(_ kinds: Set<FocusDynamicFilterKind>, for author: DynamicCard.Author) {
        let key = authorFilterKey(for: author)
        settings.perAuthorDynamicFilters[key] = kinds
    }

    func authorFilterKey(for author: DynamicCard.Author) -> String {
        author.mid > 0 ? "mid:\(author.mid)" : "name:\(author.name)"
    }
}
#endif
