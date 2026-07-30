import Foundation
import Testing
@testable import FocusCore

private let playbackScopeA = FocusPlaybackAccountScope.accountID(1001)
private let playbackScopeB = FocusPlaybackAccountScope.accountID(2002)

@Suite("Persistent playback progress and history outbox")
struct FocusPlaybackProgressStoreTests {
    @Test("progress survives recreation, remains bounded, and expires")
    func progressPersistenceBoundsAndRecency() async {
        let persistence = PlaybackStateMemoryPersistence()
        let clock = PlaybackTestClock(now: 1_000)
        let firstStore = FocusPlaybackProgressStore(
            persistence: persistence,
            maxProgressEntries: 2,
            recentProgressLifetimeMilliseconds: 1_000,
            clock: { clock.now }
        )

        _ = await firstStore.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 1,
            bvid: "bv-one",
            cid: 11,
            positionMilliseconds: 11_000
        )
        clock.now = 1_100
        _ = await firstStore.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 2,
            bvid: "BV-TWO",
            cid: 22,
            positionMilliseconds: 22_000
        )
        clock.now = 1_200
        _ = await firstStore.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 3,
            bvid: "BV-THREE",
            cid: 33,
            positionMilliseconds: 33_000
        )

        let restoredStore = FocusPlaybackProgressStore(
            persistence: persistence,
            maxProgressEntries: 2,
            recentProgressLifetimeMilliseconds: 1_000,
            clock: { clock.now }
        )
        #expect(
            await restoredStore.recentProgress(
                accountScope: playbackScopeA,
                aid: 1,
                bvid: "BV-ONE",
                cid: 11
            ) == nil
        )
        #expect(
            await restoredStore.recentProgress(
                accountScope: playbackScopeA,
                aid: 2,
                bvid: "BV-TWO",
                cid: 22
            )?
                .positionMilliseconds == 22_000
        )
        #expect(
            await restoredStore.recentProgress(
                accountScope: playbackScopeA,
                aid: 0,
                bvid: "bv-three",
                cid: 33
            )?
                .positionMilliseconds == 33_000
        )

        clock.now = 2_201
        #expect(
            await restoredStore.recentProgress(
                accountScope: playbackScopeA,
                aid: 3,
                bvid: "BV-THREE",
                cid: 33
            ) == nil
        )
    }

    @Test("most recently watched page wins when no CID is selected")
    func mostRecentPageWins() async {
        let persistence = PlaybackStateMemoryPersistence()
        let clock = PlaybackTestClock(now: 10_000)
        let store = FocusPlaybackProgressStore(
            persistence: persistence,
            clock: { clock.now }
        )

        _ = await store.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 42,
            bvid: "BV1xx411c7mD",
            cid: 4201,
            positionMilliseconds: 30_000
        )
        clock.now += 1
        _ = await store.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 42,
            bvid: "BV1xx411c7mD",
            cid: 4203,
            positionMilliseconds: 87_000
        )

        let entry = await store.recentProgress(
            accountScope: playbackScopeA,
            aid: 42,
            bvid: "BV1xx411c7mD"
        )
        #expect(entry?.cid == 4203)
        #expect(entry?.positionMilliseconds == 87_000)
    }

    @Test("account scope prefers DedeUserID and fingerprints fallback identity cookies")
    func accountScopeResolutionDoesNotPersistCookieSecrets() throws {
        let firstAccountCookies = [
            playbackCookie(name: "DedeUserID", value: "1001"),
            playbackCookie(name: "SESSDATA", value: "secret-session-a"),
        ]
        let rotatedSessionCookies = [
            playbackCookie(name: "DedeUserID", value: "1001"),
            playbackCookie(name: "SESSDATA", value: "secret-session-b"),
        ]
        #expect(
            FocusPlaybackAccountScope.resolve(cookies: firstAccountCookies)
                == FocusPlaybackAccountScope.resolve(cookies: rotatedSessionCookies)
        )
        #expect(
            FocusPlaybackAccountScope.resolve(cookies: firstAccountCookies)
                == playbackScopeA
        )

        let fingerprintA = FocusPlaybackAccountScope.resolve(
            cookies: [playbackCookie(name: "SESSDATA", value: "secret-session-a")]
        )
        let fingerprintAWithDuplicateDomains = FocusPlaybackAccountScope.resolve(
            cookies: [
                playbackCookie(
                    name: "SESSDATA",
                    value: "secret-session-a",
                    domain: ".bilibili.com"
                ),
                playbackCookie(
                    name: "sessdata",
                    value: "secret-session-a",
                    domain: "api.bilibili.com"
                ),
            ]
        )
        let fingerprintAReordered = FocusPlaybackAccountScope.resolve(
            cookies: [
                playbackCookie(name: "DedeUserID__ckMd5", value: "stable-digest"),
                playbackCookie(name: "SESSDATA", value: "secret-session-a"),
            ]
        )
        let fingerprintAReorderedAgain = FocusPlaybackAccountScope.resolve(
            cookies: [
                playbackCookie(name: "SESSDATA", value: "secret-session-a"),
                playbackCookie(name: "DedeUserID__ckMd5", value: "stable-digest"),
            ]
        )
        let fingerprintB = FocusPlaybackAccountScope.resolve(
            cookies: [playbackCookie(name: "SESSDATA", value: "secret-session-b")]
        )

        #expect(fingerprintA != fingerprintB)
        #expect(fingerprintA == fingerprintAWithDuplicateDomains)
        #expect(fingerprintAReordered == fingerprintAReorderedAgain)
        #expect(FocusPlaybackAccountScope.resolve(cookies: []) == .anonymous)

        let encodedAccount = try JSONEncoder().encode(playbackScopeA)
        let persistedAccount = String(decoding: encodedAccount, as: UTF8.self)
        #expect(!persistedAccount.contains("1001"))
        #expect(
            persistedAccount.contains(
                "account-v2-bd44f72021e30dff059d35d48de464d63d63b1313d2f703d7a12877722ba05bd"
            )
        )

        let encodedFingerprint = try JSONEncoder().encode(fingerprintA)
        let persistedFingerprint = String(decoding: encodedFingerprint, as: UTF8.self)
        #expect(!persistedFingerprint.contains("secret-session-a"))
        #expect(!persistedFingerprint.contains("SESSDATA"))
        #expect(
            persistedFingerprint.contains(
                "account-v2-249441c3e0f80d9290e06ffa7a0b3ff04b29ea060068e56579adefe3c1a0a772"
            )
        )
    }

    @Test("progress and outbox remain isolated across accounts and reconstruction")
    func accountScopedStateSurvivesReconstruction() async {
        let persistence = PlaybackStateMemoryPersistence()
        let store = FocusPlaybackProgressStore(persistence: persistence)

        _ = await store.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 42,
            bvid: "BV1xx411c7mD",
            cid: 4203,
            positionMilliseconds: 30_000
        )
        _ = await store.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeB,
            aid: 42,
            bvid: "BV1xx411c7mD",
            cid: 4203,
            positionMilliseconds: 80_000
        )
        let anonymousReport = await store.recordProgressAndEnqueueHistory(
            accountScope: .anonymous,
            aid: 42,
            bvid: "BV1xx411c7mD",
            cid: 4203,
            positionMilliseconds: 12_000
        )
        #expect(anonymousReport == nil)

        let restoredStore = FocusPlaybackProgressStore(persistence: persistence)
        #expect(
            await restoredStore.recentProgress(
                accountScope: playbackScopeA,
                aid: 42,
                bvid: "BV1xx411c7mD",
                cid: 4203
            )?.positionMilliseconds == 30_000
        )
        #expect(
            await restoredStore.recentProgress(
                accountScope: playbackScopeB,
                aid: 42,
                bvid: "BV1xx411c7mD",
                cid: 4203
            )?.positionMilliseconds == 80_000
        )
        #expect(
            await restoredStore.recentProgress(
                accountScope: .anonymous,
                aid: 42,
                bvid: "BV1xx411c7mD",
                cid: 4203
            )?.positionMilliseconds == 12_000
        )

        let delivered = PlaybackDeliveredReports()
        await restoredStore.drainPendingHistory(accountScope: playbackScopeA) { report in
            await delivered.append(report)
            return .delivered
        }
        #expect(await delivered.values.map(\.accountScope) == [playbackScopeA])
        #expect(
            await restoredStore.pendingHistoryReports(accountScope: playbackScopeA).isEmpty
        )
        #expect(
            await restoredStore.pendingHistoryReports(accountScope: playbackScopeB).count == 1
        )
        #expect(
            await restoredStore.pendingHistoryReports(accountScope: .anonymous).isEmpty
        )
    }

    @Test("legacy v1 state is discarded instead of being assigned to an account")
    func legacyUnscopedStateIsDiscarded() async {
        let legacyState = Data(
            #"""
            {
              "schemaVersion": 1,
              "nextRevision": 2,
              "progressEntries": [{
                "aid": 42,
                "bvid": "BV1xx411c7mD",
                "cid": 4203,
                "positionMilliseconds": 87000,
                "updatedAtMilliseconds": 1
              }],
              "pendingReports": [{
                "aid": 42,
                "cid": 4203,
                "progressSeconds": 87,
                "revision": 1,
                "updatedAtMilliseconds": 1
              }]
            }
            """#.utf8
        )
        let persistence = PlaybackStateMemoryPersistence(data: legacyState)
        let store = FocusPlaybackProgressStore(persistence: persistence)

        #expect(
            await store.recentProgress(
                accountScope: playbackScopeA,
                aid: 42,
                bvid: "BV1xx411c7mD",
                cid: 4203
            ) == nil
        )
        #expect(await store.pendingHistoryReports(accountScope: playbackScopeA).isEmpty)
        #expect(await store.pendingHistoryReports(accountScope: .anonymous).isEmpty)
    }

    @Test("account switch before reporter execution preserves the original outbox")
    func accountSwitchBeforeReporterDoesNotCrossPost() async {
        let cookieProvider = SwitchablePlaybackCookieProvider(accountID: 1001)
        let requestRecorder = PlaybackHistoryRequestRecorder()
        let actionService = FocusVideoActionService(
            cookieProvider: cookieProvider,
            requestLoader: { request in
                await requestRecorder.respond(to: request)
            }
        )
        let store = FocusPlaybackProgressStore(
            persistence: PlaybackStateMemoryPersistence()
        )
        _ = await store.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 42,
            bvid: "BV1xx411c7mD",
            cid: 4203,
            positionMilliseconds: 87_000
        )

        await cookieProvider.switchAccount(to: 2002)
        await store.drainPendingHistory(accountScope: playbackScopeA) { report in
            await actionService.attemptWatchHistory(report)
        }
        #expect(await requestRecorder.requests.isEmpty)
        #expect(await store.pendingHistoryReports(accountScope: playbackScopeA).count == 1)
        #expect(await store.pendingHistoryReports(accountScope: playbackScopeB).isEmpty)

        await cookieProvider.switchAccount(to: 1001)
        await store.drainPendingHistory(accountScope: playbackScopeA) { report in
            await actionService.attemptWatchHistory(report)
        }
        #expect(await requestRecorder.requests.count == 1)
        #expect(await store.pendingHistoryReports(accountScope: playbackScopeA).isEmpty)
    }

    @Test("local resume is authoritative and server is only the fallback")
    func localResumePrecedenceUsesExistingBoundaryPolicy() {
        #expect(
            !FocusPlaybackResumeResolver.isMeaningfulResume(
                FocusVideoPlaybackResume(cid: 4203, positionMilliseconds: 4_999)
            )
        )
        #expect(
            FocusPlaybackResumeResolver.isMeaningfulResume(
                FocusVideoPlaybackResume(cid: 4203, positionMilliseconds: 5_000)
            )
        )

        let local = FocusPlaybackProgressEntry(
            accountScope: playbackScopeA,
            aid: 42,
            bvid: "BV1xx411c7mD",
            cid: 4203,
            positionMilliseconds: 87_000,
            updatedAtMilliseconds: 1
        )
        let server = FocusVideoPlaybackResume(
            cid: 4203,
            positionMilliseconds: 45_000
        )

        #expect(
            FocusPlaybackResumeResolver.initialPositionMilliseconds(
                local: local,
                server: server,
                selectedCID: 4203,
                durationSeconds: 120
            ) == 87_000
        )
        #expect(
            FocusPlaybackResumeResolver.initialPositionMilliseconds(
                local: nil,
                server: server,
                selectedCID: 4203,
                durationSeconds: 120
            ) == 45_000
        )

        let nearTailLocal = FocusPlaybackProgressEntry(
            accountScope: playbackScopeA,
            aid: 42,
            bvid: "BV1xx411c7mD",
            cid: 4203,
            positionMilliseconds: 119_000,
            updatedAtMilliseconds: 2
        )
        #expect(
            FocusPlaybackResumeResolver.initialPositionMilliseconds(
                local: nearTailLocal,
                server: server,
                selectedCID: 4203,
                durationSeconds: 120
            ) == 0
        )
    }

    @Test("outbox merges by aid and CID without an old success deleting new progress")
    func outboxMergeAndRevisionSafeAcknowledgement() async throws {
        let persistence = PlaybackStateMemoryPersistence()
        let clock = PlaybackTestClock(now: 20_000)
        let store = FocusPlaybackProgressStore(
            persistence: persistence,
            clock: { clock.now }
        )

        let first = try #require(
            await store.recordProgressAndEnqueueHistory(
                accountScope: playbackScopeA,
                aid: 42,
                bvid: "BV1xx411c7mD",
                cid: 4203,
                positionMilliseconds: 30_000
            )
        )
        clock.now += 1
        let replacement = try #require(
            await store.recordProgressAndEnqueueHistory(
                accountScope: playbackScopeA,
                aid: 42,
                bvid: "BV1xx411c7mD",
                cid: 4203,
                positionMilliseconds: 45_000
            )
        )

        #expect(first.revision != replacement.revision)
        #expect(
            await store.acknowledgeHistoryReport(
                accountScope: playbackScopeA,
                aid: first.aid,
                cid: first.cid,
                revision: first.revision
            ) == false
        )
        let pending = await store.pendingHistoryReports(accountScope: playbackScopeA)
        #expect(pending == [replacement])
    }

    @Test("failed or cancelled delivery remains durable and success removes it")
    func outboxDeliveryLifecycle() async {
        let persistence = PlaybackStateMemoryPersistence()
        let store = FocusPlaybackProgressStore(persistence: persistence)
        _ = await store.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 42,
            bvid: "BV1xx411c7mD",
            cid: 4203,
            positionMilliseconds: 87_000
        )

        let retryable = await store.drainPendingHistory(accountScope: playbackScopeA) { _ in
            .retryableFailure
        }
        #expect(retryable.requiresRetry)
        #expect(retryable.remainingCount == 1)
        #expect(await store.pendingHistoryReports(accountScope: playbackScopeA).count == 1)

        let cancelledDrain = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await store.drainPendingHistory(accountScope: playbackScopeA) { _ in
                Issue.record("a cancelled drain must not call the reporter")
                return .delivered
            }
        }
        await cancelledDrain.value
        #expect(await store.pendingHistoryReports(accountScope: playbackScopeA).count == 1)

        let delivered = PlaybackDeliveredReports()
        await store.drainPendingHistory(accountScope: playbackScopeA) { report in
            await delivered.append(report)
            return .delivered
        }
        #expect(await delivered.values.count == 1)
        #expect(await store.pendingHistoryReports(accountScope: playbackScopeA).isEmpty)

        let restoredStore = FocusPlaybackProgressStore(persistence: persistence)
        #expect(await restoredStore.pendingHistoryReports(accountScope: playbackScopeA).isEmpty)
    }

    @Test("permanent failure is discarded and does not block later reports")
    func permanentFailureDoesNotPoisonTheQueue() async {
        let clock = PlaybackTestClock(now: 30_000)
        let store = FocusPlaybackProgressStore(
            persistence: PlaybackStateMemoryPersistence(),
            clock: { clock.now }
        )
        _ = await store.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 1,
            bvid: "BV-PERMANENT",
            cid: 11,
            positionMilliseconds: 10_000
        )
        clock.now += 1
        _ = await store.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 2,
            bvid: "BV-DELIVERED",
            cid: 22,
            positionMilliseconds: 20_000
        )

        let outcome = await store.drainPendingHistory(accountScope: playbackScopeA) { report in
            report.aid == 1 ? .permanentFailure : .delivered
        }

        #expect(outcome == FocusHistoryOutboxDrainOutcome(
            deliveredCount: 1,
            discardedCount: 1,
            remainingCount: 0
        ))
        #expect(!outcome.requiresRetry)
        #expect(await store.pendingHistoryReports(accountScope: playbackScopeA).isEmpty)
    }

    @Test("permanent acknowledgement cannot delete a newer revision")
    func permanentFailureKeepsConcurrentReplacement() async throws {
        let clock = PlaybackTestClock(now: 40_000)
        let store = FocusPlaybackProgressStore(
            persistence: PlaybackStateMemoryPersistence(),
            clock: { clock.now }
        )
        let first = try #require(
            await store.recordProgressAndEnqueueHistory(
                accountScope: playbackScopeA,
                aid: 42,
                bvid: "BV-REVISION",
                cid: 4203,
                positionMilliseconds: 30_000
            )
        )

        let outcome = await store.drainPendingHistory(accountScope: playbackScopeA) { report in
            if report.revision == first.revision {
                clock.now += 1
                _ = await store.recordProgressAndEnqueueHistory(
                    accountScope: playbackScopeA,
                    aid: report.aid,
                    bvid: "BV-REVISION",
                    cid: report.cid,
                    positionMilliseconds: 45_000
                )
                return .permanentFailure
            }
            return .retryableFailure
        }

        let pending = await store.pendingHistoryReports(accountScope: playbackScopeA)
        #expect(pending.count == 1)
        let replacement = try #require(pending.first)
        #expect(replacement.revision != first.revision)
        #expect(replacement.progressSeconds == 45)
        #expect(outcome.discardedCount == 0)
        #expect(outcome.remainingCount == 1)
        #expect(outcome.requiresRetry)
    }

    @Test("old anonymous pending reports are removed without calling reporter")
    func anonymousOutboxMigrationIsLocalOnly() async {
        let persistedState = Data(
            #"""
            {
              "schemaVersion": 2,
              "nextRevision": 2,
              "progressEntries": [],
              "pendingReports": [{
                "accountScope": {"storageValue": "anonymous"},
                "aid": 42,
                "cid": 4203,
                "progressSeconds": 87,
                "revision": 1,
                "updatedAtMilliseconds": 1
              }]
            }
            """#.utf8
        )
        let persistence = PlaybackStateMemoryPersistence(data: persistedState)
        let store = FocusPlaybackProgressStore(persistence: persistence)

        let outcome = await store.drainPendingHistory(accountScope: .anonymous) { _ in
            Issue.record("anonymous outbox must never call a server reporter")
            return .delivered
        }

        #expect(outcome == .noWork)
        #expect(await store.pendingHistoryReports(accountScope: .anonymous).isEmpty)

        let reconstructed = FocusPlaybackProgressStore(persistence: persistence)
        #expect(await reconstructed.pendingHistoryReports(accountScope: .anonymous).isEmpty)
        let cleanedData = await persistence.loadPlaybackState()
        let cleanedRoot = try? cleanedData.flatMap {
            try JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        #expect((cleanedRoot?["pendingReports"] as? [Any])?.isEmpty == true)
    }

    @Test("action errors map to permanent and retryable attempts")
    func actionErrorClassification() async {
        #expect(
            FocusVideoActionService.historyReportAttemptOutcome(
                for: FocusVideoActionService.ServiceError.loginRequired
            ) == .permanentFailure
        )
        #expect(
            FocusVideoActionService.historyReportAttemptOutcome(
                for: FocusVideoActionService.ServiceError.invalidParameters
            ) == .permanentFailure
        )
        #expect(
            FocusVideoActionService.historyReportAttemptOutcome(
                for: FocusVideoActionService.ServiceError.api(code: -400, message: "bad request")
            ) == .permanentFailure
        )
        #expect(
            FocusVideoActionService.historyReportAttemptOutcome(
                for: FocusVideoActionService.ServiceError.accountScopeChanged
            ) == .retryableFailure
        )
        #expect(
            FocusVideoActionService.historyReportAttemptOutcome(
                for: FocusVideoActionService.ServiceError.httpStatus(code: 503)
            ) == .retryableFailure
        )
        #expect(
            FocusVideoActionService.historyReportAttemptOutcome(
                for: FocusVideoActionService.ServiceError.api(code: -509, message: "busy")
            ) == .retryableFailure
        )
        #expect(
            FocusVideoActionService.historyReportAttemptOutcome(
                for: URLError(.notConnectedToInternet)
            ) == .retryableFailure
        )

        let report = FocusPendingWatchHistoryReport(
            accountScope: playbackScopeA,
            aid: 42,
            cid: 4203,
            progressSeconds: 87,
            revision: 1,
            updatedAtMilliseconds: 1
        )
        let missingCSRFService = FocusVideoActionService(
            cookieProvider: StaticPlaybackCookieProvider(
                cookies: [
                    playbackCookie(name: "DedeUserID", value: "1001"),
                    playbackCookie(name: "SESSDATA", value: "session-1001"),
                ]
            ),
            requestLoader: { _ in
                Issue.record("missing CSRF must fail before network")
                throw URLError(.badServerResponse)
            }
        )
        #expect(await missingCSRFService.attemptWatchHistory(report) == .permanentFailure)
    }

    @Test("action API policy discards permanent responses and retains transient HTTP failures")
    func actionPolicyDrivesDurableOutbox() async {
        let store = FocusPlaybackProgressStore(
            persistence: PlaybackStateMemoryPersistence()
        )
        _ = await store.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 42,
            bvid: "BV-ACTION-POLICY",
            cid: 4203,
            positionMilliseconds: 30_000
        )
        let cookieProvider = StaticPlaybackCookieProvider(
            cookies: [
                playbackCookie(name: "DedeUserID", value: "1001"),
                playbackCookie(name: "SESSDATA", value: "session-1001"),
                playbackCookie(name: "bili_jct", value: "csrf-1001"),
            ]
        )
        let permanentService = FocusVideoActionService(
            cookieProvider: cookieProvider,
            requestLoader: playbackActionResponse(
                statusCode: 200,
                body: #"{"code":-400,"message":"bad request"}"#
            )
        )

        let permanent = await store.drainPendingHistory(
            accountScope: playbackScopeA
        ) { report in
            await permanentService.attemptWatchHistory(report)
        }
        #expect(permanent.discardedCount == 1)
        #expect(!permanent.requiresRetry)

        _ = await store.recordProgressAndEnqueueHistory(
            accountScope: playbackScopeA,
            aid: 42,
            bvid: "BV-ACTION-POLICY",
            cid: 4203,
            positionMilliseconds: 45_000
        )
        let transientService = FocusVideoActionService(
            cookieProvider: cookieProvider,
            requestLoader: playbackActionResponse(
                statusCode: 503,
                body: #"{"code":-500,"message":"busy"}"#
            )
        )
        let transient = await store.drainPendingHistory(
            accountScope: playbackScopeA
        ) { report in
            await transientService.attemptWatchHistory(report)
        }

        #expect(transient.discardedCount == 0)
        #expect(transient.remainingCount == 1)
        #expect(transient.requiresRetry)
        #expect(await store.pendingHistoryReports(accountScope: playbackScopeA).count == 1)
    }
}

private actor PlaybackStateMemoryPersistence: FocusPlaybackStatePersistence {
    private var data: Data?

    init(data: Data? = nil) {
        self.data = data
    }

    func loadPlaybackState() -> Data? {
        data
    }

    func savePlaybackState(_ data: Data) {
        self.data = data
    }
}

private final class PlaybackTestClock: @unchecked Sendable {
    var now: Int64

    init(now: Int64) {
        self.now = now
    }
}

private actor PlaybackDeliveredReports {
    private(set) var values: [FocusPendingWatchHistoryReport] = []

    func append(_ report: FocusPendingWatchHistoryReport) {
        values.append(report)
    }
}

private actor SwitchablePlaybackCookieProvider: CookieSnapshotProvider {
    private var accountID: Int64

    init(accountID: Int64) {
        self.accountID = accountID
    }

    func switchAccount(to accountID: Int64) {
        self.accountID = accountID
    }

    func loadCookies() async -> [HTTPCookie] {
        [
            playbackCookie(name: "DedeUserID", value: String(accountID)),
            playbackCookie(name: "SESSDATA", value: "session-\(accountID)"),
            playbackCookie(name: "bili_jct", value: "csrf-\(accountID)"),
        ]
    }
}

private struct StaticPlaybackCookieProvider: CookieSnapshotProvider {
    let cookies: [HTTPCookie]

    func loadCookies() async -> [HTTPCookie] {
        cookies
    }
}

private actor PlaybackHistoryRequestRecorder {
    private(set) var requests: [URLRequest] = []

    func respond(to request: URLRequest) -> (Data, URLResponse) {
        requests.append(request)
        return (
            Data(#"{"code":0,"data":{}}"#.utf8),
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private func playbackCookie(
    name: String,
    value: String,
    domain: String = ".bilibili.com"
) -> HTTPCookie {
    HTTPCookie(properties: [
        .domain: domain,
        .path: "/",
        .name: name,
        .value: value,
        .secure: "TRUE",
    ])!
}

private func playbackActionResponse(
    statusCode: Int,
    body: String
) -> FocusVideoActionService.RequestLoader {
    { request in
        (
            Data(body.utf8),
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
