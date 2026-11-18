import Foundation

public struct FocusCursorPage<Item: Sendable, Cursor: Sendable>: Sendable {
    public let items: [Item]
    public let nextCursor: Cursor?

    public init(items: [Item], nextCursor: Cursor?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

public struct FocusPagedState<Item: Sendable>: Sendable {
    public var items: [Item]
    public var isRefreshing: Bool
    public var isAppending: Bool
    public var endReached: Bool
    public var refreshError: String?
    public var appendError: String?

    public init(
        items: [Item] = [],
        isRefreshing: Bool = false,
        isAppending: Bool = false,
        endReached: Bool = false,
        refreshError: String? = nil,
        appendError: String? = nil
    ) {
        self.items = items
        self.isRefreshing = isRefreshing
        self.isAppending = isAppending
        self.endReached = endReached
        self.refreshError = refreshError
        self.appendError = appendError
    }
}

public actor FocusCursorPager<
    Item: Sendable,
    Cursor: Hashable & Sendable,
    Key: Hashable & Sendable
> {
    public typealias Loader = @Sendable (Cursor?) async throws -> FocusCursorPage<Item, Cursor>

    private let firstCursor: Cursor?
    private let keyOf: @Sendable (Item) -> Key
    private let loader: Loader
    private var generation: UInt64 = 0
    private var nextCursor: Cursor?
    private var currentState = FocusPagedState<Item>()

    public init(
        firstCursor: Cursor?,
        keyOf: @escaping @Sendable (Item) -> Key,
        loader: @escaping Loader
    ) {
        self.firstCursor = firstCursor
        self.nextCursor = firstCursor
        self.keyOf = keyOf
        self.loader = loader
    }

    public var state: FocusPagedState<Item> {
        currentState
    }

    public func refresh() async throws {
        generation &+= 1
        let requestGeneration = generation
        nextCursor = firstCursor
        currentState.isRefreshing = true
        currentState.isAppending = false
        currentState.refreshError = nil
        currentState.appendError = nil

        do {
            let page = try await loader(firstCursor)
            guard requestGeneration == generation else {
                return
            }
            nextCursor = page.nextCursor
            currentState = FocusPagedState(
                items: deduplicated(page.items),
                endReached: page.nextCursor == nil || page.nextCursor == firstCursor
            )
        } catch is CancellationError {
            if requestGeneration == generation {
                currentState.isRefreshing = false
            }
            throw CancellationError()
        } catch {
            if requestGeneration == generation {
                currentState.isRefreshing = false
                currentState.refreshError = error.localizedDescription
            }
        }
    }

    public func append() async throws {
        guard
            !currentState.isRefreshing,
            !currentState.isAppending,
            !currentState.endReached,
            let requestCursor = nextCursor
        else {
            return
        }

        let requestGeneration = generation
        currentState.isAppending = true
        currentState.appendError = nil
        do {
            let page = try await loader(requestCursor)
            guard
                requestGeneration == generation,
                nextCursor == requestCursor
            else {
                return
            }

            var existingKeys = Set(currentState.items.map(keyOf))
            let additions = page.items.filter { existingKeys.insert(keyOf($0)).inserted }
            nextCursor = page.nextCursor
            currentState.items.append(contentsOf: additions)
            currentState.isAppending = false
            currentState.endReached = page.nextCursor == nil || page.nextCursor == requestCursor
        } catch is CancellationError {
            if requestGeneration == generation {
                currentState.isAppending = false
            }
            throw CancellationError()
        } catch {
            if requestGeneration == generation {
                currentState.isAppending = false
                currentState.appendError = error.localizedDescription
            }
        }
    }

    private func deduplicated(_ items: [Item]) -> [Item] {
        var keys = Set<Key>()
        return items.filter { keys.insert(keyOf($0)).inserted }
    }
}
