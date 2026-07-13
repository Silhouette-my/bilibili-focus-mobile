import Foundation

public struct FocusVideoInteractionState: Equatable, Sendable {
    public let liked: Bool
    public let coined: Bool
    public let favorited: Bool
    public let favoriteFolderID: Int64?

    public init(
        liked: Bool = false,
        coined: Bool = false,
        favorited: Bool = false,
        favoriteFolderID: Int64? = nil
    ) {
        self.liked = liked
        self.coined = coined
        self.favorited = favorited
        self.favoriteFolderID = favoriteFolderID
    }
}

public actor FocusVideoActionService {
    private enum InteractionFlagKind: Sendable {
        case liked
        case coined
        case favorited
    }

    public enum ServiceError: Error, Equatable, Sendable, LocalizedError {
        case loginRequired
        case noFavoriteFolder
        case invalidResponse
        case api(code: Int, message: String)

        public var errorDescription: String? {
            switch self {
            case .loginRequired:
                return "需要先登录才能执行此操作"
            case .noFavoriteFolder:
                return "当前账号没有可用的收藏夹"
            case .invalidResponse:
                return "操作接口返回了无效数据"
            case let .api(code, message):
                return "操作失败（\(code)）：\(message)"
            }
        }
    }

    public typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let cookieProvider: any CookieSnapshotProvider
    private let requestLoader: RequestLoader

    public init(
        cookieProvider: any CookieSnapshotProvider,
        requestLoader: @escaping RequestLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.cookieProvider = cookieProvider
        self.requestLoader = requestLoader
    }

    public func fetchInteractionState(aid: Int64) async throws -> FocusVideoInteractionState {
        let cookies = await authenticatedCookies()
        let referer = "https://www.bilibili.com/video/av\(aid)/"

        async let likedResult = interactionFlag(
            url: URL(string: "https://api.bilibili.com/x/web-interface/archive/has/like?aid=\(aid)")!,
            referer: referer,
            cookies: cookies,
            kind: .liked
        )
        async let coinedResult = interactionFlag(
            url: URL(string: "https://api.bilibili.com/x/web-interface/archive/coins?aid=\(aid)")!,
            referer: referer,
            cookies: cookies,
            kind: .coined
        )
        async let favoriteResult = interactionFlag(
            url: URL(string: "https://api.bilibili.com/x/v2/fav/video/favoured?aid=\(aid)")!,
            referer: referer,
            cookies: cookies,
            kind: .favorited
        )
        async let folderResult = favoriteFolderID(aid: aid, cookies: cookies)

        let likedValue = await likedResult
        let coinedValue = await coinedResult
        let favoriteValue = await favoriteResult
        let folderID = try? await folderResult

        return FocusVideoInteractionState(
            liked: likedValue,
            coined: coinedValue,
            favorited: favoriteValue,
            favoriteFolderID: folderID
        )
    }

    public func setLiked(aid: Int64, liked: Bool) async throws {
        let cookies = await authenticatedCookies()
        let csrf = try Self.csrfToken(in: cookies)
        try await postForm(
            url: URL(string: "https://api.bilibili.com/x/web-interface/archive/like")!,
            values: [
                "aid": String(aid),
                "like": liked ? "1" : "2",
                "csrf": csrf,
                "csrf_token": csrf,
            ],
            referer: "https://www.bilibili.com/video/av\(aid)/",
            cookies: cookies
        )
    }

    public func addCoin(aid: Int64, alsoLike: Bool = false) async throws {
        let cookies = await authenticatedCookies()
        let csrf = try Self.csrfToken(in: cookies)
        try await postForm(
            url: URL(string: "https://api.bilibili.com/x/web-interface/coin/add")!,
            values: [
                "aid": String(aid),
                "multiply": "1",
                "select_like": alsoLike ? "1" : "0",
                "csrf": csrf,
                "csrf_token": csrf,
            ],
            referer: "https://www.bilibili.com/video/av\(aid)/",
            cookies: cookies
        )
    }

    /// Mirrors `bilibili-api`'s `Video.report_watch_history` request.
    /// Calling this periodically keeps the server-side history position in sync.
    public func reportWatchHistory(aid: Int64, cid: Int64, progressSeconds: Int64) async throws {
        let cookies = await authenticatedCookies()
        let csrf = try Self.csrfToken(in: cookies)
        try await postForm(
            url: URL(string: "https://api.bilibili.com/x/v2/history/report")!,
            values: [
                "aid": String(aid),
                "cid": String(cid),
                "progress": String(max(progressSeconds, 0)),
                "csrf": csrf,
            ],
            referer: "https://www.bilibili.com/video/av\(aid)/",
            cookies: cookies
        )
    }

    @discardableResult
    public func setFavorited(
        aid: Int64,
        favorited: Bool,
        folderID: Int64?
    ) async throws -> Int64 {
        let cookies = await authenticatedCookies()
        let resolvedFolderID: Int64
        if let folderID {
            resolvedFolderID = folderID
        } else {
            resolvedFolderID = try await favoriteFolderID(aid: aid, cookies: cookies)
        }
        let csrf = try Self.csrfToken(in: cookies)
        try await postForm(
            url: URL(string: "https://api.bilibili.com/x/v3/fav/resource/deal")!,
            values: [
                "rid": String(aid),
                "type": "2",
                "add_media_ids": favorited ? String(resolvedFolderID) : "",
                "del_media_ids": favorited ? "" : String(resolvedFolderID),
                "csrf": csrf,
                "csrf_token": csrf,
            ],
            referer: "https://www.bilibili.com/video/av\(aid)/",
            cookies: cookies
        )
        return resolvedFolderID
    }

    private func authenticatedCookies() async -> [HTTPCookie] {
        await cookieProvider.loadCookies()
    }

    private func interactionFlag(
        url: URL,
        referer: String,
        cookies: [HTTPCookie],
        kind: InteractionFlagKind
    ) async -> Bool {
        do {
            let root = try await requestObject(
                request: makeRequest(url: url, referer: referer, cookies: cookies)
            )
            try Self.validate(root)
            let value = root["data"]
            switch kind {
            case .liked:
                return Self.boolValue(value, preferredKeys: ["liked", "like"])
            case .coined:
                return Self.positiveValue(value, preferredKeys: ["multiply", "coin"])
            case .favorited:
                return Self.boolValue(value, preferredKeys: ["favoured", "favorited"])
            }
        } catch {
            return false
        }
    }

    private func favoriteFolderID(aid: Int64, cookies: [HTTPCookie]) async throws -> Int64 {
        let navURL = URL(string: "https://api.bilibili.com/x/web-interface/nav")!
        let navRoot = try await requestObject(
            request: makeRequest(url: navURL, referer: "https://www.bilibili.com/", cookies: cookies)
        )
        try Self.validate(navRoot)
        guard
            Self.boolValue(navRoot.value(at: ["data", "isLogin"]), preferredKeys: []),
            let mid = navRoot.int64Value(at: ["data", "mid"]),
            mid > 0
        else {
            throw ServiceError.loginRequired
        }

        var components = URLComponents(string: "https://api.bilibili.com/x/v3/fav/folder/created/list-all")!
        components.queryItems = [
            URLQueryItem(name: "up_mid", value: String(mid)),
            URLQueryItem(name: "rid", value: String(aid)),
            URLQueryItem(name: "type", value: "2"),
            URLQueryItem(name: "web_location", value: "333.1387"),
        ]
        let folderRoot = try await requestObject(
            request: makeRequest(
                url: components.url!,
                referer: "https://space.bilibili.com/\(mid)/favlist",
                cookies: cookies
            )
        )
        try Self.validate(folderRoot)
        let folders = (folderRoot.arrayValue(at: ["data", "list"]) ?? [])
            .compactMap { $0 as? [String: Any] }
        let containingFolderID = folders.first(where: { folder in
            Self.boolValue(folder["fav_state"], preferredKeys: [])
        })?.int64Value(at: ["id"])
        guard let folderID = containingFolderID ?? folders.first?.int64Value(at: ["id"]) else {
            throw ServiceError.noFavoriteFolder
        }
        return folderID
    }

    private func postForm(
        url: URL,
        values: [String: String],
        referer: String,
        cookies: [HTTPCookie]
    ) async throws {
        var request = makeRequest(url: url, referer: referer, cookies: cookies)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        var components = URLComponents()
        components.queryItems = values.keys.sorted().map { key in
            URLQueryItem(name: key, value: values[key])
        }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let root = try await requestObject(request: request)
        try Self.validate(root)
    }

    private func makeRequest(url: URL, referer: String, cookies: [HTTPCookie]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(FocusVideoDetailService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        return DynamicFeedService.attach(cookies: cookies, to: request)
    }

    private func requestObject(request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await requestLoader(request)
        guard
            let response = response as? HTTPURLResponse,
            (200 ..< 300).contains(response.statusCode),
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ServiceError.invalidResponse
        }
        return root
    }

    private nonisolated static func validate(_ root: [String: Any]) throws {
        let code = root.intValue(at: ["code"]) ?? -1
        if code == -101 {
            throw ServiceError.loginRequired
        }
        guard code == 0 else {
            throw ServiceError.api(
                code: code,
                message: root.stringValue(at: ["message"]) ?? "未知错误"
            )
        }
    }

    private nonisolated static func csrfToken(in cookies: [HTTPCookie]) throws -> String {
        guard let token = cookies.first(where: { $0.name == "bili_jct" })?.value, !token.isEmpty else {
            throw ServiceError.loginRequired
        }
        return token
    }

    private nonisolated static func boolValue(_ value: Any?, preferredKeys: [String]) -> Bool {
        if let dictionary = value as? [String: Any] {
            for key in preferredKeys {
                if boolValue(dictionary[key], preferredKeys: []) {
                    return true
                }
            }
            return false
        }
        if let number = value as? NSNumber {
            return number.intValue != 0
        }
        if let string = value as? String {
            return string == "1" || string.caseInsensitiveCompare("true") == .orderedSame
        }
        return false
    }

    private nonisolated static func positiveValue(_ value: Any?, preferredKeys: [String]) -> Bool {
        if let dictionary = value as? [String: Any] {
            return preferredKeys.contains { key in
                positiveValue(dictionary[key], preferredKeys: [])
            }
        }
        if let number = value as? NSNumber {
            return number.int64Value > 0
        }
        if let string = value as? String, let number = Int64(string) {
            return number > 0
        }
        return false
    }
}

private extension Dictionary where Key == String, Value == Any {
    func value(at path: [String]) -> Any? {
        guard let first = path.first else {
            return nil
        }
        guard path.count > 1 else {
            return self[first]
        }
        guard let nested = self[first] as? [String: Any] else {
            return nil
        }
        return nested.value(at: Array(path.dropFirst()))
    }

    func arrayValue(at path: [String]) -> [Any]? {
        value(at: path) as? [Any]
    }

    func stringValue(at path: [String]) -> String? {
        if let string = value(at: path) as? String {
            return string
        }
        if let number = value(at: path) as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    func intValue(at path: [String]) -> Int? {
        if let number = value(at: path) as? NSNumber {
            return number.intValue
        }
        if let string = value(at: path) as? String {
            return Int(string)
        }
        return nil
    }

    func int64Value(at path: [String]) -> Int64? {
        if let number = value(at: path) as? NSNumber {
            return number.int64Value
        }
        if let string = value(at: path) as? String {
            return Int64(string)
        }
        return nil
    }
}
