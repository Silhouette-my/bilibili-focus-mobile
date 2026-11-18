import Foundation
import Testing
@testable import FocusCore

struct PerformanceSessionTests {
    @Test func concurrentInitializationIsSharedAndConsumerCancellationIsIsolated() async {
        let gate = SessionReadGate()
        let session = CookieSessionCoordinator(reader: { try await gate.read() }, warmupDelays: [])
        let first = Task { await session.loadSnapshot() }
        await gate.waitForReads(1)
        let second = Task { await session.loadSnapshot() }
        first.cancel()
        await gate.complete(0, cookies: fixtureCookies("one"))
        let a = await first.value
        let b = await second.value
        #expect(a.cookies.isEmpty)
        #expect(b.readiness == .authenticated)
        #expect(await gate.count == 1)
        #expect(session.sessionVersion == 0)
    }

    @Test func outOfOrderReadCannotReplaceNewSessionOrRestoreDeletedCookies() async {
        let gate = SessionReadGate()
        let session = CookieSessionCoordinator(reader: { try await gate.read() }, warmupDelays: [])
        let old = Task { await session.loadSnapshot() }
        await gate.waitForReads(1)
        session.invalidate()
        #expect(session.sessionVersion == 1)
        #expect(session.sessionReadiness == .unconfirmed)
        let current = Task { await session.loadSnapshot() }
        await gate.waitForReads(2)
        await gate.complete(1, cookies: [])
        #expect(await current.value.readiness == .anonymous)
        await gate.complete(0, cookies: fixtureCookies("old-account"))
        #expect(await old.value.cookies.isEmpty)
        #expect(await session.loadCookies().isEmpty)
        #expect(session.sessionReadiness == .anonymous)
    }

    @Test func transientReadFailureIsUnknownAndCanBeRetried() async {
        let gate = SessionReadGate()
        let session = CookieSessionCoordinator(reader: { try await gate.read() }, warmupDelays: [])
        let first = Task { await session.loadSnapshot() }
        await gate.waitForReads(1)
        await gate.fail(0)
        #expect(await first.value.readiness == .unconfirmed)
        #expect(session.sessionReadiness != .anonymous)
        let next = Task { await session.loadSnapshot() }
        await gate.waitForReads(2)
        await gate.complete(1, cookies: fixtureCookies("recovered"))
        #expect(await next.value.readiness == .authenticated)
    }

    @Test func expirationFencesLateRequestsAndSameRejectedCredentialStaysRejected() async {
        let gate = SessionReadGate()
        let session = CookieSessionCoordinator(reader: { try await gate.read() }, warmupDelays: [])
        let initial = Task { await session.loadSnapshot() }
        await gate.waitForReads(1)
        await gate.complete(0, cookies: fixtureCookies("expired-server-session"))
        let version = await initial.value.version
        session.noteServerSessionExpired(version: version)
        #expect(session.sessionVersion == version + 1)
        #expect(await session.loadSnapshot().readiness == .expired)
        #expect(await gate.count == 1)
        session.invalidate()
        let reread = Task { await session.loadSnapshot() }
        await gate.waitForReads(2)
        await gate.complete(1, cookies: fixtureCookies("expired-server-session"))
        #expect(await reread.value.readiness == .expired)
        session.invalidate()
        let newLogin = Task { await session.loadSnapshot() }
        await gate.waitForReads(3)
        await gate.complete(2, cookies: fixtureCookies("new-server-session"))
        #expect(await newLogin.value.readiness == .authenticated)
        let currentVersion = session.sessionVersion
        session.noteServerSessionExpired(version: version)
        #expect(session.sessionVersion == currentVersion)
        #expect(session.sessionReadiness == .authenticated)
    }

    @Test func networkAndRiskDoNotExpireButTrueMinus101Does() async {
        let session = CookieSessionCoordinator(reader: { fixtureCookies("synthetic-auth") }, warmupDelays: [])
        _ = await session.loadSnapshot()
        let network = LoginHealthService(cookieProvider: session, requestLoader: { _ in throw URLError(.notConnectedToInternet) })
        #expect(await network.check() == .networkUnavailable)
        #expect(session.sessionReadiness == .authenticated)
        let risk = LoginHealthService(cookieProvider: session, requestLoader: response(code: -352))
        #expect(await risk.check() == .wbiRiskControlled)
        #expect(session.sessionVersion == 0)
        let expired = LoginHealthService(cookieProvider: session, requestLoader: response(code: -101))
        #expect(await expired.check() == .sessionExpired)
        #expect(session.sessionReadiness == .expired)
        #expect(session.sessionVersion == 1)
        #expect(await session.loadCookies().isEmpty)
    }

    @Test func uncertainEmptySnapshotIsNotConfirmedLoggedOut() async {
        let unknown = LoginHealthService(cookieProvider: UnconfirmedFixtureCookies(), requestLoader: response(code: 0))
        #expect(await unknown.check() == .unknown)
    }

    private func response(code: Int) -> BiliAPITransport.RequestLoader {
        { request in
            (Data("{\"code\":\(code),\"data\":{\"isLogin\":true}}".utf8),
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
}

private func fixtureCookies(_ value: String) -> [HTTPCookie] {
    [HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: "SESSDATA", .value: value, .secure: "TRUE"])!]
}

private struct UnconfirmedFixtureCookies: CookieSnapshotProvider {
    func loadCookies() async -> [HTTPCookie] { [] }
}

private actor SessionReadGate {
    private(set) var count = 0
    private var requests: [Int: CheckedContinuation<[HTTPCookie], Error>] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    func read() async throws -> [HTTPCookie] {
        let id = count
        count += 1
        let ready = observers.filter { $0.0 <= count }
        observers.removeAll { $0.0 <= count }
        ready.forEach { $0.1.resume() }
        return try await withCheckedThrowingContinuation { requests[id] = $0 }
    }
    func waitForReads(_ target: Int) async {
        if count >= target { return }
        await withCheckedContinuation { observers.append((target, $0)) }
    }
    func complete(_ id: Int, cookies: [HTTPCookie]) { requests.removeValue(forKey: id)?.resume(returning: cookies) }
    func fail(_ id: Int) { requests.removeValue(forKey: id)?.resume(throwing: URLError(.cannotLoadFromNetwork)) }
}
