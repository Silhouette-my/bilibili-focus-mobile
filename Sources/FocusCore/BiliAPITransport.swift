import Foundation

public struct BiliNetworkEvent: Equatable, Sendable {
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
        self.attemptCount = attemptCount
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
        requestLoader: RequestLoader? = nil,
        eventStore: BiliNetworkEventStore? = nil,
        retryPolicy: BiliHTTPRetryPolicy = BiliHTTPRetryPolicy(),
        sleeper: @escaping Sleeper = { milliseconds in
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
        }
    ) {
        self.requestLoader = requestLoader ?? { request in
            // Test doubles opt in explicitly through RequestLoader. Never let
            // an accidentally constructed app service reach a real account.
            if ProcessInfo.processInfo.environment["FOCUS_FIXTURE_TESTS"] == "1" {
                throw URLError(.notConnectedToInternet)
            }
            return try await BiliNativeHTTPSession.shared.data(for: request)
        }
        self.eventStore = eventStore
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let startedAt = ContinuousClock.now
        var attempt = 1
        var attemptsStarted = 0
        do {
            while true {
                try Task.checkCancellation()
                do {
                    attemptsStarted += 1
                    let result = try await requestLoader(request)
                    try Task.checkCancellation()
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
                        failureType: nil,
                        attemptCount: attemptsStarted
                    )
                    return result
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if let urlError = error as? URLError {
                        if urlError.code == .cancelled { throw CancellationError() }
                        let terminal: Set<URLError.Code> = [
                            .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed,
                            .secureConnectionFailed, .serverCertificateUntrusted,
                            .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                            .serverCertificateNotYetValid, .userAuthenticationRequired,
                            .badURL, .unsupportedURL
                        ]
                        if terminal.contains(urlError.code) { throw error }
                    }
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
                    : String(describing: type(of: error)),
                attemptCount: attemptsStarted
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
        failureType: String?,
        attemptCount: Int
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
                failureType: failureType,
                attemptCount: attemptCount
            )
        )
    }
}

/// Native API requests carry an explicit WebKit snapshot. URLSession must not
/// silently add a second credential source or persist response Set-Cookie.
private enum BiliNativeHTTPSession {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration, delegate: BiliNativeRedirectPolicy(), delegateQueue: nil)
    }()
}

final class BiliNativeRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    static func permitsRedirect(original: URLRequest?, destination: URL) -> Bool {
        guard let original, let source = original.url,
              source.scheme?.lowercased() == "https", destination.scheme?.lowercased() == "https",
              source.host?.lowercased() == destination.host?.lowercased(),
              (source.port ?? 443) == (destination.port ?? 443),
              original.value(forHTTPHeaderField: "Cookie") == nil,
              original.value(forHTTPHeaderField: "Authorization") == nil else { return false }
        return true
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url, Self.permitsRedirect(original: task.originalRequest, destination: url) else {
            completionHandler(nil)
            return
        }
        var redirected = request
        redirected.httpShouldHandleCookies = false
        redirected.setValue(nil, forHTTPHeaderField: "Cookie")
        redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(redirected)
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
