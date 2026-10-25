import Foundation

public enum CookieRequestPolicy {
    public static func cookies(
        _ cookies: [HTTPCookie],
        matching url: URL,
        now: Date = Date()
    ) -> [HTTPCookie] {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let requestHost = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            !requestHost.isEmpty
        else {
            return []
        }

        let requestPath = url.path.isEmpty ? "/" : url.path
        return cookies.enumerated()
            .filter { _, cookie in
                !cookie.name.isEmpty
                    && (cookie.expiresDate.map { $0 > now } ?? true)
                    && (!cookie.isSecure || scheme == "https")
                    && domainMatches(cookie: cookie, requestHost: requestHost)
                    && pathMatches(cookiePath: cookie.path, requestPath: requestPath)
            }
            .sorted { lhs, rhs in
                let lhsLength = normalizedCookiePath(lhs.element.path).count
                let rhsLength = normalizedCookiePath(rhs.element.path).count
                return lhsLength == rhsLength ? lhs.offset < rhs.offset : lhsLength > rhsLength
            }
            .map(\.element)
    }

    public static func cookieHeader(
        cookies: [HTTPCookie],
        for url: URL,
        now: Date = Date()
    ) -> String? {
        let value = self.cookies(cookies, matching: url, now: now)
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        return value.isEmpty ? nil : value
    }

    public static func headerFields(
        cookies: [HTTPCookie],
        for url: URL,
        now: Date = Date()
    ) -> [String: String] {
        guard let cookieHeader = cookieHeader(cookies: cookies, for: url, now: now) else {
            return [:]
        }
        return ["Cookie": cookieHeader]
    }

    public static func attach(
        cookies: [HTTPCookie],
        to request: URLRequest,
        now: Date = Date()
    ) -> URLRequest {
        var updatedRequest = request
        updatedRequest.setValue(nil, forHTTPHeaderField: "Cookie")
        guard
            let url = request.url,
            let cookieHeader = cookieHeader(cookies: cookies, for: url, now: now)
        else {
            return updatedRequest
        }
        updatedRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        return updatedRequest
    }

    private static func domainMatches(cookie: HTTPCookie, requestHost: String) -> Bool {
        let rawDomain = cookie.domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let domain = rawDomain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !domain.isEmpty else {
            return false
        }
        if requestHost == domain {
            return true
        }
        let isHostOnly = !rawDomain.hasPrefix(".")
        return !isHostOnly && requestHost.hasSuffix(".\(domain)")
    }

    private static func pathMatches(cookiePath rawCookiePath: String, requestPath: String) -> Bool {
        let cookiePath = normalizedCookiePath(rawCookiePath)
        if requestPath == cookiePath {
            return true
        }
        guard requestPath.hasPrefix(cookiePath) else {
            return false
        }
        if cookiePath.hasSuffix("/") {
            return true
        }
        let boundary = requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)
        return boundary < requestPath.endIndex && requestPath[boundary] == "/"
    }

    private static func normalizedCookiePath(_ path: String) -> String {
        path.hasPrefix("/") ? path : "/"
    }
}

public enum CookieSessionReadiness: String, Sendable {
    case restoring, unconfirmed, anonymous, authenticated, expired
}

/// Immutable cookies and generation travel together, preventing a read/version
/// race from attaching the old account's cookies under the new generation.
public struct CookieSessionSnapshot: Sendable {
    public let cookies: [HTTPCookie]
    public let version: UInt64
    public let readiness: CookieSessionReadiness
    public init(cookies: [HTTPCookie], version: UInt64, readiness: CookieSessionReadiness) {
        self.cookies = cookies; self.version = version; self.readiness = readiness
    }
}

public struct CookieSessionTransition: Sendable {
    public let version: UInt64
    public let readiness: CookieSessionReadiness
    public let requiresAccountReset: Bool
}

public protocol CookieSnapshotProvider: Sendable {
    var sessionVersion: UInt64 { get }
    var sessionReadiness: CookieSessionReadiness { get }
    func loadCookies() async -> [HTTPCookie]
    func loadSnapshot() async -> CookieSessionSnapshot
    func noteServerSessionExpired(version: UInt64)
    func attachCookies(to request: URLRequest) -> URLRequest
}

public extension CookieSnapshotProvider {
    var sessionVersion: UInt64 { 0 }
    var sessionReadiness: CookieSessionReadiness { .unconfirmed }
    func noteServerSessionExpired(version: UInt64) {}
    func loadSnapshot() async -> CookieSessionSnapshot {
        let version = sessionVersion
        let cookies = await loadCookies()
        guard version == sessionVersion else {
            return CookieSessionSnapshot(cookies: [], version: version, readiness: .unconfirmed)
        }
        return CookieSessionSnapshot(cookies: cookies, version: version, readiness: sessionReadiness)
    }
    func attachCookies(to request: URLRequest) -> URLRequest { request }
}

/// WebKit supplies the reader in production; tests inject deterministic gates.
/// No native cookie jar, credential persistence or response-cookie writeback.
public final class CookieSessionCoordinator: CookieSnapshotProvider, @unchecked Sendable {
    public typealias Reader = @Sendable () async throws -> [HTTPCookie]
    public typealias Sleeper = @Sendable (UInt64) async throws -> Void
    private struct Pending {
        let id: UUID
        let version: UInt64
        let task: Task<ReadResult, Never>
    }
    private enum ReadResult: Sendable {
        case cookies([HTTPCookie]), failed, cancelled
    }
    private let lock = NSLock()
    private let reader: Reader
    private let sleeper: Sleeper
    private let warmupDelays: [UInt64]
    private var version: UInt64 = 0
    private var readiness: CookieSessionReadiness = .restoring
    private var cookies: [HTTPCookie] = []
    private var pending: Pending?
    private var warmupStarted = false
    private var lastCredentialFingerprint: Int?
    private var rejectedCredentialFingerprint: Int?
    private var transitionHandler: (@Sendable (CookieSessionTransition) -> Void)?

    public init(
        reader: @escaping Reader,
        warmupDelays: [UInt64] = [180_000_000, 350_000_000, 700_000_000, 1_100_000_000],
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.reader = reader; self.warmupDelays = Array(warmupDelays.prefix(4)); self.sleeper = sleeper
    }

    deinit { pending?.task.cancel() }
    public var sessionVersion: UInt64 { lock.withLock { version } }
    public var sessionReadiness: CookieSessionReadiness { lock.withLock { readiness } }

    public func setTransitionHandler(_ handler: @escaping @Sendable (CookieSessionTransition) -> Void) {
        lock.withLock { transitionHandler = handler }
    }

    /// Every store mutation fences old asynchronous work immediately. Loaded UI
    /// is discarded only after a credential change is confirmed, not for a
    /// harmless tracking-cookie notification or a temporary read failure.
    public func invalidate() {
        let transition: CookieSessionTransition = lock.withLock {
            version &+= 1
            pending?.task.cancel(); pending = nil
            cookies.removeAll()
            readiness = .unconfirmed
            return CookieSessionTransition(version: version, readiness: readiness, requiresAccountReset: false)
        }
        publish(transition)
    }

    public func noteServerSessionExpired(version expected: UInt64) {
        let transition: CookieSessionTransition? = lock.withLock {
            guard version == expected, readiness != .expired else { return nil }
            rejectedCredentialFingerprint = lastCredentialFingerprint
            version &+= 1
            pending?.task.cancel(); pending = nil
            cookies.removeAll()
            readiness = .expired
            return CookieSessionTransition(version: version, readiness: readiness, requiresAccountReset: true)
        }
        if let transition { publish(transition) }
    }

    public func loadCookies() async -> [HTTPCookie] { await loadSnapshot().cookies }

    public func loadSnapshot() async -> CookieSessionSnapshot {
        expireIfNecessary()
        let (cached, request): (CookieSessionSnapshot?, Pending?) = lock.withLock {
            if readiness == .authenticated || readiness == .anonymous || readiness == .expired {
                return (snapshotLocked(), nil)
            }
            if let pending { return (nil, pending) }
            let id = UUID()
            let capturedVersion = version
            let delays = warmupStarted ? [] : warmupDelays
            warmupStarted = true
            let task = Task { [reader, sleeper] in
                let phase = BiliPerformanceStore.shared.begin(.sessionInitialization, correlationID: id)
                do {
                    var value: [HTTPCookie] = []
                    for index in 0...delays.count {
                        try Task.checkCancellation()
                        if index > 0 { try await sleeper(delays[index - 1]) }
                        let read = BiliPerformanceStore.shared.begin(.cookieSnapshot, correlationID: id)
                        do {
                            value = try await reader()
                            try Task.checkCancellation()
                            BiliPerformanceStore.shared.end(read)
                        } catch {
                            BiliPerformanceStore.shared.end(read, outcome: error is CancellationError ? .cancelled : .failure)
                            throw error
                        }
                        if Self.hasUsableSession(value) { break }
                    }
                    BiliPerformanceStore.shared.end(phase)
                    return ReadResult.cookies(value)
                } catch is CancellationError {
                    BiliPerformanceStore.shared.end(phase, outcome: .cancelled)
                    return ReadResult.cancelled
                } catch {
                    BiliPerformanceStore.shared.end(phase, outcome: .failure)
                    return ReadResult.failed
                }
            }
            let request = Pending(id: id, version: capturedVersion, task: task)
            pending = request
            return (nil, request)
        }
        if let cached { return cached }
        guard let request else { return CookieSessionSnapshot(cookies: [], version: sessionVersion, readiness: .unconfirmed) }
        let result = await request.task.value
        var transition: CookieSessionTransition?
        let snapshot: CookieSessionSnapshot = lock.withLock {
            guard version == request.version else {
                return CookieSessionSnapshot(cookies: [], version: request.version, readiness: .unconfirmed)
            }
            if pending?.id == request.id {
                pending = nil
                switch result {
                case let .cookies(value):
                    let fingerprint = Self.credentialFingerprint(value)
                    let changed = lastCredentialFingerprint.map { $0 != fingerprint } ?? false
                    let usable = Self.hasUsableSession(value)
                    readiness = usable ? .authenticated : .anonymous
                    if fingerprint == rejectedCredentialFingerprint { readiness = .expired }
                    cookies = readiness == .expired ? [] : value.filter { $0.expiresDate.map { $0 > Date() } ?? true }
                    lastCredentialFingerprint = fingerprint
                    transition = CookieSessionTransition(version: version, readiness: readiness, requiresAccountReset: changed)
                case .failed, .cancelled:
                    cookies.removeAll()
                    readiness = .unconfirmed
                }
            }
            return snapshotLocked()
        }
        if let transition { publish(transition) }
        if Task.isCancelled {
            return CookieSessionSnapshot(cookies: [], version: snapshot.version, readiness: .unconfirmed)
        }
        return snapshot
    }

    public func attachCookies(to request: URLRequest) -> URLRequest {
        expireIfNecessary()
        let snapshot = lock.withLock { snapshotLocked() }
        var request = CookieRequestPolicy.attach(cookies: snapshot.cookies, to: request)
        request.httpShouldHandleCookies = false
        return request
    }

    private func snapshotLocked() -> CookieSessionSnapshot {
        CookieSessionSnapshot(cookies: cookies, version: version, readiness: readiness)
    }
    private func publish(_ transition: CookieSessionTransition) {
        let handler = lock.withLock { transitionHandler }
        handler?(transition)
    }
    private func expireIfNecessary() {
        let expiredVersion: UInt64? = lock.withLock {
            readiness == .authenticated && !Self.hasUsableSession(cookies) ? version : nil
        }
        if let expiredVersion { noteServerSessionExpired(version: expiredVersion) }
    }
    public static func hasUsableSession(_ cookies: [HTTPCookie], now: Date = Date()) -> Bool {
        CookieRequestPolicy.cookies(cookies, matching: BiliAPIContractCatalog.require("credential.info.valid").url, now: now)
            .contains { $0.name.caseInsensitiveCompare("SESSDATA") == .orderedSame && !$0.value.isEmpty }
    }
    private static func credentialFingerprint(_ cookies: [HTTPCookie]) -> Int {
        // Process-local comparison only; never logged/exported or used as a cache key.
        let relevant = cookies.filter {
            ["sessdata", "dedeuserid", "bili_jct"].contains($0.name.lowercased())
                && ($0.domain == "bilibili.com" || $0.domain.hasSuffix(".bilibili.com"))
                && ($0.expiresDate.map { $0 > Date() } ?? true)
        }.sorted { ($0.name, $0.domain, $0.path, $0.value) < ($1.name, $1.domain, $1.path, $1.value) }
        var hash = Hasher()
        for cookie in relevant {
            hash.combine(cookie.name); hash.combine(cookie.domain); hash.combine(cookie.path)
            hash.combine(cookie.value); hash.combine(cookie.isSecure)
        }
        return hash.finalize()
    }
}
