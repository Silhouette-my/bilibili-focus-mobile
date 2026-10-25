import Foundation

/// Closed vocabulary: no URL, account identifier, cookie, response body or arbitrary text.
public enum BiliPerformanceStage: String, Codable, Sendable {
    case sessionInitialization, cookieSnapshot
    case dynamicLoad, dynamicFirstPage, dynamicDisplayed
    case myProfile, myFollowing, myHistory, myFavorites, myWatchLater, favoritePreviews
    case videoStartup, videoDetail, playbackURL, resumeLookup, mediaPreparation, playerReady, firstFrame
    case scrollRestore, layoutCompensation
    case scrollReturn, normalReturnPreserved, layoutChanged
    case anchorMaterializationRequested, anchorResolved, anchorMissing, preciseAlignment
    case restorationFallback, restorationCancelledByGesture, visiblePositionError
    case restorationScopeChanged, restorationClamped
}

public enum BiliPerformanceOutcome: String, Codable, Sendable {
    case success, failure, cancelled, timedOut, stale, fallback
}

public struct BiliPerformanceSpan: Sendable {
    fileprivate let id: UUID
    fileprivate let correlationID: UUID
    fileprivate let stage: BiliPerformanceStage
    fileprivate let startedAt: UInt64
}

public struct BiliPerformanceEvent: Codable, Equatable, Sendable {
    public let id: UUID
    public let correlationID: UUID
    public let stage: BiliPerformanceStage
    public let outcome: BiliPerformanceOutcome
    public let durationMilliseconds: Double
    public let count: Int
    public let positionErrorPoints: Double?
}

/// Bounded in-memory local diagnostics. Callers own spans, so abandoned work
/// cannot grow an active-span dictionary. Monotonic time ignores clock changes.
public final class BiliPerformanceStore: @unchecked Sendable {
    public static let shared = BiliPerformanceStore()
    private let lock = NSLock()
    private let capacity: Int
    private let now: @Sendable () -> UInt64
    private var events: [BiliPerformanceEvent] = []

    public init(
        capacity: Int = 256,
        now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        precondition(capacity > 0)
        self.capacity = min(capacity, 4_096)
        self.now = now
    }

    public func begin(
        _ stage: BiliPerformanceStage,
        correlationID: UUID = UUID()
    ) -> BiliPerformanceSpan {
        BiliPerformanceSpan(id: UUID(), correlationID: correlationID, stage: stage, startedAt: now())
    }

    public func end(
        _ span: BiliPerformanceSpan,
        outcome: BiliPerformanceOutcome = .success,
        count: Int = 0,
        positionErrorPoints: Double? = nil
    ) {
        let finishedAt = now()
        let duration = finishedAt >= span.startedAt ? Double(finishedAt - span.startedAt) / 1_000_000 : 0
        let event = BiliPerformanceEvent(
            id: span.id, correlationID: span.correlationID, stage: span.stage,
            outcome: outcome, durationMilliseconds: duration,
            count: max(0, min(count, 1_000_000)),
            positionErrorPoints: positionErrorPoints.flatMap { $0.isFinite ? $0 : nil }
        )
        lock.lock()
        defer { lock.unlock() }
        guard !events.contains(where: { $0.id == span.id }) else { return }
        events.append(event)
        if events.count > capacity { events.removeFirst(events.count - capacity) }
    }

    public func snapshot() -> [BiliPerformanceEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        events.removeAll(keepingCapacity: true)
    }
}

public struct BiliDiagnosticEvent: Codable, Equatable, Sendable {
    public let method: String
    public let target: String
    public let statusCode: Int?
    public let durationMilliseconds: Int
    public let responseBytes: Int?
    public let failureType: String?
    public let attemptCount: Int

    public init(
        method: String,
        target: String,
        statusCode: Int?,
        durationMilliseconds: Int,
        responseBytes: Int?,
        failureType: String?,
        attemptCount: Int = 1
    ) {
        self.method = method
        self.target = target
        self.statusCode = statusCode
        self.durationMilliseconds = durationMilliseconds
        self.responseBytes = responseBytes
        self.failureType = failureType
        self.attemptCount = max(0, attemptCount)
    }
}

public struct BiliDiagnosticSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let loginHealth: LoginHealth
    public let events: [BiliDiagnosticEvent]
    public let performanceEvents: [BiliPerformanceEvent]

    public init(
        schemaVersion: Int = 2,
        loginHealth: LoginHealth,
        events: [BiliDiagnosticEvent],
        performanceEvents: [BiliPerformanceEvent] = []
    ) {
        self.schemaVersion = schemaVersion
        self.loginHealth = loginHealth
        self.events = events
        self.performanceEvents = performanceEvents
    }

    public func jsonData(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// Builds an exportable snapshot from the local ring buffer.
///
/// Events are sanitized again even though the production transport already
/// redacts them. The second boundary protects exports if a test double or a
/// future transport records an unsafe value directly.
public enum BiliDiagnostics {
    public static func snapshot(
        loginHealth: LoginHealth,
        eventStore: BiliNetworkEventStore = BiliAPINetwork.events,
        performanceStore: BiliPerformanceStore = .shared
    ) async -> BiliDiagnosticSnapshot {
        let events = await eventStore.snapshot().map(sanitize)
        return BiliDiagnosticSnapshot(
            loginHealth: loginHealth, events: events,
            performanceEvents: performanceStore.snapshot()
        )
    }

    private static func sanitize(_ event: BiliNetworkEvent) -> BiliDiagnosticEvent {
        BiliDiagnosticEvent(
            method: sanitizedMethod(event.method),
            target: BiliAPITransport.redactedTarget(for: URL(string: event.target)),
            statusCode: event.statusCode.flatMap { (100 ... 599).contains($0) ? $0 : nil },
            durationMilliseconds: max(event.durationMilliseconds, 0),
            responseBytes: event.responseBytes.map { max($0, 0) },
            failureType: sanitizedFailureType(event.failureType),
            attemptCount: event.attemptCount
        )
    }

    private static func sanitizedMethod(_ method: String) -> String {
        let normalized = method.uppercased()
        return ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"].contains(normalized)
            ? normalized
            : "OTHER"
    }

    private static func sanitizedFailureType(_ failureType: String?) -> String? {
        guard let failureType else {
            return nil
        }
        let normalized = failureType.lowercased()
        if normalized.contains("cancel") {
            return "cancelled"
        }
        if normalized.contains("timeout") || normalized.contains("timedout") {
            return "timeout"
        }
        if
            normalized.contains("url") ||
            normalized.contains("network") ||
            normalized.contains("socket") ||
            normalized.contains("connect") ||
            normalized.contains("host") ||
            normalized.contains("dns") ||
            normalized.contains("io")
        {
            return "network_unavailable"
        }
        return "transport_error"
    }
}
