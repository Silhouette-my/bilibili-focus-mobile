import Foundation

/// Disposable feed data only. Credentials, preferences and playback history are
/// deliberately outside this directory and are never cleared by this store.
public actor DynamicFeedSnapshotStore {
    public struct Snapshot: Codable, Sendable {
        public let cards: [DynamicCard]
        public let nextOffset: String?
        public let savedAt: Date
    }
    private struct Entry: Codable {
        let scope: FocusPlaybackAccountScope
        let snapshot: Snapshot
    }
    public static let shared = DynamicFeedSnapshotStore(
        fileURL: ProcessInfo.processInfo.environment["FOCUS_FIXTURE_TESTS"] == "1" ? nil :
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("FocusDynamicFeed", isDirectory: true).appendingPathComponent("snapshots-v1.json")
    )
    private let fileURL: URL?
    private var entries: [Entry]?
    private var revision: UInt64 = 0
    private let maximumBytes = 8 * 1024 * 1024
    public init(fileURL: URL?) { self.fileURL = fileURL }
    public func writeRevision() -> UInt64 { revision }

    public func load(scope: FocusPlaybackAccountScope, now: Date = Date()) -> Snapshot? {
        guard fileURL != nil, scope != .anonymous else { return nil }
        readIfNeeded()
        prune(now: now)
        return entries?.first { $0.scope == scope }?.snapshot
    }

    public func save(cards: [DynamicCard], nextOffset: String?, scope: FocusPlaybackAccountScope,
                     revision expectedRevision: UInt64, now: Date = Date()) throws {
        try Task.checkCancellation()
        guard fileURL != nil, expectedRevision == revision, scope != .anonymous, cards.count <= 300 else { return }
        readIfNeeded()
        prune(now: now)
        entries?.removeAll { $0.scope == scope }
        // Retain only complete page boundaries, so no discarded row is skipped
        // by a cursor beyond the persisted portion of a long session.
        let snapshot = Snapshot(cards: cards, nextOffset: nextOffset, savedAt: now)
        entries?.append(Entry(scope: scope, snapshot: snapshot))
        entries = Array((entries ?? []).sorted { $0.snapshot.savedAt > $1.snapshot.savedAt }.prefix(3))
        try persist()
    }

    public func clear() throws {
        revision &+= 1
        entries = []
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func prune(now: Date) {
        entries?.removeAll { now.timeIntervalSince($0.snapshot.savedAt) > 7 * 24 * 3600 }
    }
    private func readIfNeeded() {
        guard entries == nil else { return }
        entries = []
        guard let fileURL else { return }
        // Cache corruption, schema changes or OS eviction are a cache miss.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data),
              decoded.count <= 3, decoded.allSatisfy({ $0.snapshot.cards.count <= 300 }) else { return }
        entries = decoded
    }
    private func persist() throws {
        guard let fileURL else { return }
        var data = try JSONEncoder().encode(entries ?? [])
        while data.count > maximumBytes, !(entries ?? []).isEmpty {
            entries?.removeLast()
            data = try JSONEncoder().encode(entries ?? [])
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
