import CryptoKit
import Foundation

public struct FocusPlaybackAccountScope: Codable, Hashable, Sendable {
    public static let anonymous = FocusPlaybackAccountScope(storageValue: "anonymous")

    private static let historyEndpoint = BiliAPIContractCatalog.require(
        "video.operate.report_history"
    ).url
    private static let canonicalFingerprintCookieNames = [
        "dedeuserid__ckmd5": "DedeUserID__ckMd5",
        "sessdata": "SESSDATA",
    ]
    private static let scopeVersion = "account-v2"

    private let storageValue: String

    public static func accountID(_ accountID: Int64) -> FocusPlaybackAccountScope {
        guard accountID > 0 else {
            return .anonymous
        }
        return scope(
            identityMaterial: lengthPrefixed(
                name: "mid",
                value: String(accountID)
            )
        )
    }

    public static func resolve(cookies: [HTTPCookie]) -> FocusPlaybackAccountScope {
        let matchingCookies = CookieRequestPolicy.cookies(
            cookies,
            matching: historyEndpoint
        )

        let accountIDs = Set(
            matchingCookies.compactMap { cookie -> String? in
                guard cookie.name.caseInsensitiveCompare("DedeUserID") == .orderedSame else {
                    return nil
                }
                let value = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        ).sorted()
        if accountIDs.count == 1, let accountID = accountIDs.first {
            return scope(
                identityMaterial: lengthPrefixed(
                    name: "mid",
                    value: accountID
                )
            )
        }

        let identityComponents = Set(
            matchingCookies.compactMap { cookie -> IdentityComponent? in
                guard
                    let normalizedName = canonicalFingerprintCookieNames[
                        cookie.name.lowercased()
                    ],
                    !cookie.value.isEmpty
                else {
                    return nil
                }
                return IdentityComponent(name: normalizedName, value: cookie.value)
            }
        ).sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.value < rhs.value
            }
            return lhs.name < rhs.name
        }
        guard !identityComponents.isEmpty else {
            return .anonymous
        }

        let identityMaterial = identityComponents.map {
            lengthPrefixed(name: $0.name, value: $0.value)
        }.joined()
        return scope(identityMaterial: identityMaterial)
    }

    private static func lengthPrefixed(name: String, value: String) -> String {
        "\(name.utf8.count):\(name):\(value.utf8.count):\(value);"
    }

    private static func scope(identityMaterial: String) -> FocusPlaybackAccountScope {
        let digest = SHA256.hash(data: Data(identityMaterial.utf8))
        let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
        return FocusPlaybackAccountScope(
            storageValue: "\(scopeVersion)-\(hexDigest)"
        )
    }

    private struct IdentityComponent: Hashable {
        let name: String
        let value: String
    }
}

public struct FocusPlaybackProgressEntry: Codable, Equatable, Sendable {
    public let accountScope: FocusPlaybackAccountScope
    public let aid: Int64
    public let bvid: String
    public let cid: Int64
    public let positionMilliseconds: Int64
    public let updatedAtMilliseconds: Int64

    public init(
        accountScope: FocusPlaybackAccountScope,
        aid: Int64,
        bvid: String,
        cid: Int64,
        positionMilliseconds: Int64,
        updatedAtMilliseconds: Int64
    ) {
        self.accountScope = accountScope
        self.aid = aid
        self.bvid = bvid
        self.cid = cid
        self.positionMilliseconds = max(positionMilliseconds, 0)
        self.updatedAtMilliseconds = updatedAtMilliseconds
    }

    public var playbackResume: FocusVideoPlaybackResume {
        FocusVideoPlaybackResume(
            cid: cid,
            positionMilliseconds: positionMilliseconds
        )
    }
}

public struct FocusPendingWatchHistoryReport: Codable, Equatable, Sendable {
    public let accountScope: FocusPlaybackAccountScope
    public let aid: Int64
    public let cid: Int64
    public let progressSeconds: Int64
    public let revision: UInt64
    public let updatedAtMilliseconds: Int64

    public init(
        accountScope: FocusPlaybackAccountScope,
        aid: Int64,
        cid: Int64,
        progressSeconds: Int64,
        revision: UInt64,
        updatedAtMilliseconds: Int64
    ) {
        self.accountScope = accountScope
        self.aid = aid
        self.cid = cid
        self.progressSeconds = max(progressSeconds, 0)
        self.revision = revision
        self.updatedAtMilliseconds = updatedAtMilliseconds
    }
}

public enum FocusHistoryReportAttemptOutcome: Equatable, Sendable {
    case delivered
    case retryableFailure
    case permanentFailure
}

public struct FocusHistoryOutboxDrainOutcome: Equatable, Sendable {
    public static let noWork = FocusHistoryOutboxDrainOutcome()

    public let deliveredCount: Int
    public let discardedCount: Int
    public let remainingCount: Int

    public init(
        deliveredCount: Int = 0,
        discardedCount: Int = 0,
        remainingCount: Int = 0
    ) {
        self.deliveredCount = max(deliveredCount, 0)
        self.discardedCount = max(discardedCount, 0)
        self.remainingCount = max(remainingCount, 0)
    }

    public var requiresRetry: Bool {
        remainingCount > 0
    }
}

public protocol FocusPlaybackStatePersistence: Actor {
    func loadPlaybackState() -> Data?
    func savePlaybackState(_ data: Data)
}

public actor FocusUserDefaultsPlaybackStatePersistence: FocusPlaybackStatePersistence {
    public static let standard = FocusUserDefaultsPlaybackStatePersistence()

    private let userDefaults: UserDefaults
    private let storageKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "org.bilibilifocus.playback-state.v2"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    public func loadPlaybackState() -> Data? {
        userDefaults.data(forKey: storageKey)
    }

    public func savePlaybackState(_ data: Data) {
        userDefaults.set(data, forKey: storageKey)
    }
}

public enum FocusPlaybackResumeResolver {
    public static func isMeaningfulResume(_ resume: FocusVideoPlaybackResume) -> Bool {
        resume.cid > 0 && resume.positionMilliseconds >= 5_000
    }

    public static func preferredResume(
        local: FocusPlaybackProgressEntry?,
        server: FocusVideoPlaybackResume?
    ) -> FocusVideoPlaybackResume? {
        local?.playbackResume ?? server
    }

    public static func initialPositionMilliseconds(
        local: FocusPlaybackProgressEntry?,
        server: FocusVideoPlaybackResume?,
        selectedCID: Int64,
        durationSeconds: Int64
    ) -> Int64 {
        guard let resume = preferredResume(local: local, server: server) else {
            return 0
        }
        return FocusVideoPlaybackResumePolicy.initialPositionMilliseconds(
            resume: resume,
            selectedCID: selectedCID,
            durationSeconds: durationSeconds
        )
    }
}

public actor FocusPlaybackProgressStore {
    public typealias Clock = @Sendable () -> Int64
    public typealias HistoryReporter = @Sendable (
        FocusPendingWatchHistoryReport
    ) async -> FocusHistoryReportAttemptOutcome

    public static let shared = FocusPlaybackProgressStore(
        persistence: FocusUserDefaultsPlaybackStatePersistence.standard
    )

    private struct PersistedState: Codable, Sendable {
        var schemaVersion = 2
        var nextRevision: UInt64 = 1
        var progressEntries: [FocusPlaybackProgressEntry] = []
        var pendingReports: [FocusPendingWatchHistoryReport] = []
    }

    private struct ProgressKey: Hashable {
        let accountScope: FocusPlaybackAccountScope
        let aid: Int64
        let bvid: String
        let cid: Int64
    }

    private struct HistoryKey: Hashable {
        let accountScope: FocusPlaybackAccountScope
        let aid: Int64
        let cid: Int64
    }

    private let persistence: any FocusPlaybackStatePersistence
    private let maxProgressEntries: Int
    private let maxPendingReports: Int
    private let recentProgressLifetimeMilliseconds: Int64
    private let clock: Clock
    private var state = PersistedState()
    private var hasLoadedState = false
    private var stateLoadTask: Task<PersistedState?, Never>?
    private var drainingHistoryScopes: Set<FocusPlaybackAccountScope> = []

    public init(
        persistence: any FocusPlaybackStatePersistence,
        maxProgressEntries: Int = 120,
        maxPendingReports: Int = 120,
        recentProgressLifetimeMilliseconds: Int64 = 30 * 24 * 60 * 60 * 1_000,
        clock: @escaping Clock = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.persistence = persistence
        self.maxProgressEntries = max(maxProgressEntries, 1)
        self.maxPendingReports = max(maxPendingReports, 1)
        self.recentProgressLifetimeMilliseconds = max(recentProgressLifetimeMilliseconds, 0)
        self.clock = clock
    }

    public func recentProgress(
        accountScope: FocusPlaybackAccountScope,
        aid: Int64,
        bvid: String,
        cid: Int64? = nil
    ) async -> FocusPlaybackProgressEntry? {
        await loadStateIfNeeded()
        let now = clock()
        let normalizedBVID = Self.normalizedBVID(bvid)

        return state.progressEntries
            .lazy
            .filter { $0.accountScope == accountScope }
            .filter { entry in
                Self.matchesVideo(
                    entry,
                    aid: aid,
                    normalizedBVID: normalizedBVID
                )
            }
            .filter { entry in
                guard let cid else {
                    return true
                }
                return entry.cid == cid
            }
            .filter { entry in
                guard self.recentProgressLifetimeMilliseconds > 0 else {
                    return entry.updatedAtMilliseconds >= now
                }
                let age = now.subtractingReportingOverflow(entry.updatedAtMilliseconds)
                return !age.overflow && age.partialValue >= 0
                    && age.partialValue <= self.recentProgressLifetimeMilliseconds
            }
            .max { lhs, rhs in
                if lhs.updatedAtMilliseconds != rhs.updatedAtMilliseconds {
                    return lhs.updatedAtMilliseconds < rhs.updatedAtMilliseconds
                }
                return lhs.cid < rhs.cid
            }
    }

    @discardableResult
    public func recordProgress(
        accountScope: FocusPlaybackAccountScope,
        aid: Int64,
        bvid: String,
        cid: Int64,
        positionMilliseconds: Int64
    ) async -> FocusPlaybackProgressEntry? {
        guard aid > 0, cid > 0 else {
            return nil
        }
        await loadStateIfNeeded()

        let progress = upsertProgress(
            accountScope: accountScope,
            aid: aid,
            bvid: bvid,
            cid: cid,
            positionMilliseconds: positionMilliseconds,
            updatedAtMilliseconds: clock()
        )
        await persistState()
        return progress
    }

    @discardableResult
    public func recordProgressAndEnqueueHistory(
        accountScope: FocusPlaybackAccountScope,
        aid: Int64,
        bvid: String,
        cid: Int64,
        positionMilliseconds: Int64
    ) async -> FocusPendingWatchHistoryReport? {
        guard aid > 0, cid > 0 else {
            return nil
        }
        await loadStateIfNeeded()

        let now = clock()
        _ = upsertProgress(
            accountScope: accountScope,
            aid: aid,
            bvid: bvid,
            cid: cid,
            positionMilliseconds: positionMilliseconds,
            updatedAtMilliseconds: now
        )
        let report = upsertPendingHistory(
            accountScope: accountScope,
            aid: aid,
            cid: cid,
            progressSeconds: max(positionMilliseconds, 0) / 1_000,
            updatedAtMilliseconds: now
        )
        await persistState()
        return report
    }

    public func pendingHistoryReports(
        accountScope: FocusPlaybackAccountScope
    ) async -> [FocusPendingWatchHistoryReport] {
        await loadStateIfNeeded()
        return sortedPendingReports(accountScope: accountScope)
    }

    @discardableResult
    public func acknowledgeHistoryReport(
        accountScope: FocusPlaybackAccountScope,
        aid: Int64,
        cid: Int64,
        revision: UInt64
    ) async -> Bool {
        await loadStateIfNeeded()
        guard let index = state.pendingReports.firstIndex(where: {
            $0.accountScope == accountScope
                && $0.aid == aid
                && $0.cid == cid
                && $0.revision == revision
        }) else {
            return false
        }
        state.pendingReports.remove(at: index)
        await persistState()
        return true
    }

    @discardableResult
    public func drainPendingHistory(
        accountScope: FocusPlaybackAccountScope,
        using reporter: @escaping HistoryReporter
    ) async -> FocusHistoryOutboxDrainOutcome {
        await loadStateIfNeeded()
        guard accountScope != .anonymous else {
            return .noWork
        }
        guard drainingHistoryScopes.insert(accountScope).inserted else {
            return FocusHistoryOutboxDrainOutcome(
                remainingCount: sortedPendingReports(accountScope: accountScope).count
            )
        }
        defer {
            drainingHistoryScopes.remove(accountScope)
        }

        var deliveredCount = 0
        var discardedCount = 0
        while let report = sortedPendingReports(accountScope: accountScope).first {
            guard !Task.isCancelled else {
                break
            }

            let attempt = await reporter(report)
            switch attempt {
            case .delivered:
                let acknowledged = await acknowledgeHistoryReport(
                    accountScope: accountScope,
                    aid: report.aid,
                    cid: report.cid,
                    revision: report.revision
                )
                if acknowledged {
                    deliveredCount += 1
                }
            case .permanentFailure:
                let acknowledged = await acknowledgeHistoryReport(
                    accountScope: accountScope,
                    aid: report.aid,
                    cid: report.cid,
                    revision: report.revision
                )
                if acknowledged {
                    discardedCount += 1
                }
            case .retryableFailure:
                return FocusHistoryOutboxDrainOutcome(
                    deliveredCount: deliveredCount,
                    discardedCount: discardedCount,
                    remainingCount: sortedPendingReports(accountScope: accountScope).count
                )
            }
        }

        return FocusHistoryOutboxDrainOutcome(
            deliveredCount: deliveredCount,
            discardedCount: discardedCount,
            remainingCount: sortedPendingReports(accountScope: accountScope).count
        )
    }

    private func loadStateIfNeeded() async {
        guard !hasLoadedState else {
            return
        }

        let task: Task<PersistedState?, Never>
        if let stateLoadTask {
            task = stateLoadTask
        } else {
            let persistence = persistence
            let newTask = Task<PersistedState?, Never> {
                guard let data = await persistence.loadPlaybackState() else {
                    return nil
                }
                return try? JSONDecoder().decode(PersistedState.self, from: data)
            }
            stateLoadTask = newTask
            task = newTask
        }

        let decoded = await task.value
        guard !hasLoadedState else {
            return
        }
        hasLoadedState = true
        stateLoadTask = nil
        if let decoded, decoded.schemaVersion == 2 {
            state = decoded
            sanitizeLoadedState()
            await persistState()
        }
    }

    private func sanitizeLoadedState() {
        state.progressEntries = state.progressEntries.filter {
            $0.aid > 0 && $0.cid > 0 && $0.positionMilliseconds >= 0
        }
        state.pendingReports = state.pendingReports.filter {
            $0.accountScope != .anonymous
                && $0.aid > 0
                && $0.cid > 0
                && $0.progressSeconds >= 0
                && $0.revision > 0
        }

        var uniqueProgress: [ProgressKey: FocusPlaybackProgressEntry] = [:]
        for entry in state.progressEntries {
            let key = ProgressKey(
                accountScope: entry.accountScope,
                aid: entry.aid,
                bvid: Self.normalizedBVID(entry.bvid),
                cid: entry.cid
            )
            if let current = uniqueProgress[key],
               current.updatedAtMilliseconds > entry.updatedAtMilliseconds
            {
                continue
            }
            uniqueProgress[key] = entry
        }
        state.progressEntries = Array(uniqueProgress.values)

        var uniqueReports: [HistoryKey: FocusPendingWatchHistoryReport] = [:]
        for report in state.pendingReports {
            let key = HistoryKey(
                accountScope: report.accountScope,
                aid: report.aid,
                cid: report.cid
            )
            if let current = uniqueReports[key], current.revision > report.revision {
                continue
            }
            uniqueReports[key] = report
        }
        state.pendingReports = Array(uniqueReports.values)
        pruneProgressEntries()
        prunePendingReports()

        let largestRevision = state.pendingReports.map(\.revision).max() ?? 0
        if state.nextRevision <= largestRevision {
            state.nextRevision = largestRevision == UInt64.max
                ? 1
                : largestRevision + 1
        }
        if state.nextRevision == 0 {
            state.nextRevision = 1
        }
    }

    private func nextRevision() -> UInt64 {
        let revision = state.nextRevision == 0 ? 1 : state.nextRevision
        state.nextRevision = revision == UInt64.max ? 1 : revision + 1
        return revision
    }

    @discardableResult
    private func upsertProgress(
        accountScope: FocusPlaybackAccountScope,
        aid: Int64,
        bvid: String,
        cid: Int64,
        positionMilliseconds: Int64,
        updatedAtMilliseconds: Int64
    ) -> FocusPlaybackProgressEntry {
        let normalizedBVID = Self.normalizedBVID(bvid)
        let progress = FocusPlaybackProgressEntry(
            accountScope: accountScope,
            aid: aid,
            bvid: normalizedBVID,
            cid: cid,
            positionMilliseconds: positionMilliseconds,
            updatedAtMilliseconds: updatedAtMilliseconds
        )
        let progressKey = ProgressKey(
            accountScope: accountScope,
            aid: aid,
            bvid: normalizedBVID,
            cid: cid
        )
        state.progressEntries.removeAll {
            ProgressKey(
                accountScope: $0.accountScope,
                aid: $0.aid,
                bvid: Self.normalizedBVID($0.bvid),
                cid: $0.cid
            ) == progressKey
        }
        state.progressEntries.append(progress)
        pruneProgressEntries()
        return progress
    }

    private func upsertPendingHistory(
        accountScope: FocusPlaybackAccountScope,
        aid: Int64,
        cid: Int64,
        progressSeconds: Int64,
        updatedAtMilliseconds: Int64
    ) -> FocusPendingWatchHistoryReport? {
        guard accountScope != .anonymous else {
            return nil
        }

        let report = FocusPendingWatchHistoryReport(
            accountScope: accountScope,
            aid: aid,
            cid: cid,
            progressSeconds: progressSeconds,
            revision: nextRevision(),
            updatedAtMilliseconds: updatedAtMilliseconds
        )
        let historyKey = HistoryKey(
            accountScope: accountScope,
            aid: aid,
            cid: cid
        )
        state.pendingReports.removeAll {
            HistoryKey(
                accountScope: $0.accountScope,
                aid: $0.aid,
                cid: $0.cid
            ) == historyKey
        }
        state.pendingReports.append(report)
        prunePendingReports()
        return report
    }

    private func pruneProgressEntries() {
        guard state.progressEntries.count > maxProgressEntries else {
            return
        }
        state.progressEntries = Array(
            state.progressEntries
                .sorted {
                    if $0.updatedAtMilliseconds != $1.updatedAtMilliseconds {
                        return $0.updatedAtMilliseconds > $1.updatedAtMilliseconds
                    }
                    return $0.cid > $1.cid
                }
                .prefix(maxProgressEntries)
        )
    }

    private func prunePendingReports() {
        guard state.pendingReports.count > maxPendingReports else {
            return
        }
        state.pendingReports = Array(
            state.pendingReports
                .sorted {
                    if $0.updatedAtMilliseconds != $1.updatedAtMilliseconds {
                        return $0.updatedAtMilliseconds > $1.updatedAtMilliseconds
                    }
                    return $0.revision > $1.revision
                }
                .prefix(maxPendingReports)
        )
    }

    private func sortedPendingReports(
        accountScope: FocusPlaybackAccountScope
    ) -> [FocusPendingWatchHistoryReport] {
        state.pendingReports.filter {
            $0.accountScope == accountScope
        }.sorted {
            if $0.updatedAtMilliseconds != $1.updatedAtMilliseconds {
                return $0.updatedAtMilliseconds < $1.updatedAtMilliseconds
            }
            return $0.revision < $1.revision
        }
    }

    private func persistState() async {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        await persistence.savePlaybackState(data)
    }

    private nonisolated static func normalizedBVID(_ bvid: String) -> String {
        bvid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private nonisolated static func matchesVideo(
        _ entry: FocusPlaybackProgressEntry,
        aid: Int64,
        normalizedBVID normalizedRequestedBVID: String
    ) -> Bool {
        if aid > 0 {
            return entry.aid == aid
        }
        return !normalizedRequestedBVID.isEmpty
            && normalizedBVID(entry.bvid) == normalizedRequestedBVID
    }
}
