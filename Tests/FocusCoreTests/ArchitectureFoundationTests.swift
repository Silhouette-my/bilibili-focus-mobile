import Foundation
import Testing
@testable import FocusCore

@Suite("4-12 week architecture foundations")
struct ArchitectureFoundationTests {
    @Test("cache coalesces concurrent misses and uses stale-if-error")
    func cacheCoalescesAndFallsBack() async throws {
        final class ClockBox: @unchecked Sendable {
            var date = Date(timeIntervalSince1970: 1_000)
        }
        let clock = ClockBox()
        let cache = AsyncExpiringCache<String, String>(now: { clock.date })
        let policy = FocusCachePolicy(freshFor: 10, staleIfErrorFor: 20)

        let values = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0 ..< 2 {
                group.addTask {
                    try await cache.value(for: "video", policy: policy) {
                        try await Task.sleep(nanoseconds: 10_000_000)
                        return "cached"
                    }
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(values == ["cached", "cached"])

        clock.date = clock.date.addingTimeInterval(11)
        let stale = try await cache.value(for: "video", policy: policy) {
            throw TestFailure.offline
        }
        #expect(stale == "cached")
    }

    @Test("cursor pager deduplicates and terminates repeated cursor")
    func pagerDeduplicates() async throws {
        struct Item: Sendable {
            let id: Int
        }
        let pager = FocusCursorPager<Item, String, Int>(
            firstCursor: "first",
            keyOf: \.id
        ) { cursor in
            if cursor == "first" {
                return FocusCursorPage(items: [Item(id: 1), Item(id: 2)], nextCursor: "next")
            }
            return FocusCursorPage(items: [Item(id: 2), Item(id: 3)], nextCursor: "next")
        }

        try await pager.refresh()
        try await pager.append()
        let state = await pager.state

        #expect(state.items.map(\.id) == [1, 2, 3])
        #expect(state.endReached)
    }

    @Test("transport retries GET, never retries POST, and redacts diagnostics")
    func transportPolicyAndDiagnostics() async throws {
        actor Responses {
            var getAttempts = 0
            var postAttempts = 0

            func load(_ request: URLRequest) throws -> (Data, URLResponse) {
                let method = request.httpMethod ?? "GET"
                if method == "POST" {
                    postAttempts += 1
                    return response(request, status: 503)
                }
                getAttempts += 1
                return response(request, status: getAttempts == 1 ? 503 : 200)
            }

            private func response(
                _ request: URLRequest,
                status: Int
            ) -> (Data, URLResponse) {
                (
                    Data("{}".utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: status,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        }

        let responses = Responses()
        let events = BiliNetworkEventStore(capacity: 2)
        let transport = BiliAPITransport(
            requestLoader: { request in try await responses.load(request) },
            eventStore: events,
            retryPolicy: BiliHTTPRetryPolicy(
                maximumAttempts: 2,
                initialDelayMilliseconds: 0,
                maximumDelayMilliseconds: 0
            ),
            sleeper: { _ in }
        )

        var get = URLRequest(
            url: URL(string: "https://api.bilibili.com/test?keyword=秘密&w_rid=secret")!
        )
        get.httpMethod = "GET"
        let (_, getResponse) = try await transport.data(for: get)
        #expect((getResponse as? HTTPURLResponse)?.statusCode == 200)

        var post = URLRequest(url: URL(string: "https://api.bilibili.com/write?csrf=secret")!)
        post.httpMethod = "POST"
        let (_, postResponse) = try await transport.data(for: post)
        #expect((postResponse as? HTTPURLResponse)?.statusCode == 503)

        #expect(await responses.getAttempts == 2)
        #expect(await responses.postAttempts == 1)
        let snapshot = await events.snapshot()
        #expect(snapshot.map(\.target) == [
            "https://api.bilibili.com/test",
            "https://api.bilibili.com/write",
        ])
    }
}

private enum TestFailure: Error {
    case offline
}
