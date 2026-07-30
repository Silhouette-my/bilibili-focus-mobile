import Foundation

public struct FocusSettings: Codable, Equatable, Sendable {
    public static let storageKey = "focus.settings"
    public static let defaultAccentColorHex = "#FB7299"
    public static let defaults = FocusSettings()

    public var redirectEnabled: Bool
    public var playerMaskEnabled: Bool
    public var nativeDanmakuEnabled: Bool
    public var nativeSubtitleEnabled: Bool
    public var nativeSubtitleLanguageCode: String
    public var searchMaskEnabled: Bool
    public var dynamicMaskEnabled: Bool
    public var debugMode: Bool
    public var defaultEntry: FocusEntry
    public var themeMode: FocusThemeMode
    public var accentColorHex: String
    public var dynamicVisibleKinds: Set<FocusDynamicFilterKind>
    public var perAuthorDynamicFilters: [String: Set<FocusDynamicFilterKind>]

    public init(
        redirectEnabled: Bool = true,
        playerMaskEnabled: Bool = true,
        nativeDanmakuEnabled: Bool = true,
        nativeSubtitleEnabled: Bool = true,
        nativeSubtitleLanguageCode: String = "",
        searchMaskEnabled: Bool = true,
        dynamicMaskEnabled: Bool = true,
        debugMode: Bool = false,
        defaultEntry: FocusEntry = .dynamic,
        themeMode: FocusThemeMode = .system,
        accentColorHex: String = FocusSettings.defaultAccentColorHex,
        dynamicVisibleKinds: Set<FocusDynamicFilterKind> = Set(FocusDynamicFilterKind.allCases),
        perAuthorDynamicFilters: [String: Set<FocusDynamicFilterKind>] = [:]
    ) {
        self.redirectEnabled = redirectEnabled
        self.playerMaskEnabled = playerMaskEnabled
        self.nativeDanmakuEnabled = nativeDanmakuEnabled
        self.nativeSubtitleEnabled = nativeSubtitleEnabled
        self.nativeSubtitleLanguageCode = nativeSubtitleLanguageCode
        self.searchMaskEnabled = searchMaskEnabled
        self.dynamicMaskEnabled = dynamicMaskEnabled
        self.debugMode = debugMode
        self.defaultEntry = defaultEntry
        self.themeMode = themeMode
        self.accentColorHex = Self.normalizedAccentColorHex(accentColorHex)
            ?? Self.defaultAccentColorHex
        self.dynamicVisibleKinds = dynamicVisibleKinds
        self.perAuthorDynamicFilters = perAuthorDynamicFilters
    }

    private enum CodingKeys: String, CodingKey {
        case redirectEnabled
        case playerMaskEnabled
        case nativeDanmakuEnabled
        case nativeSubtitleEnabled
        case nativeSubtitleLanguageCode
        case searchMaskEnabled
        case dynamicMaskEnabled
        case debugMode
        case defaultEntry
        case themeMode
        case accentColorHex
        case dynamicVisibleKinds
        case perAuthorDynamicFilters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        redirectEnabled = try container.decodeIfPresent(Bool.self, forKey: .redirectEnabled) ?? true
        playerMaskEnabled = try container.decodeIfPresent(Bool.self, forKey: .playerMaskEnabled) ?? true
        nativeDanmakuEnabled = try container.decodeIfPresent(Bool.self, forKey: .nativeDanmakuEnabled) ?? true
        nativeSubtitleEnabled = try container.decodeIfPresent(Bool.self, forKey: .nativeSubtitleEnabled) ?? true
        nativeSubtitleLanguageCode = try container.decodeIfPresent(
            String.self,
            forKey: .nativeSubtitleLanguageCode
        ) ?? ""
        searchMaskEnabled = try container.decodeIfPresent(Bool.self, forKey: .searchMaskEnabled) ?? true
        dynamicMaskEnabled = try container.decodeIfPresent(Bool.self, forKey: .dynamicMaskEnabled) ?? true
        debugMode = try container.decodeIfPresent(Bool.self, forKey: .debugMode) ?? false
        defaultEntry = try container.decodeIfPresent(FocusEntry.self, forKey: .defaultEntry) ?? .dynamic
        themeMode = try container.decodeIfPresent(FocusThemeMode.self, forKey: .themeMode) ?? .system
        accentColorHex = Self.normalizedAccentColorHex(
            try container.decodeIfPresent(String.self, forKey: .accentColorHex)
                ?? Self.defaultAccentColorHex
        ) ?? Self.defaultAccentColorHex
        dynamicVisibleKinds = try container.decodeIfPresent(
            Set<FocusDynamicFilterKind>.self,
            forKey: .dynamicVisibleKinds
        ) ?? Set(FocusDynamicFilterKind.allCases)
        perAuthorDynamicFilters = try container.decodeIfPresent(
            [String: Set<FocusDynamicFilterKind>].self,
            forKey: .perAuthorDynamicFilters
        ) ?? [:]
    }

    public static func normalizedAccentColorHex(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6, UInt32(digits, radix: 16) != nil else {
            return nil
        }
        return "#\(digits.uppercased())"
    }

    public var debugLoggingEnabledForCurrentBuild: Bool {
#if DEBUG
        debugMode
#else
        false
#endif
    }

    public var effectiveRuntimeSettings: FocusSettings {
        var settings = self
        settings.debugMode = debugLoggingEnabledForCurrentBuild
        return settings
    }

    public static func load(from userDefaults: UserDefaults) -> FocusSettings {
        guard
            let data = userDefaults.data(forKey: storageKey),
            let settings = try? JSONDecoder().decode(FocusSettings.self, from: data)
        else {
            return .defaults
        }

        return settings
    }

    public func save(to userDefaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }

        userDefaults.set(data, forKey: Self.storageKey)
    }
}

public enum FocusDynamicFilterKind: String, Codable, CaseIterable, Hashable, Sendable {
    case all
    case video
    case articleLike

    public var title: String {
        switch self {
        case .all:
            return "综合"
        case .video:
            return "视频"
        case .articleLike:
            return "图文"
        }
    }
}

public enum FocusThemeMode: String, Codable, CaseIterable, Hashable, Sendable {
    case system
    case light
    case dark

    public var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }
}
