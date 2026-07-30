import Foundation

public struct BiliDiagnosticEvent: Codable, Equatable, Sendable {
    public let method: String
    public let target: String
    public let statusCode: Int?
    public let durationMilliseconds: Int
    public let responseBytes: Int?
    public let failureType: String?

    public init(
        method: String,
        target: String,
        statusCode: Int?,
        durationMilliseconds: Int,
        responseBytes: Int?,
        failureType: String?
    ) {
        self.method = method
        self.target = target
        self.statusCode = statusCode
        self.durationMilliseconds = durationMilliseconds
        self.responseBytes = responseBytes
        self.failureType = failureType
    }
}

public struct BiliDiagnosticSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let loginHealth: LoginHealth
    public let events: [BiliDiagnosticEvent]

    public init(
        schemaVersion: Int = 1,
        loginHealth: LoginHealth,
        events: [BiliDiagnosticEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.loginHealth = loginHealth
        self.events = events
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
        eventStore: BiliNetworkEventStore = BiliAPINetwork.events
    ) async -> BiliDiagnosticSnapshot {
        let events = await eventStore.snapshot().map(sanitize)
        return BiliDiagnosticSnapshot(loginHealth: loginHealth, events: events)
    }

    private static func sanitize(_ event: BiliNetworkEvent) -> BiliDiagnosticEvent {
        BiliDiagnosticEvent(
            method: sanitizedMethod(event.method),
            target: BiliAPITransport.redactedTarget(for: URL(string: event.target)),
            statusCode: event.statusCode.flatMap { (100 ... 599).contains($0) ? $0 : nil },
            durationMilliseconds: max(event.durationMilliseconds, 0),
            responseBytes: event.responseBytes.map { max($0, 0) },
            failureType: sanitizedFailureType(event.failureType)
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
