import FocusCore
import Foundation
import Testing

struct FocusWatchLaterServiceTests {
    @Test
    func decodesLongIdentifiersAndListMetadata() throws {
        let result = try FocusWatchLaterService.decodeListResponse(Data(Self.listPayload.utf8))

        #expect(result.totalCount == 1)
        let item = try #require(result.items.first)
        #expect(item.aid == 4_294_967_296)
        #expect(item.cid == 8_589_934_592)
        #expect(item.bvid == "BV1xx411c7mD")
        #expect(item.coverURL?.absoluteString == "https://i0.hdslb.com/cover.jpg")
        #expect(item.author.mid == 4_294_967_297)
        #expect(item.viewCount == 9_223_372_036)
        #expect(item.targetURL?.absoluteString == "https://www.bilibili.com/video/BV1xx411c7mD/")
    }

    @Test
    func listAndMutationsUseCatalogEndpointsScopedCookiesAndCSRF() async throws {
        let recorder = WatchLaterRequestRecorder(listPayload: Self.listPayload)
        let service = FocusWatchLaterService(
            cookieProvider: WatchLaterCookieProvider(includeCSRF: true),
            requestLoader: { request in
                await recorder.response(for: request)
            }
        )
        let aid: Int64 = 4_294_967_296

        _ = try await service.fetchList()
        try await service.add(aid: aid)
        try await service.remove(aid: aid)
        try await service.deleteViewed()
        try await service.clear()

        let requests = await recorder.snapshot()
        #expect(requests.map(\.url?.path) == [
            "/x/v2/history/toview",
            "/x/v2/history/toview/add",
            "/x/v2/history/toview/del",
            "/x/v2/history/toview/del",
            "/x/v2/history/toview/clear",
        ])
        let listRequest = try #require(requests.first)
        #expect(listRequest.httpMethod == "GET")
        #expect(listRequest.value(forHTTPHeaderField: "Cookie")?.contains("SESSDATA=session-token") == true)
        #expect(listRequest.value(forHTTPHeaderField: "Cookie")?.contains("bili_jct=csrf-token") == true)
        #expect(listRequest.value(forHTTPHeaderField: "Cookie")?.contains("wrong-domain") == false)
        #expect(listRequest.value(forHTTPHeaderField: "Cookie")?.contains("wrong-path") == false)

        let mutationRequests = Array(requests.dropFirst())
        let bodies = mutationRequests.map {
            String(data: $0.httpBody ?? Data(), encoding: .utf8) ?? ""
        }
        #expect(bodies[0].contains("aid=4294967296"))
        #expect(bodies[1].contains("viewed=false"))
        #expect(bodies[2].contains("viewed=true"))
        for (request, body) in zip(mutationRequests, bodies) {
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Origin") == "https://www.bilibili.com")
            #expect(body.contains("csrf=csrf-token"))
            #expect(body.contains("csrf_token=csrf-token"))
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("wrong-domain") == false)
        }
    }

    @Test
    func mutationFailsBeforeNetworkWithoutMatchingCSRF() async {
        let service = FocusWatchLaterService(
            cookieProvider: WatchLaterCookieProvider(includeCSRF: false),
            requestLoader: { _ in
                Issue.record("request loader should not run without CSRF")
                return (
                    Data(),
                    URLResponse(
                        url: URL(string: "https://api.bilibili.com")!,
                        mimeType: nil,
                        expectedContentLength: 0,
                        textEncodingName: nil
                    )
                )
            }
        )

        await #expect(throws: FocusWatchLaterService.ServiceError.missingCSRF) {
            try await service.add(aid: 42)
        }
    }

    @Test
    func cancellationPropagatesWithoutConversion() async {
        let service = FocusWatchLaterService(
            cookieProvider: WatchLaterCookieProvider(includeCSRF: true),
            requestLoader: { _ in
                throw CancellationError()
            }
        )

        do {
            _ = try await service.fetchList()
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected: cancellation is not converted to a service error.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    private static let listPayload = """
    {
      "code": 0,
      "message": "0",
      "data": {
        "count": 1,
        "list": [{
          "aid": 4294967296,
          "bvid": "BV1xx411c7mD",
          "cid": 8589934592,
          "title": "稍后再看的视频",
          "pic": "//i0.hdslb.com/cover.jpg",
          "duration": 600,
          "progress": 87,
          "add_at": 1700000000,
          "pubdate": 1690000000,
          "owner": {
            "mid": 4294967297,
            "name": "UP 主",
            "face": "//i0.hdslb.com/avatar.jpg"
          },
          "stat": {
            "view": 9223372036
          }
        }]
      }
    }
    """
}

private struct WatchLaterCookieProvider: CookieSnapshotProvider {
    let includeCSRF: Bool

    func loadCookies() async -> [HTTPCookie] {
        var cookies = [
            watchLaterCookie(
                name: "bili_jct",
                value: "wrong-domain",
                domain: ".example.com"
            ),
            watchLaterCookie(
                name: "path-only",
                value: "wrong-path",
                domain: ".bilibili.com",
                path: "/account"
            ),
            watchLaterCookie(
                name: "SESSDATA",
                value: "session-token",
                domain: ".bilibili.com"
            ),
        ].compactMap { $0 }
        if includeCSRF, let csrf = watchLaterCookie(
            name: "bili_jct",
            value: "csrf-token",
            domain: ".bilibili.com"
        ) {
            cookies.append(csrf)
        }
        return cookies
    }
}

private actor WatchLaterRequestRecorder {
    private let listPayload: String
    private var requests: [URLRequest] = []

    init(listPayload: String) {
        self.listPayload = listPayload
    }

    func response(for request: URLRequest) -> (Data, URLResponse) {
        requests.append(request)
        let payload = request.url?.path == "/x/v2/history/toview"
            ? listPayload
            : #"{"code":0,"data":{}}"#
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.bilibili.com")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(payload.utf8), response)
    }

    func snapshot() -> [URLRequest] {
        requests
    }
}

private func watchLaterCookie(
    name: String,
    value: String,
    domain: String,
    path: String = "/"
) -> HTTPCookie? {
    HTTPCookie(properties: [
        .domain: domain,
        .path: path,
        .name: name,
        .value: value,
        .secure: "TRUE",
    ])
}
