import Foundation

public struct FocusCachePolicy: Equatable, Sendable {
    public let freshFor: TimeInterval
    public let staleIfErrorFor: TimeInterval

    public init(freshFor: TimeInterval, staleIfErrorFor: TimeInterval = 0) {
        precondition(freshFor >= 0)
        precondition(staleIfErrorFor >= 0)
        self.freshFor = freshFor
        self.staleIfErrorFor = staleIfErrorFor
    }
}

public actor AsyncExpiringCache<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry: Sendable {
        let value: Value
        let freshUntil: Date
        let staleUntil: Date
    }

    private let maximumEntries: Int
    private let now: @Sendable () -> Date
    private var entries: [Key: Entry] = [:]
    private var accessOrder: [Key] = []
    private var inFlight: [Key: Task<Value, Error>] = [:]

    public init(
        maximumEntries: Int = 100,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        precondition(maximumEntries > 0)
        self.maximumEntries = maximumEntries
        self.now = now
    }

    public func value(
        for key: Key,
        policy: FocusCachePolicy,
        loader: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let requestDate = now()
        if let entry = entries[key], requestDate < entry.freshUntil {
            touch(key)
            return entry.value
        }

        let stale = entries[key].flatMap { requestDate < $0.staleUntil ? $0 : nil }
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task { try await loader() }
        inFlight[key] = task
        do {
            let loaded = try await task.value
            let loadedAt = now()
            put(
                Entry(
                    value: loaded,
                    freshUntil: loadedAt.addingTimeInterval(policy.freshFor),
                    staleUntil: loadedAt.addingTimeInterval(
                        policy.freshFor + policy.staleIfErrorFor
                    )
                ),
                for: key
            )
            inFlight[key] = nil
            return loaded
        } catch is CancellationError {
            inFlight[key] = nil
            task.cancel()
            throw CancellationError()
        } catch {
            inFlight[key] = nil
            if let stale {
                touch(key)
                return stale.value
            }
            throw error
        }
    }

    public func cachedValue(for key: Key, allowStale: Bool = false) -> Value? {
        guard let entry = entries[key] else {
            return nil
        }
        let deadline = allowStale ? entry.staleUntil : entry.freshUntil
        guard now() < deadline else {
            return nil
        }
        touch(key)
        return entry.value
    }

    public func insert(_ value: Value, for key: Key, policy: FocusCachePolicy) {
        let insertionDate = now()
        put(
            Entry(
                value: value,
                freshUntil: insertionDate.addingTimeInterval(policy.freshFor),
                staleUntil: insertionDate.addingTimeInterval(
                    policy.freshFor + policy.staleIfErrorFor
                )
            ),
            for: key
        )
    }

    public func invalidate(_ key: Key) {
        entries[key] = nil
        accessOrder.removeAll { $0 == key }
    }

    public func clear() {
        entries.removeAll()
        accessOrder.removeAll()
    }

    private func put(_ entry: Entry, for key: Key) {
        entries[key] = entry
        touch(key)
        while accessOrder.count > maximumEntries, let oldest = accessOrder.first {
            entries[oldest] = nil
            accessOrder.removeFirst()
        }
    }

    private func touch(_ key: Key) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
}
