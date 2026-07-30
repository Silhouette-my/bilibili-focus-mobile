import Foundation

public struct FocusWatchLaterAuthor: Codable, Equatable, Sendable {
    public let mid: Int64
    public let name: String
    public let avatarURL: URL?

    public init(mid: Int64, name: String, avatarURL: URL?) {
        self.mid = mid
        self.name = name
        self.avatarURL = avatarURL
    }
}

public struct FocusWatchLaterItem: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64 { aid }

    public let aid: Int64
    public let bvid: String
    public let cid: Int64
    public let title: String
    public let coverURL: URL?
    public let author: FocusWatchLaterAuthor
    public let durationSeconds: Int64
    public let progressSeconds: Int64
    public let addedAt: Int64
    public let publishedAt: Int64
    public let viewCount: Int64

    public init(
        aid: Int64,
        bvid: String,
        cid: Int64,
        title: String,
        coverURL: URL?,
        author: FocusWatchLaterAuthor,
        durationSeconds: Int64,
        progressSeconds: Int64,
        addedAt: Int64,
        publishedAt: Int64,
        viewCount: Int64
    ) {
        self.aid = aid
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.coverURL = coverURL
        self.author = author
        self.durationSeconds = durationSeconds
        self.progressSeconds = progressSeconds
        self.addedAt = addedAt
        self.publishedAt = publishedAt
        self.viewCount = viewCount
    }

    public var targetURL: URL? {
        if !bvid.isEmpty {
            return URL(string: "https://www.bilibili.com/video/\(bvid)/")
        }
        guard aid > 0 else {
            return nil
        }
        return URL(string: "https://www.bilibili.com/video/av\(aid)/")
    }
}

public struct FocusWatchLaterList: Codable, Equatable, Sendable {
    public let totalCount: Int
    public let items: [FocusWatchLaterItem]

    public init(totalCount: Int, items: [FocusWatchLaterItem]) {
        self.totalCount = totalCount
        self.items = items
    }
}

public actor FocusWatchLaterService {
    public enum ServiceError: Error, Equatable, Sendable, LocalizedError {
        case invalidResponse
        case loginRequired
        case missingCSRF
        case invalidAID
        case api(code: Int, message: String)

        public var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "稍后再看接口返回无效数据"
            case .loginRequired:
                return "需要先登录才能访问稍后再看"
            case .missingCSRF:
                return "登录凭据缺少 bili_jct"
            case .invalidAID:
                return "视频 aid 无效"
            case let .api(code, message):
                return "稍后再看接口失败（\(code)）：\(message)"
            }
        }
    }

    public typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private struct AuthenticationSnapshot {
        let cookies: [HTTPCookie]
        let csrf: String?
    }

    private let cookieProvider: any CookieSnapshotProvider
    private let requestLoader: RequestLoader
    private let userAgent: String

    public init(
        cookieProvider: any CookieSnapshotProvider,
        userAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
        requestLoader: @escaping RequestLoader = { request in
            try await BiliAPINetwork.data(for: request)
        }
    ) {
        self.cookieProvider = cookieProvider
        self.requestLoader = requestLoader
        self.userAgent = userAgent
    }

    public func fetchList() async throws -> FocusWatchLaterList {
        try Task.checkCancellation()
        let url = BiliAPIContractCatalog.require("toview.info.list").url
        let authentication = try await authenticationSnapshot(for: url, needsCSRF: false)
        let (data, response) = try await requestLoader(
            makeRequest(url: url, method: "GET", cookies: authentication.cookies)
        )
        try Task.checkCancellation()
        try Self.validateHTTPResponse(response)
        return try Self.decodeListResponse(data)
    }

    public func add(aid: Int64) async throws {
        guard aid > 0 else {
            throw ServiceError.invalidAID
        }
        try await postMutation(
            endpointKey: "toview.operate.add",
            values: [URLQueryItem(name: "aid", value: String(aid))]
        )
    }

    public func remove(aid: Int64) async throws {
        guard aid > 0 else {
            throw ServiceError.invalidAID
        }
        try await postMutation(
            endpointKey: "toview.operate.del",
            values: [
                URLQueryItem(name: "aid", value: String(aid)),
                URLQueryItem(name: "viewed", value: "false"),
            ]
        )
    }

    public func deleteViewed() async throws {
        try await postMutation(
            endpointKey: "toview.operate.del",
            values: [URLQueryItem(name: "viewed", value: "true")]
        )
    }

    public func clear() async throws {
        try await postMutation(endpointKey: "toview.operate.clear", values: [])
    }

    public nonisolated static func decodeListResponse(_ data: Data) throws -> FocusWatchLaterList {
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ServiceError.invalidResponse
        }
        try validatePayload(payload)
        guard let dataPayload = payload["data"] as? [String: Any] else {
            throw ServiceError.invalidResponse
        }

        let rawItems = dataPayload["list"] as? [Any] ?? []
        let items = rawItems.compactMap { rawItem -> FocusWatchLaterItem? in
            guard
                let item = rawItem as? [String: Any],
                let aid = int64Value(item["aid"]),
                aid > 0
            else {
                return nil
            }
            let owner = item["owner"] as? [String: Any] ?? [:]
            return FocusWatchLaterItem(
                aid: aid,
                bvid: stringValue(item["bvid"]) ?? "",
                cid: int64Value(item["cid"]) ?? 0,
                title: stringValue(item["title"]) ?? "",
                coverURL: normalizedURL(stringValue(item["pic"])),
                author: FocusWatchLaterAuthor(
                    mid: int64Value(owner["mid"]) ?? 0,
                    name: stringValue(owner["name"]) ?? "",
                    avatarURL: normalizedURL(stringValue(owner["face"]))
                ),
                durationSeconds: int64Value(item["duration"]) ?? 0,
                progressSeconds: int64Value(item["progress"]) ?? 0,
                addedAt: int64Value(item["add_at"]) ?? 0,
                publishedAt: int64Value(item["pubdate"]) ?? 0,
                viewCount: int64Value((item["stat"] as? [String: Any])?["view"]) ?? 0
            )
        }
        let rawCount = int64Value(dataPayload["count"]) ?? Int64(items.count)
        let count = Int(max(0, min(rawCount, Int64(Int.max))))
        return FocusWatchLaterList(totalCount: count, items: items)
    }

    private func postMutation(
        endpointKey: String,
        values: [URLQueryItem]
    ) async throws {
        try Task.checkCancellation()
        let url = BiliAPIContractCatalog.require(endpointKey).url
        let authentication = try await authenticationSnapshot(for: url, needsCSRF: true)
        guard let csrf = authentication.csrf else {
            throw ServiceError.missingCSRF
        }

        var request = makeRequest(url: url, method: "POST", cookies: authentication.cookies)
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        var formComponents = URLComponents()
        formComponents.queryItems = values + [
            URLQueryItem(name: "csrf", value: csrf),
            URLQueryItem(name: "csrf_token", value: csrf),
        ]
        request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await requestLoader(request)
        try Task.checkCancellation()
        try Self.validateHTTPResponse(response)
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ServiceError.invalidResponse
        }
        try Self.validatePayload(payload)
    }

    private func authenticationSnapshot(
        for targetURL: URL,
        needsCSRF: Bool
    ) async throws -> AuthenticationSnapshot {
        let cookies = await cookieProvider.loadCookies()
        try Task.checkCancellation()
        let matchingCookies = CookieRequestPolicy.cookies(cookies, matching: targetURL)
        guard matchingCookies.contains(where: {
            $0.name == "SESSDATA" && !$0.value.isEmpty
        }) else {
            throw ServiceError.loginRequired
        }
        let csrf = matchingCookies.first(where: {
            $0.name == "bili_jct" && !$0.value.isEmpty
        })?.value
        if needsCSRF && csrf == nil {
            throw ServiceError.missingCSRF
        }
        return AuthenticationSnapshot(cookies: cookies, csrf: csrf)
    }

    private func makeRequest(
        url: URL,
        method: String,
        cookies: [HTTPCookie]
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        return CookieRequestPolicy.attach(cookies: cookies, to: request)
    }

    private nonisolated static func validateHTTPResponse(_ response: URLResponse) throws {
        guard
            let response = response as? HTTPURLResponse,
            (200 ..< 300).contains(response.statusCode)
        else {
            throw ServiceError.invalidResponse
        }
    }

    private nonisolated static func validatePayload(_ payload: [String: Any]) throws {
        guard let code = int64Value(payload["code"]) else {
            throw ServiceError.invalidResponse
        }
        if code == -101 {
            throw ServiceError.loginRequired
        }
        guard code == 0 else {
            throw ServiceError.api(
                code: Int(clamping: code),
                message: stringValue(payload["message"]) ?? "未知错误"
            )
        }
    }

    private nonisolated static func int64Value(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let string = value as? String {
            return Int64(string)
        }
        return nil
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private nonisolated static func normalizedURL(_ rawValue: String?) -> URL? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return URL(string: value.hasPrefix("//") ? "https:\(value)" : value)
    }
}
