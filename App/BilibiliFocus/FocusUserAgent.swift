#if canImport(UIKit)
import UIKit

enum FocusUserAgent {
    @MainActor
    static func mobileSafari() -> String {
        let idiom = UIDevice.current.userInterfaceIdiom
        let deviceName = idiom == .pad ? "iPad" : "iPhone"
        let versionString = UIDevice.current.systemVersion
        let osToken = versionString.replacingOccurrences(of: ".", with: "_")
        let majorVersion = versionString.split(separator: ".").first.map(String.init) ?? "18"

        return """
        Mozilla/5.0 (\(deviceName); CPU \(deviceName) OS \(osToken) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(majorVersion).0 Mobile/15E148 Safari/604.1
        """
    }

    static func desktopSafari() -> String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    }

    static func shouldUseDesktopMode(for url: URL) -> Bool {
        if shouldUseDesktopPlayback(for: url) {
            return true
        }

        if shouldUseDesktopDynamicDetail(for: url) {
            return true
        }

        if shouldUseDesktopLiveRoom(for: url) {
            return true
        }

        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "search.bilibili.com"
    }

    static func shouldUseDesktopPlayback(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        let isBilibiliHost = host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com"
        guard isBilibiliHost else {
            return false
        }

        let path = url.path.lowercased()
        if path.hasPrefix("/video/") || path.hasPrefix("/bangumi/play/") {
            return true
        }

        if path.hasPrefix("/blackboard/html5player.html") || path.hasPrefix("/blackboard/html5mobileplayer.html") {
            return true
        }

        return false
    }

    private static func shouldUseDesktopDynamicDetail(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        let path = url.path.lowercased()
        let pathComponents = path.split(separator: "/")
        let isNumericDynamicPath = host == "t.bilibili.com"
            && pathComponents.count == 1
            && pathComponents[0].allSatisfy(\.isNumber)
        let isOpusPath = (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com")
            && path.hasPrefix("/opus/")

        return isNumericDynamicPath || isOpusPath
    }

    private static func shouldUseDesktopLiveRoom(for url: URL) -> Bool {
        guard let host = url.host?.lowercased(), host == "live.bilibili.com" else {
            return false
        }

        let pathComponents = url.path.split(separator: "/")
        if pathComponents.contains(where: { !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return true
        }

        let query = url.query?.lowercased() ?? ""
        return query.contains("room_id=") || query.contains("roomid=")
    }
}
#endif
