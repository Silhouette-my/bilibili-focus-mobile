import Foundation

public struct FocusNavigationPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case allow
        case cancel
        case redirect(URL)
    }

    private static let blockedSchemes: Set<String> = [
        "bilibili",
        "bilibilihd",
        "bstar",
        "intent",
        "itms-apps",
        "itmss",
    ]
    private static let blockedHosts: Set<String> = [
        "app.bilibili.com",
    ]

    public init(settings _: FocusSettings = .defaults) {}

    public func decision(for url: URL, currentURL: URL? = nil) -> Decision {
        let canonicalURL = Self.canonicalWebURL(for: url)
        if canonicalURL != url {
            return .redirect(canonicalURL)
        }

        if shouldBlock(url: canonicalURL, currentURL: currentURL) {
            return .cancel
        }

        return .allow
    }

    public static func canonicalWebURL(for url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let host = components?.host?.lowercased() else {
            return url
        }

        let path = url.path.lowercased()
        let isStandardBilibiliHost = host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com"

        if isStandardBilibiliHost && (path.hasPrefix("/video/") || path.hasPrefix("/bangumi/play/")) {
            components?.scheme = "https"
            components?.host = "www.bilibili.com"
            if path.hasPrefix("/video/"), components?.path.hasSuffix("/") == false {
                components?.path += "/"
            }
            if path.hasPrefix("/video/") {
                let filteredItems = filteredVideoQueryItems(from: components?.queryItems)
                components?.queryItems = filteredItems
            }
            return components?.url ?? url
        }

        if isStandardBilibiliHost && (path.hasPrefix("/blackboard/html5player.html") || path.hasPrefix("/blackboard/html5mobileplayer.html")) {
            if let videoPath = canonicalVideoPath(from: components) {
                let filteredItems = filteredVideoQueryItems(from: components?.queryItems)
                components?.scheme = "https"
                components?.host = "www.bilibili.com"
                components?.path = videoPath
                components?.queryItems = filteredItems
                components?.fragment = nil
                if components?.path.hasPrefix("/video/") == true, components?.path.hasSuffix("/") == false {
                    components?.path += "/"
                }
                return components?.url ?? url
            }
        }

        if isStandardBilibiliHost && path.hasPrefix("/opus/") {
            components?.host = "www.bilibili.com"
            return components?.url ?? url
        }

        if host == "t.bilibili.com" {
            let pathComponents = url.path.split(separator: "/")
            if pathComponents.count == 1, pathComponents[0].allSatisfy(\.isNumber) {
                components?.scheme = "https"
                components?.host = "www.bilibili.com"
                components?.path = "/opus/\(pathComponents[0])"
                return components?.url ?? url
            }
        }

        if host == "live.bilibili.com", let roomID = canonicalLiveRoomID(from: components) {
            components?.scheme = "https"
            components?.host = "live.bilibili.com"
            components?.path = "/\(roomID)"
            components?.queryItems = nil
            components?.fragment = nil
            return components?.url ?? url
        }

        return url
    }

    private func shouldBlock(url: URL, currentURL: URL?) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if Self.blockedSchemes.contains(scheme) {
            return true
        }

        let host = url.host?.lowercased() ?? ""
        if Self.blockedHosts.contains(host) {
            return true
        }

        let lowercasedPath = url.path.lowercased()
        let lowercasedURL = url.absoluteString.lowercased()
        let isBilibiliFamilyHost = Self.isHost(host, within: "bilibili.com")
            || Self.isHost(host, within: "hdslb.com")
        let cameFromVideoPage = currentURL?.path.hasPrefix("/video/") == true
            || Self.isHost(currentURL?.host?.lowercased() ?? "", within: "bilibili.com")
                && currentURL?.absoluteString.contains("/video/") == true

        if isBilibiliFamilyHost && lowercasedPath.contains("/download") {
            return true
        }

        if lowercasedURL.contains("openapp") || lowercasedURL.contains("launchapp") {
            return true
        }

        if cameFromVideoPage && isBilibiliFamilyHost && lowercasedURL.contains("download") {
            return true
        }

        return false
    }

    private static func isHost(_ host: String, within domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }

    private static func canonicalVideoPath(from components: URLComponents?) -> String? {
        guard let queryItems = components?.queryItems else {
            return nil
        }

        if let bvid = queryItems.first(where: { $0.name.caseInsensitiveCompare("bvid") == .orderedSame })?.value,
           !bvid.isEmpty
        {
            return "/video/\(bvid)"
        }

        if let aid = queryItems.first(where: { $0.name.caseInsensitiveCompare("aid") == .orderedSame || $0.name.caseInsensitiveCompare("avid") == .orderedSame })?.value,
           !aid.isEmpty
        {
            return "/video/av\(aid)"
        }

        return nil
    }

    private static func filteredVideoQueryItems(from items: [URLQueryItem]?) -> [URLQueryItem]? {
        let preservedNames: Set<String> = [
            "p",
            "cid",
            "t",
            "start_progress",
            "start_progress_ms",
            "spm_id_from",
            "from_spmid",
            "from_source",
        ]

        let filtered = (items ?? []).filter { preservedNames.contains($0.name.lowercased()) }
        return filtered.isEmpty ? nil : filtered
    }

    private static func canonicalLiveRoomID(from components: URLComponents?) -> String? {
        let pathComponents = (components?.path ?? "")
            .split(separator: "/")
            .map(String.init)

        if let numericPathComponent = pathComponents.reversed().first(where: { !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return numericPathComponent
        }

        let queryItems = components?.queryItems ?? []
        let liveRoomKeys: Set<String> = [
            "room_id",
            "roomid",
            "id",
        ]

        return queryItems.first(where: { liveRoomKeys.contains($0.name.lowercased()) })?.value
            .flatMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
    }
}
