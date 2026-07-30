import Foundation

public struct BiliNetworkEvent: Equatable, Sendable {
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

public actor BiliNetworkEventStore {
    private let capacity: Int
    private var events: [BiliNetworkEvent] = []

    public init(capacity: Int = 100) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public func record(_ event: BiliNetworkEvent) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    public func snapshot() -> [BiliNetworkEvent] {
        events
    }

    public func clear() {
        events.removeAll()
    }
}

public struct BiliHTTPRetryPolicy: Equatable, Sendable {
    public let maximumAttempts: Int
    public let initialDelayMilliseconds: UInt64
    public let maximumDelayMilliseconds: UInt64

    public init(
        maximumAttempts: Int = 3,
        initialDelayMilliseconds: UInt64 = 250,
        maximumDelayMilliseconds: UInt64 = 2_000
    ) {
        precondition(maximumAttempts >= 1)
        precondition(maximumDelayMilliseconds >= initialDelayMilliseconds)
        self.maximumAttempts = maximumAttempts
        self.initialDelayMilliseconds = initialDelayMilliseconds
        self.maximumDelayMilliseconds = maximumDelayMilliseconds
    }

    public func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 408 ||
            statusCode == 425 ||
            statusCode == 429 ||
            (500 ... 599).contains(statusCode)
    }

    public func delayBeforeAttempt(_ attempt: Int) -> UInt64 {
        guard attempt > 1, initialDelayMilliseconds > 0 else {
            return 0
        }
        var delay = initialDelayMilliseconds
        if attempt > 2 {
            for _ in 3 ... attempt {
                delay = min(delay * 2, maximumDelayMilliseconds)
            }
        }
        return delay
    }
}

public struct BiliAPITransport: Sendable {
    public typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public typealias Sleeper = @Sendable (UInt64) async throws -> Void

    private let requestLoader: RequestLoader
    private let eventStore: BiliNetworkEventStore?
    private let retryPolicy: BiliHTTPRetryPolicy
    private let sleeper: Sleeper

    public init(
        requestLoader: @escaping RequestLoader = { request in
            try await URLSession.shared.data(for: request)
        },
        eventStore: BiliNetworkEventStore? = nil,
        retryPolicy: BiliHTTPRetryPolicy = BiliHTTPRetryPolicy(),
        sleeper: @escaping Sleeper = { milliseconds in
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
        }
    ) {
        self.requestLoader = requestLoader
        self.eventStore = eventStore
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let startedAt = ContinuousClock.now
        var attempt = 1
        do {
            while true {
                do {
                    let result = try await requestLoader(request)
                    let statusCode = (result.1 as? HTTPURLResponse)?.statusCode
                    if
                        isIdempotent(request),
                        attempt < retryPolicy.maximumAttempts,
                        statusCode.map(retryPolicy.shouldRetry(statusCode:)) == true
                    {
                        attempt += 1
                        try await sleeper(retryPolicy.delayBeforeAttempt(attempt))
                        continue
                    }
                    await record(
                        request: request,
                        startedAt: startedAt,
                        statusCode: statusCode,
                        responseBytes: result.0.count,
                        failureType: nil
                    )
                    return result
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard isIdempotent(request), attempt < retryPolicy.maximumAttempts else {
                        throw error
                    }
                    attempt += 1
                    try await sleeper(retryPolicy.delayBeforeAttempt(attempt))
                }
            }
        } catch {
            await record(
                request: request,
                startedAt: startedAt,
                statusCode: nil,
                responseBytes: nil,
                failureType: error is CancellationError
                    ? "cancelled"
                    : String(describing: type(of: error))
            )
            throw error
        }
    }

    public static func redactedTarget(for url: URL?) -> String {
        guard
            let url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host,
            !host.isEmpty
        else {
            return ""
        }
        components.scheme = scheme
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? "\(scheme)://\(host)\(url.path)"
    }

    private func isIdempotent(_ request: URLRequest) -> Bool {
        let method = request.httpMethod?.uppercased() ?? "GET"
        return method == "GET" || method == "HEAD"
    }

    private func record(
        request: URLRequest,
        startedAt: ContinuousClock.Instant,
        statusCode: Int?,
        responseBytes: Int?,
        failureType: String?
    ) async {
        guard let eventStore else {
            return
        }
        let duration = startedAt.duration(to: .now)
        let milliseconds = Int(duration.components.seconds * 1_000) +
            Int(duration.components.attoseconds / 1_000_000_000_000_000)
        await eventStore.record(
            BiliNetworkEvent(
                method: request.httpMethod?.uppercased() ?? "GET",
                target: Self.redactedTarget(for: request.url),
                statusCode: statusCode,
                durationMilliseconds: max(milliseconds, 0),
                responseBytes: responseBytes,
                failureType: failureType
            )
        )
    }
}

/// Process-wide production transport used by every first-party API service.
/// Tests can continue to inject a deterministic `RequestLoader`.
public enum BiliAPINetwork {
    public static let events = BiliNetworkEventStore(capacity: 200)
    private static let transport = BiliAPITransport(eventStore: events)

    public static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await transport.data(for: request)
    }
}
