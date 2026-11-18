@testable import FocusCore
import Foundation
import Testing

struct WBISignerTests {
    @Test
    func signsCleanedChineseParametersInRFC3986KeyOrder() throws {
        let mixinKey = try WBISigner.makeMixinKey(
            imgKey: "7cd084941338484aae1ad9425b84077c",
            subKey: "4932caff0ff746eab6f01bf08b70ac45"
        )
        let query = try WBISigner.makeSignedQuery(
            parameters: [
                "z": "最后",
                "keyword": "原神 测试!'()*",
                "a": "A/B",
                "w_rid": "stale-signature",
                "wts": "0",
            ],
            mixinKey: mixinKey,
            timestamp: 1_700_000_000
        )

        #expect(mixinKey == "ea1db124af3c7062474693fa704f4ff8")
        #expect(
            query
                == "a=A%2FB&keyword=%E5%8E%9F%E7%A5%9E%20%E6%B5%8B%E8%AF%95"
                + "&web_location=1550101&wts=1700000000&z=%E6%9C%80%E5%90%8E"
                + "&w_rid=f48be76f01dde5ed2a5145472b4aeb36"
        )
    }

    @Test
    func concurrentSearchAndVideoRequestsCoalesceNavigationKeyLoad() async throws {
        let recorder = CrossServiceWBIRecorder()
        let signer = WBISigner(
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let cookieProvider = EmptyWBICookieProvider()
        let searchService = SearchResultService(
            cookieProvider: cookieProvider,
            wbiSigner: signer,
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )
        let videoService = FocusVideoDetailService(
            cookieProvider: cookieProvider,
            wbiSigner: signer,
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        async let searchPage = searchService.fetchPage(
            for: SearchQuery(keyword: "并发签名"),
            filter: .video
        )
        async let comments = videoService.fetchComments(aid: 42)
        let (page, loadedComments) = try await (searchPage, comments)
        let requests = await recorder.requests

        #expect(page.sections.isEmpty)
        #expect(loadedComments.isEmpty)
        #expect(requests.filter { $0.url?.path == "/x/web-interface/nav" }.count == 1)
        #expect(requests.filter { $0.url?.path == "/x/web-interface/wbi/search/type" }.count == 1)
        #expect(requests.filter { $0.url?.path == "/x/v2/reply/wbi/main" }.count == 1)
    }

    @Test
    func searchRefreshesRejectedKeyOnceAndRetriesWithNewSignature() async throws {
        let recorder = SearchWBIRetryRecorder()
        let signer = WBISigner(
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let service = SearchResultService(
            cookieProvider: EmptyWBICookieProvider(),
            wbiSigner: signer,
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        let page = try await service.fetchPage(
            for: SearchQuery(keyword: "刷新签名"),
            filter: .video
        )
        let requests = await recorder.requests
        let searchRequests = requests.filter {
            $0.url?.path == "/x/web-interface/wbi/search/type"
        }
        let signatures = searchRequests.compactMap { request in
            URLComponents(
                url: request.url ?? URL(string: "https://api.bilibili.com/")!,
                resolvingAgainstBaseURL: false
            )?.queryItems?.first(where: { $0.name == "w_rid" })?.value
        }

        #expect(page.sections.isEmpty)
        #expect(requests.filter { $0.url?.path == "/x/web-interface/nav" }.count == 2)
        #expect(searchRequests.count == 2)
        #expect(signatures.count == 2)
        #expect(signatures[0] != signatures[1])
    }
}

private struct EmptyWBICookieProvider: CookieSnapshotProvider {
    func loadCookies() async -> [HTTPCookie] {
        []
    }
}

private actor CrossServiceWBIRecorder {
    private(set) var requests: [URLRequest] = []

    func response(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let payload: String
        switch request.url?.path {
        case "/x/web-interface/nav":
            try await Task.sleep(for: .milliseconds(25))
            payload = wbiTestNavigationPayload(img: "a", sub: "b")
        case "/x/web-interface/wbi/search/type":
            payload = #"{"code":0,"data":{"result":[],"page":1,"numPages":1}}"#
        case "/x/v2/reply/wbi/main":
            payload = #"{"code":0,"data":{"replies":[]}}"#
        default:
            payload = #"{"code":-404,"message":"unexpected"}"#
        }
        return (Data(payload.utf8), wbiTestHTTPResponse(for: request))
    }
}

private actor SearchWBIRetryRecorder {
    private(set) var requests: [URLRequest] = []
    private var navigationCount = 0
    private var searchCount = 0

    func response(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let payload: String
        switch request.url?.path {
        case "/x/web-interface/nav":
            navigationCount += 1
            payload = navigationCount == 1
                ? wbiTestNavigationPayload(img: "a", sub: "b")
                : wbiTestNavigationPayload(img: "c", sub: "d")
        case "/x/web-interface/wbi/search/type":
            searchCount += 1
            payload = searchCount == 1
                ? #"{"code":-403,"message":"expired"}"#
                : #"{"code":0,"data":{"result":[],"page":1,"numPages":1}}"#
        default:
            payload = #"{"code":-404,"message":"unexpected"}"#
        }
        return (Data(payload.utf8), wbiTestHTTPResponse(for: request))
    }
}

private func wbiTestNavigationPayload(img: Character, sub: Character) -> String {
    let imgKey = String(repeating: String(img), count: 32)
    let subKey = String(repeating: String(sub), count: 32)
    return """
    {"code":0,"data":{"wbi_img":{
      "img_url":"https://i0.hdslb.com/\(imgKey).png",
      "sub_url":"https://i0.hdslb.com/\(subKey).png"
    }}}
    """
}

private func wbiTestHTTPResponse(for request: URLRequest) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url ?? URL(string: "https://api.bilibili.com/")!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
}
