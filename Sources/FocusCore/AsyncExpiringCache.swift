import Foundation

public enum FocusAsyncDeadlineError: Error, Equatable, Sendable { case timedOut }

/// A deadline race whose scope does not wait for an uncooperative cancelled
/// child. Late results can only resolve this already-completed private box;
/// they cannot seek a player or replace page state. The transport still owns
/// its own resource timeout. Cancellation of a shared cache consumer does not
/// cancel the underlying request needed by another consumer.
public enum FocusAsyncDeadline {
    public typealias Sleeper = @Sendable (UInt64) async throws -> Void
    public static func value<Value: Sendable>(
        timeoutNanoseconds: UInt64,
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) },
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let race = DeadlineRace<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.start(continuation: continuation, timeoutNanoseconds: timeoutNanoseconds,
                           sleeper: sleeper, operation: operation)
            }
        } onCancel: { race.finish(.failure(CancellationError())) }
    }
}

private final class DeadlineRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    func start(
        continuation: CheckedContinuation<Value, Error>, timeoutNanoseconds: UInt64,
        sleeper: @escaping FocusAsyncDeadline.Sleeper,
        operation: @escaping @Sendable () async throws -> Value
    ) {
        let previous: Result<Value, Error>? = lock.withLock {
            if let result { return result }
            self.continuation = continuation
            return nil
        }
        if let previous { continuation.resume(with: previous); return }
        let work = Task {
            do { self.finish(.success(try await operation())) }
            catch { self.finish(.failure(error)) }
        }
        let timer = Task {
            do {
                try await sleeper(timeoutNanoseconds)
                try Task.checkCancellation()
                self.finish(.failure(FocusAsyncDeadlineError.timedOut))
            } catch { /* The other result or the caller already completed us. */ }
        }
        let shouldCancel = lock.withLock {
            guard result == nil else { return true }
            tasks = [work, timer]
            return false
        }
        if shouldCancel { work.cancel(); timer.cancel() }
    }

    func finish(_ result: Result<Value, Error>) {
        let completion: (CheckedContinuation<Value, Error>?, [Task<Void, Never>])? = lock.withLock {
            guard self.result == nil else { return nil }
            self.result = result
            let completion = (continuation, tasks)
            continuation = nil; tasks.removeAll()
            return completion
        }
        guard let (continuation, tasks) = completion else { return }
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}

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
    // Actor-confined tokens live only with an entry/flight or its consumers;
    // there is no ever-growing per-key revision dictionary.
    private final class Generation { var isValid = true; var consumers = 0 }
    private struct Entry {
        let value: Value
        let freshUntil: Date
        let staleUntil: Date
        let generation: Generation
    }
    private enum Outcome: Sendable { case loaded(Value), stale(Value, Error) }
    private struct Flight {
        let id: UUID
        let generation: Generation
        let forceRefresh: Bool
        let task: Task<Outcome, Error>
    }

    private let maximumEntries: Int
    private let now: @Sendable () -> Date
    private var entries: [Key: Entry] = [:]
    private var accessOrder: [Key] = []
    private var inFlight: [Key: Flight] = [:]

    public init(
        maximumEntries: Int = 100,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        precondition(maximumEntries > 0)
        self.maximumEntries = maximumEntries
        self.now = now
    }

    var activeConsumerCount: Int { inFlight.values.reduce(0) { $0 + $1.generation.consumers } }

    public func value(
        for key: Key,
        policy: FocusCachePolicy,
        forceRefresh: Bool = false,
        returnsStaleOnError: Bool = true,
        canUseStaleOnError: @escaping @Sendable (Error) -> Bool = { error in
            !(error is CancellationError) && (error as? URLError)?.code != .cancelled
        },
        loader: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        if !forceRefresh, let entry = entries[key], now() < entry.freshUntil {
            touch(key)
            return entry.value
        }
        if forceRefresh, let previous = inFlight[key], !previous.forceRefresh {
            previous.generation.isValid = false
            previous.task.cancel()
            inFlight[key] = nil
        }
        let flight: Flight
        if let existing = inFlight[key] {
            flight = existing
        } else {
            let staleValue = entries[key]?.value
            let staleUntil = entries[key]?.staleUntil
            let clock = now
            let task = Task {
                do { return Outcome.loaded(try await loader()) }
                catch {
                    try Task.checkCancellation()
                    guard canUseStaleOnError(error), let staleValue, let staleUntil,
                          clock() < staleUntil else { throw error }
                    return Outcome.stale(staleValue, error)
                }
            }
            flight = Flight(id: UUID(), generation: Generation(), forceRefresh: forceRefresh, task: task)
            inFlight[key] = flight
        }
        flight.generation.consumers += 1
        defer { flight.generation.consumers -= 1 }
        do {
            let outcome = try await flight.task.value
            guard flight.generation.isValid else { throw CancellationError() }
            let value: Value
            switch outcome {
            case let .loaded(loaded):
                value = loaded
                if inFlight[key]?.id == flight.id {
                    let loadedAt = now()
                    entries[key]?.generation.isValid = false
                    put(Entry(value: loaded, freshUntil: loadedAt.addingTimeInterval(policy.freshFor),
                              staleUntil: loadedAt.addingTimeInterval(policy.freshFor + policy.staleIfErrorFor),
                              generation: flight.generation), for: key)
                }
            case let .stale(stale, error):
                // A refresh UI can surface the failure while retaining its rows
                // and the fallback entry. This is per consumer, not per flight.
                guard returnsStaleOnError else { throw error }
                value = stale
                if inFlight[key]?.id == flight.id, let entry = entries[key] {
                    entry.generation.isValid = false
                    put(Entry(value: stale, freshUntil: entry.freshUntil, staleUntil: entry.staleUntil,
                              generation: flight.generation), for: key)
                }
            }
            if inFlight[key]?.id == flight.id { inFlight[key] = nil }
            try Task.checkCancellation()
            return value
        } catch {
            guard flight.generation.isValid else { throw CancellationError() }
            if inFlight[key]?.id == flight.id {
                inFlight[key] = nil
                if !(error is CancellationError), !canUseStaleOnError(error) {
                    entries[key]?.generation.isValid = false
                    entries[key] = nil
                    accessOrder.removeAll { $0 == key }
                }
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
        invalidate(key)
        let insertionDate = now()
        put(
            Entry(
                value: value,
                freshUntil: insertionDate.addingTimeInterval(policy.freshFor),
                staleUntil: insertionDate.addingTimeInterval(
                    policy.freshFor + policy.staleIfErrorFor
                ),
                generation: Generation()
            ),
            for: key
        )
    }

    public func invalidate(_ key: Key) {
        entries[key]?.generation.isValid = false
        inFlight[key]?.generation.isValid = false
        inFlight[key]?.task.cancel()
        inFlight[key] = nil
        entries[key] = nil
        accessOrder.removeAll { $0 == key }
    }

    public func clear() {
        entries.values.forEach { $0.generation.isValid = false }
        inFlight.values.forEach { $0.generation.isValid = false; $0.task.cancel() }
        inFlight.removeAll()
        entries.removeAll()
        accessOrder.removeAll()
    }

    private func put(_ entry: Entry, for key: Key) {
        entries[key] = entry
        touch(key)
        while accessOrder.count > maximumEntries, let oldest = accessOrder.first {
            entries[oldest]?.generation.isValid = false
            entries[oldest] = nil
            accessOrder.removeFirst()
        }
    }

    private func touch(_ key: Key) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
}
