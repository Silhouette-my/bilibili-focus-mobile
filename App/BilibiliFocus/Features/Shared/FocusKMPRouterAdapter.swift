#if canImport(UIKit)
import FocusCore
import FocusKMP
import Foundation

enum FocusKMPRouterAdapter {
    enum SharedResult: Equatable {
        case allow
        case redirect(FocusCore.FocusEntry)
        case unmappedEntry
        case unavailable
    }

    struct Evaluation: Equatable {
        let shared: SharedResult
        let baseline: FocusCore.FocusEntry?

        var isConsistent: Bool {
            switch shared {
            case .allow:
                return baseline == nil
            case let .redirect(entry):
                return baseline == entry
            case .unmappedEntry, .unavailable:
                return false
            }
        }

        var resolvedTarget: FocusCore.FocusEntry? {
            guard isConsistent else {
                return baseline
            }

            switch shared {
            case .allow, .unmappedEntry, .unavailable:
                return nil
            case let .redirect(entry):
                return entry
            }
        }
    }

    static func redirectTarget(
        for url: URL,
        settings: FocusCore.FocusSettings
    ) -> FocusCore.FocusEntry? {
        evaluate(for: url, settings: settings).resolvedTarget
    }

    static func evaluate(
        for url: URL,
        settings: FocusCore.FocusSettings
    ) -> Evaluation {
        let baseline = FocusCore.FocusRouter(settings: settings).redirectTarget(for: url)
        return evaluate(
            sharedResult: sharedResult(for: url, settings: settings),
            baseline: baseline
        )
    }

    static func evaluate(
        sharedResult: SharedResult,
        baseline: FocusCore.FocusEntry?
    ) -> Evaluation {
        Evaluation(shared: sharedResult, baseline: baseline)
    }

    static func sharedResult(
        for url: URL,
        settings: FocusCore.FocusSettings
    ) -> SharedResult {
        guard let normalizedURL = normalizedURLString(for: url) else {
            return .unavailable
        }

        let sharedDefaultEntry: FocusKMP.FocusEntry
        switch settings.defaultEntry {
        case .dynamic:
            sharedDefaultEntry = FocusKMP.FocusEntry.dynamic
        case .search:
            sharedDefaultEntry = FocusKMP.FocusEntry.search
        }

        let router = FocusKMP.FocusRouter(
            redirectEnabled: settings.redirectEnabled,
            defaultEntry: sharedDefaultEntry
        )
        guard let entry = router.redirectTarget(url: normalizedURL) else {
            return .allow
        }

        if entry === FocusKMP.FocusEntry.dynamic {
            return .redirect(FocusCore.FocusEntry.dynamic)
        }
        if entry === FocusKMP.FocusEntry.search {
            return .redirect(FocusCore.FocusEntry.search)
        }
        return .unmappedEntry
    }

    static func normalizedURLString(for url: URL) -> String? {
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme != nil,
            components.host != nil
        else {
            return nil
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.user = nil
        components.password = nil
        components.port = nil
        components.query = nil
        components.fragment = nil
        return components.string
    }
}
#endif
