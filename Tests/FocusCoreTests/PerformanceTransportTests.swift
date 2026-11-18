import Foundation
import Testing
@testable import FocusCore

struct PerformanceTransportTests {
    @Test func diagnosticsCountActualAttemptsAcrossRetries() async throws {
        let counter = TransportAttemptCounter()
        let events = BiliNetworkEventStore()
        let transport = BiliAPITransport(requestLoader: { request in
            await counter.increment()
            let status = await counter.count < 3 ? 503 : 200
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }, eventStore: events, sleeper: { _ in })
        _ = try await transport.data(for: URLRequest(url: URL(string: "https://example.org/fixture")!))
        let event = try #require(await events.snapshot().first)
        #expect(event.attemptCount == 3)
        #expect(event.statusCode == 200)
    }

    @Test func authenticatedOrCrossOriginRedirectCannotMoveCredentials() {
        let source = URL(string: "https://api.bilibili.com/x/web-interface/nav")!
        let sameOrigin = URL(string: "https://api.bilibili.com/other")!
        var request = URLRequest(url: source)
        #expect(BiliNativeRedirectPolicy.permitsRedirect(original: request, destination: sameOrigin))
        #expect(!BiliNativeRedirectPolicy.permitsRedirect(original: request, destination: URL(string: "https://example.org/")!))
        #expect(!BiliNativeRedirectPolicy.permitsRedirect(original: request, destination: URL(string: "http://api.bilibili.com/")!))
        request.setValue("SESSDATA=synthetic-fixture", forHTTPHeaderField: "Cookie")
        #expect(!BiliNativeRedirectPolicy.permitsRedirect(original: request, destination: sameOrigin))
    }

    @Test func offlineAndCancellationDoNotSpendRetryBudget() async {
        for code in [URLError.Code.notConnectedToInternet, .cancelled] {
            let counter = TransportAttemptCounter()
            let transport = BiliAPITransport(requestLoader: { _ in
                await counter.increment()
                throw URLError(code)
            }, sleeper: { _ in })
            do {
                _ = try await transport.data(for: URLRequest(url: URL(string: "https://example.org/fixture")!))
                Issue.record("Expected fixture failure")
            } catch {
                if code == .cancelled { #expect(error is CancellationError) }
            }
            #expect(await counter.count == 1)
        }
    }
}

private actor TransportAttemptCounter {
    var count = 0
    func increment() { count += 1 }
}
