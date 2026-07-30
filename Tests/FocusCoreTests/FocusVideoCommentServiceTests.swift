@testable import FocusCore
import Foundation
import Testing

struct FocusVideoCommentServiceTests {
    @Test
    func replyFixturesDecodeLikedStateAndOpaqueContinuation() throws {
        let firstPage = try FocusVideoCommentService.decodeRepliesPageResponse(
            commentFixture(named: "comment-sub-replies-page-1"),
            aid: 42,
            rootCommentID: 80001,
            requestedPage: 1,
            requestedPageSize: 20
        )
        let secondPage = try FocusVideoCommentService.decodeRepliesPageResponse(
            commentFixture(named: "comment-sub-replies-page-2"),
            aid: 42,
            rootCommentID: 80001,
            requestedPage: 2,
            requestedPageSize: 20
        )

        #expect(firstPage.replies.map(\.id) == [90001, 90002])
        #expect(firstPage.replies.first?.isLiked == true)
        #expect(firstPage.replies.first?.likes == 12)
        #expect(firstPage.totalCount == 3)
        #expect(firstPage.nextCursor != nil)
        #expect(secondPage.replies.map(\.id) == [90003])
        #expect(secondPage.totalCount == 3)
        #expect(secondPage.nextCursor == nil)
    }

    @Test
    func replyDecoderStopsAtIntegerPageBoundary() throws {
        var root = try #require(
            JSONSerialization.jsonObject(
                with: commentFixture(named: "comment-sub-replies-page-1")
            ) as? [String: Any]
        )
        var payload = try #require(root["data"] as? [String: Any])
        payload.removeValue(forKey: "page")
        root["data"] = payload
        let data = try JSONSerialization.data(withJSONObject: root)

        let page = try FocusVideoCommentService.decodeRepliesPageResponse(
            data,
            aid: 42,
            rootCommentID: 80001,
            requestedPage: .max,
            requestedPageSize: 1
        )

        #expect(page.nextCursor == nil)
    }

    @Test
    func replyPagingUsesThreadBoundCursorAndExpectedBilibiliParameters() async throws {
        let recorder = CommentServiceRequestRecorder(
            firstPage: try commentFixture(named: "comment-sub-replies-page-1"),
            secondPage: try commentFixture(named: "comment-sub-replies-page-2")
        )
        let service = FocusVideoCommentService(
            cookieProvider: StaticCommentCookieProvider(cookies: []),
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        let firstPage = try await service.fetchReplies(
            aid: 42,
            rootCommentID: 80001
        )
        let cursor = try #require(firstPage.nextCursor)
        let secondPage = try await service.fetchReplies(
            aid: 42,
            rootCommentID: 80001,
            cursor: cursor
        )

        #expect(secondPage.nextCursor == nil)
        await #expect(throws: FocusVideoCommentService.ServiceError.invalidCursor) {
            try await service.fetchReplies(
                aid: 42,
                rootCommentID: 80002,
                cursor: cursor
            )
        }

        let requests = await recorder.requests
        #expect(requests.count == 2)
        let firstQuery = queryValues(in: try #require(requests.first?.url))
        let secondQuery = queryValues(in: try #require(requests.last?.url))
        #expect(firstQuery["pn"] == "1")
        #expect(secondQuery["pn"] == "2")
        #expect(firstQuery["ps"] == "20")
        #expect(firstQuery["type"] == "1")
        #expect(firstQuery["oid"] == "42")
        #expect(firstQuery["root"] == "80001")
        #expect(
            requests.allSatisfy {
                $0.url?.path == "/x/v2/reply/reply"
                    && $0.httpMethod == "GET"
            }
        )
    }

    @Test
    func commentLikeAndUnlikeUseCSRFAndExactAccountSnapshot() async throws {
        let cookies = commentAccountCookies(mid: "1001", session: "session-a")
        let expectedScope = FocusPlaybackAccountScope.resolve(cookies: cookies)
        let recorder = CommentServiceRequestRecorder(
            firstPage: Data(),
            secondPage: Data()
        )
        let service = FocusVideoCommentService(
            cookieProvider: StaticCommentCookieProvider(cookies: cookies),
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        try await service.setCommentLiked(
            aid: 42,
            commentID: 90001,
            liked: true,
            expectedAccountScope: expectedScope
        )
        try await service.setCommentLiked(
            aid: 42,
            commentID: 90001,
            liked: false,
            expectedAccountScope: expectedScope
        )

        let requests = await recorder.requests
        #expect(requests.count == 2)
        let likeValues = formValues(in: try #require(requests.first))
        let unlikeValues = formValues(in: try #require(requests.last))
        #expect(likeValues["oid"] == "42")
        #expect(likeValues["type"] == "1")
        #expect(likeValues["rpid"] == "90001")
        #expect(likeValues["action"] == "1")
        #expect(unlikeValues["action"] == "0")
        #expect(likeValues["csrf"] == "csrf-1001")
        #expect(likeValues["csrf_token"] == "csrf-1001")
        #expect(
            requests.allSatisfy {
                $0.url?.path == "/x/v2/reply/action"
                    && $0.httpMethod == "POST"
                    && $0.value(forHTTPHeaderField: "Origin")
                        == "https://www.bilibili.com"
                    && $0.value(forHTTPHeaderField: "Cookie")?
                        .contains("SESSDATA=session-a") == true
            }
        )
    }

    @Test
    func commentMutationRejectsMissingCSRFAndAccountSwitchBeforeNetwork() async {
        let accountA = commentAccountCookies(mid: "1001", session: "session-a")
        let accountB = commentAccountCookies(mid: "2002", session: "session-b")
        let expectedScope = FocusPlaybackAccountScope.resolve(cookies: accountA)
        let recorder = CommentServiceRequestRecorder(
            firstPage: Data(),
            secondPage: Data()
        )
        let missingCSRFService = FocusVideoCommentService(
            cookieProvider: StaticCommentCookieProvider(
                cookies: accountA.filter {
                    $0.name.caseInsensitiveCompare("bili_jct") != .orderedSame
                }
            ),
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )
        let switchedAccountService = FocusVideoCommentService(
            cookieProvider: StaticCommentCookieProvider(cookies: accountB),
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )
        let duplicateCSRFService = FocusVideoCommentService(
            cookieProvider: StaticCommentCookieProvider(
                cookies: accountA + [
                    commentCookie(
                        name: "bili_jct",
                        value: "csrf-1001"
                    ),
                ].compactMap { $0 }
            ),
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        await #expect(throws: FocusVideoCommentService.ServiceError.loginRequired) {
            try await missingCSRFService.setCommentLiked(
                aid: 42,
                commentID: 90001,
                liked: true,
                expectedAccountScope: expectedScope
            )
        }
        await #expect(
            throws: FocusVideoCommentService.ServiceError.accountScopeChanged
        ) {
            try await switchedAccountService.setCommentLiked(
                aid: 42,
                commentID: 90001,
                liked: true,
                expectedAccountScope: expectedScope
            )
        }
        await #expect(throws: FocusVideoCommentService.ServiceError.loginRequired) {
            try await duplicateCSRFService.setCommentLiked(
                aid: 42,
                commentID: 90001,
                liked: true,
                expectedAccountScope: expectedScope
            )
        }
        #expect(await recorder.requests.isEmpty)
    }
}

private actor CommentServiceRequestRecorder {
    private let firstPage: Data
    private let secondPage: Data
    private(set) var requests: [URLRequest] = []

    init(firstPage: Data, secondPage: Data) {
        self.firstPage = firstPage
        self.secondPage = secondPage
    }

    func response(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let data: Data
        switch request.url?.path {
        case "/x/v2/reply/reply":
            let page = queryValues(in: request.url!)["pn"]
            data = page == "2" ? secondPage : firstPage
        case "/x/v2/reply/action":
            data = Data(#"{"code":0,"message":"0","data":{}}"#.utf8)
        default:
            data = Data(#"{"code":-404,"message":"unexpected"}"#.utf8)
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.bilibili.com/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}

private struct StaticCommentCookieProvider: CookieSnapshotProvider {
    let cookies: [HTTPCookie]

    func loadCookies() async -> [HTTPCookie] {
        cookies
    }
}

private func commentFixture(named name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json")
    )
    return try Data(contentsOf: url)
}

private func queryValues(in url: URL) -> [String: String] {
    Dictionary(
        uniqueKeysWithValues: (
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems ?? []
        ).compactMap { item in
            item.value.map { (item.name, $0) }
        }
    )
}

private func formValues(in request: URLRequest) -> [String: String] {
    guard
        let body = request.httpBody,
        let encoded = String(data: body, encoding: .utf8),
        let url = URL(string: "https://example.com/?\(encoded)")
    else {
        return [:]
    }
    return queryValues(in: url)
}

private func commentAccountCookies(
    mid: String,
    session: String
) -> [HTTPCookie] {
    [
        commentCookie(name: "DedeUserID", value: mid),
        commentCookie(name: "SESSDATA", value: session),
        commentCookie(name: "bili_jct", value: "csrf-\(mid)"),
    ].compactMap { $0 }
}

private func commentCookie(name: String, value: String) -> HTTPCookie? {
    HTTPCookie(properties: [
        .domain: ".bilibili.com",
        .path: "/",
        .name: name,
        .value: value,
        .secure: "TRUE",
    ])
}
