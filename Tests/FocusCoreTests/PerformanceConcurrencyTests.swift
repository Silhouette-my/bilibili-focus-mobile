import Foundation
import Testing
@testable import FocusCore

struct PerformanceCacheTests {
    @Test func explicitRefreshReportsFailureWhileAnotherConsumerUsesRetainedCache() async throws {
        let cache = AsyncExpiringCache<String, Int>()
        let gate = PerformanceValueGate<Int>()
        let policy = FocusCachePolicy(freshFor: 60, staleIfErrorFor: 60)
        await cache.insert(7, for: "account", policy: policy)
        let refresh = Task {
            try await cache.value(for: "account", policy: policy, forceRefresh: true, returnsStaleOnError: false) {
                try await gate.read()
            }
        }
        await gate.waitForCount(1)
        let fallback = Task {
            try await cache.value(for: "account", policy: policy, forceRefresh: true) { try await gate.read() }
        }
        await performanceEventually { await cache.activeConsumerCount == 2 }
        await gate.fail(0, error: URLError(.notConnectedToInternet))
        await #expect(throws: URLError.self) { try await refresh.value }
        #expect(try await fallback.value == 7)
        #expect(await cache.cachedValue(for: "account") == 7)
        #expect(await gate.count == 1)
    }

    @Test func forcedRefreshKeepsStaleAndAllConcurrentConsumersShareFallback() async throws {
        let cache = AsyncExpiringCache<String, Int>(maximumEntries: 4)
        let gate = PerformanceValueGate<Int>()
        let policy = FocusCachePolicy(freshFor: 60, staleIfErrorFor: 60)
        await cache.insert(7, for: "fixture", policy: policy)
        let a = Task { try await cache.value(for: "fixture", policy: policy, forceRefresh: true) { try await gate.read() } }
        await gate.waitForCount(1)
        let b = Task { try await cache.value(for: "fixture", policy: policy, forceRefresh: true) { try await gate.read() } }
        await performanceEventually { await cache.activeConsumerCount == 2 }
        await gate.fail(0, error: URLError(.notConnectedToInternet))
        #expect(try await a.value == 7)
        #expect(try await b.value == 7)
        #expect(await gate.count == 1)
        #expect(await cache.cachedValue(for: "fixture") == 7)
    }

    @Test func invalidationFencesLateCompletionAndProtectsNewFlight() async throws {
        let cache = AsyncExpiringCache<String, Int>()
        let gate = PerformanceValueGate<Int>()
        let policy = FocusCachePolicy(freshFor: 60)
        let old = Task { try await cache.value(for: "key", policy: policy) { try await gate.read() } }
        await gate.waitForCount(1)
        await cache.invalidate("key")
        let new = Task { try await cache.value(for: "key", policy: policy) { try await gate.read() } }
        await gate.waitForCount(2)
        await gate.complete(0, value: 1)
        await #expect(throws: CancellationError.self) { try await old.value }
        #expect(await cache.activeConsumerCount == 1)
        await gate.complete(1, value: 2)
        #expect(try await new.value == 2)
        #expect(await cache.cachedValue(for: "key") == 2)
        let force = Task { try await cache.value(for: "key", policy: policy, forceRefresh: true) { try await gate.read() } }
        await gate.waitForCount(3)
        await cache.insert(3, for: "key", policy: policy)
        await gate.complete(2, value: 99)
        await #expect(throws: CancellationError.self) { try await force.value }
        #expect(await cache.cachedValue(for: "key") == 3)
    }

    @Test func authenticationErrorCannotBecomeStaleSuccessOrKeepFreshEntry() async {
        let cache = AsyncExpiringCache<String, Int>()
        let policy = FocusCachePolicy(freshFor: 60, staleIfErrorFor: 60)
        await cache.insert(7, for: "account", policy: policy)
        await #expect(throws: DynamicFeedService.ServiceError.loginRequired) {
            try await cache.value(for: "account", policy: policy, forceRefresh: true,
                                  canUseStaleOnError: { $0 is URLError }) {
                throw DynamicFeedService.ServiceError.loginRequired
            }
        }
        #expect(await cache.cachedValue(for: "account") == nil)
    }

    @Test func deadlineReturnsBeforeAnUncooperativeOperationCompletes() async {
        let work = PerformanceValueGate<Int>()
        let timer = PerformanceValueGate<Int>()
        let result = Task {
            try await FocusAsyncDeadline.value(timeoutNanoseconds: 1, sleeper: { _ in _ = try await timer.read() }) {
                try await work.read()
            }
        }
        await work.waitForCount(1)
        await timer.waitForCount(1)
        await timer.complete(0, value: 0)
        await #expect(throws: FocusAsyncDeadlineError.timedOut) { try await result.value }
        #expect(await work.completed == 0, "The deadline did not join the cancelled child")
        await work.complete(0, value: 99)
    }

    @Test func cancellationWinsBeforeDeadlineAndIgnoresLateWork() async {
        let work = PerformanceValueGate<Int>()
        let result = Task {
            try await FocusAsyncDeadline.value(timeoutNanoseconds: 60_000_000_000) { try await work.read() }
        }
        await work.waitForCount(1)
        result.cancel()
        await #expect(throws: CancellationError.self) { try await result.value }
        #expect(await work.completed == 0)
        await work.complete(0, value: 99)
    }
}

struct PerformancePlayerInfoTests {
    @Test func resumeAndSubtitlesShareOneResponseAndConsumerCancellationIsIsolated() async throws {
        let fixture = PerformancePlayerAPI()
        let cookies = PerformanceVersionedCookies()
        let loader: BiliAPITransport.RequestLoader = { try await fixture.respond($0) }
        let repository = FocusPlayerInfoRepository(cookieProvider: cookies, signer: WBISigner(), requestLoader: loader)
        let detail = FocusVideoDetailService(cookieProvider: cookies, playerInfoRepository: repository, requestLoader: loader)
        let subtitles = FocusVideoSubtitleService(cookieProvider: cookies, playerInfoRepository: repository, requestLoader: loader)
        await fixture.holdInfo()
        let resume = Task { try await detail.fetchPlaybackResume(aid: 42, cid: 4201) }
        await fixture.infoGate.waitForCount(1)
        let tracks = Task { try await subtitles.fetchTracks(aid: 42, cid: 4201) }
        await performanceEventually { await repository.activeConsumerCount == 2 }
        resume.cancel()
        await fixture.releaseInfo(0)
        #expect(try await tracks.value.count == 1)
        await #expect(throws: CancellationError.self) { try await resume.value }
        let recovered = try await detail.fetchPlaybackResume(aid: 42, cid: 4201)
        #expect(recovered.positionMilliseconds == 87_000)
        #expect(await fixture.infoRequests == 1)
        #expect(await fixture.navRequests == 1)
    }

    @Test func lateSessionResponseIsRejectedAndNewCIDIsNotMerged() async throws {
        let fixture = PerformancePlayerAPI()
        let cookies = PerformanceVersionedCookies()
        let repository = FocusPlayerInfoRepository(cookieProvider: cookies, signer: WBISigner(), requestLoader: { try await fixture.respond($0) })
        await fixture.holdInfo()
        let old = Task { try await repository.fetch(aid: 42, cid: 4201) }
        await fixture.infoGate.waitForCount(1)
        cookies.advance()
        await fixture.releaseInfo(0)
        await #expect(throws: CancellationError.self) { try await old.value }
        _ = try await repository.fetch(aid: 42, cid: 4201)
        _ = try await repository.fetch(aid: 42, cid: 4202)
        #expect(await fixture.infoRequests == 3)
    }

    @Test func streamFallbackIsBoundedAndOfflineOrRiskDoesNotTriggerDash() async throws {
        for mode in [PerformancePlayerAPI.Mode.offline, .risk, .unsupported] {
            let fixture = PerformancePlayerAPI(mode: mode)
            let service = FocusVideoDetailService(cookieProvider: PerformanceVersionedCookies(), wbiSigner: WBISigner(),
                                                 requestLoader: { try await fixture.respond($0) })
            do {
                _ = try await service.fetchPlayback(bvid: "BV1xx411c7mD", cid: 4201)
                #expect(mode == .unsupported)
            } catch {
                #expect(mode != .unsupported)
                if mode == .offline { #expect((error as? URLError)?.code == .notConnectedToInternet) }
                if mode == .risk { #expect(error as? FocusVideoDetailService.ServiceError == .api(code: -352, message: "fixture risk")) }
            }
            #expect(await fixture.playRequests == (mode == .unsupported ? 2 : 1))
            #expect(await fixture.navRequests == (mode == .unsupported ? 1 : 0))
        }
    }
}

private actor PerformanceValueGate<Value: Sendable> {
    private(set) var count = 0
    private(set) var completed = 0
    private var requests: [Int: CheckedContinuation<Value, Error>] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    func read() async throws -> Value {
        let id = count; count += 1
        return try await withCheckedThrowingContinuation { continuation in
            requests[id] = continuation
            let ready = observers.filter { $0.0 <= count }
            observers.removeAll { $0.0 <= count }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForCount(_ target: Int) async {
        if count >= target { return }
        await withCheckedContinuation { observers.append((target, $0)) }
    }
    func complete(_ id: Int, value: Value) { completed += 1; requests.removeValue(forKey: id)?.resume(returning: value) }
    func fail(_ id: Int, error: Error) { completed += 1; requests.removeValue(forKey: id)?.resume(throwing: error) }
}

private func performanceEventually(_ predicate: () async -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(4))
    while !(await predicate()), ContinuousClock.now < deadline { await Task.yield() }
    #expect(await predicate(), "Expected controlled consumer state")
}

private final class PerformanceVersionedCookies: CookieSnapshotProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var version: UInt64 = 0
    var sessionVersion: UInt64 { lock.withLock { version } }
    func advance() { lock.withLock { version += 1 } }
    func loadCookies() async -> [HTTPCookie] { [] }
}

private actor PerformancePlayerAPI {
    enum Mode: Sendable, Equatable { case regular, offline, risk, unsupported }
    let infoGate = PerformanceValueGate<Int>()
    private var hold = false
    private let mode: Mode
    private(set) var infoRequests = 0
    private(set) var navRequests = 0
    private(set) var playRequests = 0
    init(mode: Mode = .regular) { self.mode = mode }
    func holdInfo() { hold = true }
    func releaseInfo(_ index: Int) async { hold = false; await infoGate.complete(index, value: 0) }
    func respond(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let text: String
        switch url.path {
        case "/x/web-interface/nav":
            navRequests += 1
            text = #"{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/0123456789abcdef0123456789abcdef.png","sub_url":"https://i0.hdslb.com/bfs/wbi/fedcba9876543210fedcba9876543210.png"}}}"#
        case "/x/player/wbi/v2":
            infoRequests += 1
            if hold { _ = try await infoGate.read() }
            text = #"{"code":0,"data":{"last_play_cid":4201,"last_play_time":87000,"subtitle":{"subtitles":[{"id":1,"lan":"zh-CN","lan_doc":"中文","subtitle_url":"https://aisubtitle.hdslb.com/fixture.json"}]}}}"#
        case "/x/player/playurl":
            playRequests += 1
            switch mode {
            case .offline: throw URLError(.notConnectedToInternet)
            case .risk: text = #"{"code":-352,"message":"fixture risk"}"#
            case .unsupported: text = #"{"code":0,"data":{"quality":80}}"#
            case .regular: text = Self.mediaPayload
            }
        case "/x/player/wbi/playurl": playRequests += 1; text = Self.mediaPayload
        default: throw URLError(.unsupportedURL)
        }
        return (Data(text.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    static let mediaPayload = #"{"code":0,"data":{"quality":80,"accept_quality":[80],"accept_description":["1080P"],"durl":[{"url":"https://fixture.bilivideo.com/video.mp4"}]}}"#
}
