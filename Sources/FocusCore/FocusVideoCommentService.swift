import Foundation

/// An opaque continuation for one top-level video's comment thread.
///
/// Callers can compare and retain this value, but only the service can create
/// or inspect it. This prevents numeric API pages from leaking into feature
/// state and rejects accidental reuse across different comment threads.
public struct FocusVideoCommentRepliesCursor: Equatable, Hashable, Sendable {
    fileprivate let aid: Int64
    fileprivate let rootCommentID: Int64
    fileprivate let nextPage: Int
    fileprivate let pageSize: Int

    fileprivate init(
        aid: Int64,
        rootCommentID: Int64,
        nextPage: Int,
        pageSize: Int
    ) {
        self.aid = aid
        self.rootCommentID = rootCommentID
        self.nextPage = nextPage
        self.pageSize = pageSize
    }
}

public struct FocusVideoCommentRepliesPage: Equatable, Sendable {
    public let replies: [FocusVideoComment]
    public let totalCount: Int64
    public let nextCursor: FocusVideoCommentRepliesCursor?

    public init(
        replies: [FocusVideoComment],
        totalCount: Int64,
        nextCursor: FocusVideoCommentRepliesCursor?
    ) {
        self.replies = replies
        self.totalCount = max(totalCount, 0)
        self.nextCursor = nextCursor
    }
}

/// Data-layer support for nested video comments and comment reactions.
///
/// Endpoint facts and form fields mirror the sibling `bilibili-api` checkout
/// at commit 87110fe2db7af77425057e163f064700087a3c35.
public actor FocusVideoCommentService {
    public enum ServiceError: Error, Equatable, Sendable, LocalizedError {
        case invalidParameters
        case invalidCursor
        case loginRequired
        case accountScopeChanged
        case httpStatus(code: Int)
        case invalidResponse
        case api(code: Int, message: String)

        public var errorDescription: String? {
            switch self {
            case .invalidParameters:
                return "评论参数无效"
            case .invalidCursor:
                return "评论分页位置与当前楼层不匹配"
            case .loginRequired:
                return "需要先登录才能操作评论"
            case .accountScopeChanged:
                return "登录账号已切换，请刷新评论后重试"
            case let .httpStatus(code):
                return "评论接口请求失败（HTTP \(code)）"
            case .invalidResponse:
                return "评论接口返回了无效数据"
            case let .api(code, message):
                return "评论接口失败（\(code)）：\(message)"
            }
        }
    }

    public typealias RequestLoader = @Sendable (URLRequest) async throws
        -> (Data, URLResponse)

    private static let videoResourceType = 1
    private static let defaultRepliesPageSize = 20
    private static let likeEndpoint = BiliAPIContractCatalog.require(
        "common.comment.like"
    ).url

    private let cookieProvider: any CookieSnapshotProvider
    private let requestLoader: RequestLoader

    public init(
        cookieProvider: any CookieSnapshotProvider,
        requestLoader: @escaping RequestLoader = { request in
            try await BiliAPINetwork.data(for: request)
        }
    ) {
        self.cookieProvider = cookieProvider
        self.requestLoader = requestLoader
    }

    public func fetchReplies(
        aid: Int64,
        rootCommentID: Int64,
        cursor: FocusVideoCommentRepliesCursor? = nil
    ) async throws -> FocusVideoCommentRepliesPage {
        guard aid > 0, rootCommentID > 0 else {
            throw ServiceError.invalidParameters
        }

        let pageNumber: Int
        let pageSize: Int
        if let cursor {
            guard
                cursor.aid == aid,
                cursor.rootCommentID == rootCommentID,
                cursor.nextPage > 0,
                cursor.pageSize > 0
            else {
                throw ServiceError.invalidCursor
            }
            pageNumber = cursor.nextPage
            pageSize = cursor.pageSize
        } else {
            pageNumber = 1
            pageSize = Self.defaultRepliesPageSize
        }

        let endpoint = BiliAPIContractCatalog.require(
            "common.comment.sub_reply"
        ).url
        var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "pn", value: String(pageNumber)),
            URLQueryItem(name: "ps", value: String(pageSize)),
            URLQueryItem(name: "type", value: String(Self.videoResourceType)),
            URLQueryItem(name: "oid", value: String(aid)),
            URLQueryItem(name: "root", value: String(rootCommentID)),
        ]
        guard let url = components.url else {
            throw ServiceError.invalidParameters
        }

        let cookies = await cookieProvider.loadCookies()
        let request = Self.makeRequest(
            url: url,
            method: "GET",
            referer: Self.videoReferer(aid: aid),
            cookies: cookies
        )
        let data = try await loadData(for: request)
        return try Self.decodeRepliesPageResponse(
            data,
            aid: aid,
            rootCommentID: rootCommentID,
            requestedPage: pageNumber,
            requestedPageSize: pageSize
        )
    }

    /// Likes or unlikes a video comment using one account-bound Cookie snapshot.
    ///
    /// `expectedAccountScope` must be the scope that owns the currently
    /// displayed comment state. A changed or signed-out account is rejected
    /// before any request is sent.
    public func setCommentLiked(
        aid: Int64,
        commentID: Int64,
        liked: Bool,
        expectedAccountScope: FocusPlaybackAccountScope
    ) async throws {
        guard aid > 0, commentID > 0 else {
            throw ServiceError.invalidParameters
        }
        guard expectedAccountScope != .anonymous else {
            throw ServiceError.loginRequired
        }

        let cookies = await cookieProvider.loadCookies()
        let currentScope = FocusPlaybackAccountScope.resolve(cookies: cookies)
        guard currentScope == expectedAccountScope else {
            throw ServiceError.accountScopeChanged
        }

        let requestCookies = CookieRequestPolicy.cookies(
            cookies,
            matching: Self.likeEndpoint
        )
        let sessionValues = Self.cookieValues(
            named: "SESSDATA",
            in: requestCookies
        )
        let csrfValues = Self.cookieValues(
            named: "bili_jct",
            in: requestCookies
        )
        guard
            sessionValues.count == 1,
            csrfValues.count == 1,
            let csrf = csrfValues.first
        else {
            throw ServiceError.loginRequired
        }

        var request = Self.makeRequest(
            url: Self.likeEndpoint,
            method: "POST",
            referer: Self.videoReferer(aid: aid),
            cookies: requestCookies
        )
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "https://www.bilibili.com",
            forHTTPHeaderField: "Origin"
        )
        request.httpBody = Self.formBody(
            values: [
                "oid": String(aid),
                "type": String(Self.videoResourceType),
                "rpid": String(commentID),
                "action": liked ? "1" : "0",
                "csrf": csrf,
                "csrf_token": csrf,
            ]
        )

        let data = try await loadData(for: request)
        try Self.validateMutationResponse(data)
    }

    public nonisolated static func decodeRepliesPageResponse(
        _ data: Data,
        aid: Int64,
        rootCommentID: Int64,
        requestedPage: Int = 1,
        requestedPageSize: Int = 20
    ) throws -> FocusVideoCommentRepliesPage {
        guard
            aid > 0,
            rootCommentID > 0,
            requestedPage > 0,
            requestedPageSize > 0
        else {
            throw ServiceError.invalidParameters
        }

        let decoded: FocusVideoCommentsPage
        do {
            decoded = try FocusVideoDetailService.decodeCommentsPageResponse(data)
        } catch let error as FocusVideoDetailService.ServiceError {
            throw mapDetailError(error)
        } catch {
            throw ServiceError.invalidResponse
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            throw ServiceError.invalidResponse
        }
        let rawReplies = nestedValue(root, path: ["data", "replies"]) as? [Any]
            ?? []
        let declaredTotal = int64Value(
            nestedValue(root, path: ["data", "page", "count"])
        ).map { max($0, 0) }
        let responsePageSize = intValue(
            nestedValue(root, path: ["data", "page", "size"])
        ).flatMap { $0 > 0 ? $0 : nil }
        let effectivePageSize = responsePageSize ?? requestedPageSize
        let totalCount = declaredTotal ?? decoded.totalCount

        let consumed = Int64(requestedPage)
            .multipliedReportingOverflow(by: Int64(effectivePageSize))
        let hasMore: Bool
        if rawReplies.isEmpty || consumed.overflow {
            hasMore = false
        } else if let declaredTotal {
            hasMore = consumed.partialValue < declaredTotal
        } else {
            hasMore = rawReplies.count >= effectivePageSize
        }

        let nextPage = requestedPage.addingReportingOverflow(1)
        let nextCursor = hasMore && !nextPage.overflow
            ? FocusVideoCommentRepliesCursor(
                aid: aid,
                rootCommentID: rootCommentID,
                nextPage: nextPage.partialValue,
                pageSize: requestedPageSize
            )
            : nil
        return FocusVideoCommentRepliesPage(
            replies: decoded.comments,
            totalCount: totalCount,
            nextCursor: nextCursor
        )
    }

    private func loadData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await requestLoader(request)
        guard let response = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw ServiceError.httpStatus(code: response.statusCode)
        }
        return data
    }

    private nonisolated static func makeRequest(
        url: URL,
        method: String,
        referer: String,
        cookies: [HTTPCookie]
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(
            FocusVideoDetailService.userAgent,
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(
            "application/json, text/plain, */*",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "zh-CN,zh-Hans;q=0.9",
            forHTTPHeaderField: "Accept-Language"
        )
        return CookieRequestPolicy.attach(cookies: cookies, to: request)
    }

    private nonisolated static func formBody(
        values: [String: String]
    ) -> Data? {
        var components = URLComponents()
        components.queryItems = values.keys.sorted().map { key in
            URLQueryItem(name: key, value: values[key])
        }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private nonisolated static func validateMutationResponse(
        _ data: Data
    ) throws {
        guard
            let root = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            throw ServiceError.invalidResponse
        }
        let code = intValue(root["code"]) ?? -1
        if code == -101 {
            throw ServiceError.loginRequired
        }
        guard code == 0 else {
            throw ServiceError.api(
                code: code,
                message: stringValue(root["message"]) ?? "未知错误"
            )
        }
    }

    private nonisolated static func mapDetailError(
        _ error: FocusVideoDetailService.ServiceError
    ) -> ServiceError {
        switch error {
        case let .api(code, message):
            return code == -101
                ? .loginRequired
                : .api(code: code, message: message)
        case .unsupportedURL, .invalidResponse, .noStream:
            return .invalidResponse
        }
    }

    private nonisolated static func cookieValues(
        named name: String,
        in cookies: [HTTPCookie]
    ) -> [String] {
        cookies.compactMap { cookie in
            guard cookie.name.caseInsensitiveCompare(name) == .orderedSame else {
                return nil
            }
            let value = cookie.value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return value.isEmpty ? nil : value
        }
    }

    private nonisolated static func videoReferer(aid: Int64) -> String {
        "https://www.bilibili.com/video/av\(aid)/"
    }

    private nonisolated static func nestedValue(
        _ root: [String: Any],
        path: [String]
    ) -> Any? {
        var value: Any = root
        for key in path {
            guard let dictionary = value as? [String: Any],
                  let next = dictionary[key]
            else {
                return nil
            }
            value = next
        }
        return value
    }

    private nonisolated static func intValue(_ value: Any?) -> Int? {
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

    private nonisolated static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? NSNumber {
            return value.int64Value
        }
        if let value = value as? String {
            return Int64(value)
        }
        return nil
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }
}
