#if canImport(UIKit)
import Foundation
import WebKit

struct PlayerSnapshot: Equatable, Sendable {
    var hasPlayer: Bool
    var isPlaying: Bool
    var playbackRate: Double
    var isDanmakuHidden: Bool
    var hasSubtitles: Bool
    var isSubtitleHidden: Bool
    var isFullscreen: Bool

    static let empty = PlayerSnapshot(
        hasPlayer: false,
        isPlaying: false,
        playbackRate: 1,
        isDanmakuHidden: false,
        hasSubtitles: false,
        isSubtitleHidden: false,
        isFullscreen: false
    )
}

struct BrowserSessionID: Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    var stringValue: String {
        rawValue.uuidString.lowercased()
    }
}

struct NavigationRevision: Equatable, Hashable, Sendable {
    let rawValue: UInt64
}

struct BrowserCallbackStamp: Equatable {
    let sessionID: BrowserSessionID
    let revision: NavigationRevision
    let canonicalURL: URL
    let webViewIdentifier: ObjectIdentifier
}

enum BrowserCallbackGate {
    static func accepts(_ callback: BrowserCallbackStamp, current: BrowserCallbackStamp) -> Bool {
        callback == current
    }
}

enum WebContentRecoveryDecision: Equatable {
    case inactive
    case recover(URL)
    case showRetry(String)
}

enum WebContentRecoveryPolicy {
    static let automaticAttemptLimit = 1

    static func decision(
        isSessionActive: Bool,
        attempts: Int,
        recoveryURL: URL?
    ) -> WebContentRecoveryDecision {
        guard isSessionActive else {
            return .inactive
        }
        guard attempts < automaticAttemptLimit else {
            return .showRetry("网页进程已停止，点重试重新加载当前页面。")
        }
        guard let recoveryURL else {
            return .showRetry("网页进程已停止，且没有可恢复的页面地址。")
        }
        return .recover(recoveryURL)
    }
}
#endif

