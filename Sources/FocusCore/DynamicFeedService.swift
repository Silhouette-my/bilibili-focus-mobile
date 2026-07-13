import Foundation

public struct DynamicFeedService: Sendable {
    public struct FeedPage: Equatable, Sendable {
        public let cards: [DynamicCard]
        public let nextOffset: String?

        public init(cards: [DynamicCard], nextOffset: String?) {
            self.cards = cards
            self.nextOffset = nextOffset
        }
    }

    public enum ServiceError: Error, Equatable, Sendable, LocalizedError {
        case loginRequired
        case invalidResponse
        case api(code: Int, message: String)

        public var errorDescription: String? {
            switch self {
            case .loginRequired:
                return "需要登录或登录已失效"
            case .invalidResponse:
                return "动态接口返回无效数据"
            case let .api(code, message):
                return "动态接口失败（\(code)）：\(message)"
            }
        }
    }

    public typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let cookieProvider: any CookieSnapshotProvider
    private let requestLoader: RequestLoader
    private let timezoneOffsetMinutes: Int

    public init(
        cookieProvider: any CookieSnapshotProvider,
        timezoneOffsetMinutes: Int = -(TimeZone.current.secondsFromGMT() / 60),
        requestLoader: @escaping RequestLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.cookieProvider = cookieProvider
        self.timezoneOffsetMinutes = timezoneOffsetMinutes
        self.requestLoader = requestLoader
    }

    public func fetchFollowingFeed() async throws -> [DynamicCard] {
        try await fetchFollowingFeedPage().cards
    }

    public func fetchFollowingFeedPage(offset: String? = nil) async throws -> FeedPage {
        let cookies = await cookieProvider.loadCookies()
        guard !cookies.isEmpty else {
            throw ServiceError.loginRequired
        }

        var request = URLRequest(url: Self.endpoint(timezoneOffsetMinutes: timezoneOffsetMinutes, offset: offset))
        request.httpMethod = "GET"
        request.setValue("https://t.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request = Self.attach(cookies: cookies, to: request)

        let (data, response) = try await requestLoader(request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw ServiceError.invalidResponse
        }

        return try Self.decodeFeedPage(from: data)
    }

    public static func decodeCards(from data: Data) throws -> [DynamicCard] {
        try decodeFeedPage(from: data).cards
    }

    public static func decodeFeedPage(from data: Data) throws -> FeedPage {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.invalidResponse
        }

        let code = payload.intValue(at: ["code"]) ?? -1
        let message = payload.stringValue(at: ["message"]) ?? "unknown"

        if code == -101 {
            throw ServiceError.loginRequired
        }

        guard code == 0 else {
            throw ServiceError.api(code: code, message: message)
        }

        guard let items = payload.arrayValue(at: ["data", "items"]) else {
            return FeedPage(cards: [], nextOffset: nil)
        }

        let cards: [DynamicCard] = items.compactMap { item -> DynamicCard? in
            guard let dictionary = item as? [String: Any] else {
                return nil
            }
            return makeCard(from: dictionary)
        }

        let nextOffset = payload.stringValue(at: ["data", "offset"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FeedPage(cards: cards, nextOffset: nextOffset?.isEmpty == true ? nil : nextOffset)
    }

    public static func attach(cookies: [HTTPCookie], to request: URLRequest) -> URLRequest {
        guard !cookies.isEmpty else {
            return request
        }

        var updatedRequest = request
        let headerFields = HTTPCookie.requestHeaderFields(with: cookies)
        for (name, value) in headerFields {
            updatedRequest.setValue(value, forHTTPHeaderField: name)
        }
        return updatedRequest
    }

    private static func endpoint(timezoneOffsetMinutes: Int, offset: String?) -> URL {
        var components = URLComponents(string: "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all")!
        var queryItems = [
            URLQueryItem(name: "type", value: "all"),
            URLQueryItem(name: "timezone_offset", value: String(timezoneOffsetMinutes)),
            URLQueryItem(name: "features", value: "itemOpusStyle"),
        ]
        if let offset, !offset.isEmpty {
            queryItems.append(URLQueryItem(name: "offset", value: offset))
        }
        components.queryItems = queryItems
        return components.url!
    }

    private static func makeCard(from item: [String: Any]) -> DynamicCard? {
        let modules = item.dictionaryValue(at: ["modules"]) ?? [:]
        let author = modules.dictionaryValue(at: ["module_author"]) ?? [:]
        let dynamic = modules.dictionaryValue(at: ["module_dynamic"]) ?? [:]
        let major = dynamic.dictionaryValue(at: ["major"]) ?? [:]
        let basic = item.dictionaryValue(at: ["basic"]) ?? [:]

        guard
            let id = item.stringValue(at: ["id_str"])
                ?? basic.stringValue(at: ["comment_id_str"])
                ?? basic.stringValue(at: ["rid_str"])
                ?? basic.intValue(at: ["comment_id"]).map(String.init)
        else {
            return nil
        }

        let authorName = author.stringValue(at: ["name"]) ?? "Bilibili"
        let authorMID = author.intValue(at: ["mid"]).map(Int64.init) ?? 0
        let authorAvatar = normalizedURL(author.stringValue(at: ["face"]))
        let publishTime = author.stringValue(at: ["pub_time"])
            ?? author.stringValue(at: ["pub_action"])
            ?? author.stringValue(at: ["pub_time_label"])
            ?? ""

        let majorType = major.stringValue(at: ["type"]) ?? ""
        let primaryJumpCandidates = [
            basic.stringValue(at: ["jump_url"]),
            major.stringValue(at: ["archive", "jump_url"]),
            major.stringValue(at: ["article", "jump_url"]),
            major.stringValue(at: ["pgc", "jump_url"]),
            major.stringValue(at: ["courses", "jump_url"]),
            major.stringValue(at: ["music", "jump_url"]),
            major.stringValue(at: ["medialist", "jump_url"]),
            major.stringValue(at: ["live", "jump_url"]),
            major.stringValue(at: ["opus", "jump_url"]),
            major.stringValue(at: ["common", "jump_url"]),
        ]
        .compactMap(normalizedURL(_:))
        let jumpCandidates = primaryJumpCandidates + extractJumpURLs(from: major)

        let coverURLs = makeCoverURLs(major: major)
        let text = makeText(dynamic: dynamic, major: major)
        let videoURL = jumpCandidates.first(where: isVideoLikeURL(_:))
        let kind = makeKind(
            majorType: majorType,
            itemType: item.stringValue(at: ["type"]) ?? "",
            videoURL: videoURL,
            coverURLs: coverURLs
        )
        let articleCVID = major.stringValue(at: ["article", "id"]).flatMap(Int64.init)
            ?? major.stringValue(at: ["article", "id_str"]).flatMap(Int64.init)
            ?? major.stringValue(at: ["article", "cvid"]).flatMap(Int64.init)
            ?? major.intValue(at: ["article", "id"]).map(Int64.init)
            ?? jumpCandidates.compactMap(extractArticleCVID(from:)).first
        let articleURL: URL? = if kind == .articleLike {
            jumpCandidates.first(where: { extractArticleCVID(from: $0) != nil })
                .flatMap { extractArticleCVID(from: $0) }
                .flatMap { URL(string: "https://www.bilibili.com/read/cv\($0)") }
                ?? articleCVID.flatMap { URL(string: "https://www.bilibili.com/read/cv\($0)") }
        } else {
            nil
        }
        let opusDetailURL = primaryJumpCandidates.first(where: isOpusLikeURL(_:))
        let targetURL: URL
        switch kind {
        case .video:
            targetURL = videoURL
                ?? primaryJumpCandidates.first
                ?? jumpCandidates.first
                ?? fallbackTargetURL(for: id, kind: kind)
        case .articleLike:
            targetURL = articleURL
                ?? opusDetailURL
                ?? primaryJumpCandidates.first
                ?? jumpCandidates.first
                ?? fallbackTargetURL(for: id, kind: kind)
        case .text, .image:
            targetURL = opusDetailURL ?? fallbackTargetURL(for: id, kind: kind)
        }

        return DynamicCard(
            id: id,
            kind: kind,
            author: .init(mid: authorMID, name: authorName, avatarURL: authorAvatar),
            publishTime: publishTime,
            text: text,
            coverURLs: coverURLs,
            targetURL: targetURL,
            videoURL: videoURL
        )
    }

    private static func makeText(dynamic: [String: Any], major: [String: Any]) -> String {
        let bodyCandidates = [
            richTextPlainText(dynamic.arrayValue(at: ["desc", "rich_text_nodes"])),
            richTextPlainText(dynamic.arrayValue(at: ["desc", "rich_text_nodes_v2"])),
            dynamic.stringValue(at: ["desc", "text"]),
            richTextPlainText(major.arrayValue(at: ["opus", "summary", "rich_text_nodes"])),
            richTextPlainText(major.arrayValue(at: ["opus", "summary", "rich_text_nodes_v2"])),
            major.stringValue(at: ["opus", "summary", "text"]),
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        if let body = bodyCandidates.max(by: { $0.count < $1.count }) {
            return body
        }

        let candidates = [
            major.stringValue(at: ["archive", "title"]),
            major.stringValue(at: ["article", "title"]),
            major.stringValue(at: ["pgc", "title"]),
            major.stringValue(at: ["courses", "title"]),
            major.stringValue(at: ["music", "title"]),
            major.stringValue(at: ["medialist", "title"]),
            major.stringValue(at: ["live", "title"]),
            major.stringValue(at: ["common", "title"]),
        ] + extractTextCandidates(from: major)

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private static func richTextPlainText(_ nodes: [Any]?) -> String? {
        guard let nodes, !nodes.isEmpty else {
            return nil
        }
        let text = nodes.compactMap { rawNode -> String? in
            guard let node = rawNode as? [String: Any] else {
                return nil
            }
            return node.stringValue(at: ["word", "words"])
                ?? node.stringValue(at: ["words"])
                ?? node.stringValue(at: ["text"])
                ?? node.stringValue(at: ["orig_text"])
                ?? node.stringValue(at: ["rich", "text"])
                ?? node.stringValue(at: ["rich", "emoji", "text"])
                ?? node.stringValue(at: ["emoji", "text"])
        }.joined()
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static func makeCoverURLs(major: [String: Any]) -> [URL] {
        var urls: [URL] = []

        if let archiveCover = normalizedURL(major.stringValue(at: ["archive", "cover"])) {
            urls.append(archiveCover)
        }

        if let articleCovers = major.arrayValue(at: ["article", "covers"]) {
            urls.append(contentsOf: articleCovers.compactMap { cover in
                guard let value = cover as? String else { return nil }
                return normalizedURL(value)
            })
        }

        if let pgcCover = normalizedURL(
            major.stringValue(at: ["pgc", "cover"])
                ?? major.stringValue(at: ["pgc", "ep_cover"])
        ) {
            urls.append(pgcCover)
        }

        if let courseCover = normalizedURL(major.stringValue(at: ["courses", "cover"])) {
            urls.append(courseCover)
        }

        if let musicCover = normalizedURL(major.stringValue(at: ["music", "cover"])) {
            urls.append(musicCover)
        }

        if let medialistCover = normalizedURL(major.stringValue(at: ["medialist", "cover"])) {
            urls.append(medialistCover)
        }

        if let liveCover = normalizedURL(
            major.stringValue(at: ["live", "cover"])
                ?? major.stringValue(at: ["live", "room_cover"])
        ) {
            urls.append(liveCover)
        }

        if let drawItems = major.arrayValue(at: ["draw", "items"]) {
            urls.append(contentsOf: drawItems.compactMap { item in
                guard let dictionary = item as? [String: Any] else { return nil }
                return normalizedURL(
                    dictionary.stringValue(at: ["src"])
                        ?? dictionary.stringValue(at: ["url"])
                )
            })
        }

        if let opusPictures = major.arrayValue(at: ["opus", "pics"]) {
            urls.append(contentsOf: opusPictures.compactMap { picture in
                guard let dictionary = picture as? [String: Any] else { return nil }
                return normalizedURL(
                    dictionary.stringValue(at: ["url"])
                        ?? dictionary.stringValue(at: ["src"])
                )
            })
        }

        if let commonCover = normalizedURL(major.stringValue(at: ["common", "cover"])) {
            urls.append(commonCover)
        }

        urls.append(contentsOf: extractImageURLs(from: major))

        var deduplicated: [URL] = []
        var seen = Set<String>()
        for url in urls {
            let key = url.absoluteString
            guard seen.insert(key).inserted else {
                continue
            }
            deduplicated.append(url)
        }
        return deduplicated
    }

    private static func makeKind(
        majorType: String,
        itemType: String,
        videoURL: URL?,
        coverURLs: [URL]
    ) -> DynamicCard.Kind {
        if videoURL != nil
            || itemType.contains("_AV")
            || [
                "MAJOR_TYPE_ARCHIVE",
                "MAJOR_TYPE_PGC",
                "MAJOR_TYPE_COURSES",
                "MAJOR_TYPE_MEDIALIST",
            ].contains(majorType)
        {
            return .video
        }

        switch majorType {
        case "MAJOR_TYPE_DRAW", "MAJOR_TYPE_OPUS":
            return coverURLs.isEmpty ? .text : .image
        case "MAJOR_TYPE_ARTICLE":
            return .articleLike
        default:
            return coverURLs.isEmpty ? .text : .image
        }
    }

    private static func normalizedURL(_ rawValue: String?) -> URL? {
        guard var rawValue else {
            return nil
        }

        rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            return nil
        }

        if let canonicalOpusURL = canonicalOpusURLFromScheme(rawValue) {
            return canonicalOpusURL
        }

        if rawValue.hasPrefix("//") {
            rawValue = "https:\(rawValue)"
        } else if rawValue.hasPrefix("/opus/")
            || rawValue.hasPrefix("/video/")
            || rawValue.hasPrefix("/bangumi/play/")
        {
            rawValue = "https://www.bilibili.com\(rawValue)"
        } else if rawValue.hasPrefix("/") {
            rawValue = "https://t.bilibili.com\(rawValue)"
        }

        guard let url = URL(string: rawValue) else {
            return nil
        }

        return FocusNavigationPolicy.canonicalWebURL(for: url)
    }

    private static func canonicalOpusURLFromScheme(_ rawValue: String) -> URL? {
        guard
            let url = URL(string: rawValue),
            url.scheme?.lowercased() == "bilibili",
            let host = url.host?.lowercased()
        else {
            return nil
        }
        let pathComponents = url.path.split(separator: "/").map(String.init)
        let candidate: String?
        switch host {
        case "following", "opus":
            candidate = pathComponents.count == 2 && pathComponents[0].lowercased() == "detail"
                ? pathComponents[1]
                : nil
        case "dynamic":
            candidate = pathComponents.count == 1 ? pathComponents[0] : nil
        default:
            candidate = nil
        }
        guard let candidate, !candidate.isEmpty, candidate.allSatisfy(\.isNumber) else {
            return nil
        }
        return URL(string: "https://www.bilibili.com/opus/\(candidate)")
    }

    private static func isOpusLikeURL(_ url: URL) -> Bool {
        let hosts = Set(["bilibili.com", "www.bilibili.com", "m.bilibili.com"])
        guard hosts.contains(url.host?.lowercased() ?? "") else {
            return false
        }
        let components = url.path.split(separator: "/")
        guard components.count == 2, components[0].lowercased() == "opus" else {
            return false
        }
        return components[1].allSatisfy(\.isNumber)
    }

    private static func isVideoLikeURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasPrefix("/video/") || path.hasPrefix("/bangumi/play/")
    }

    private static func extractArticleCVID(from url: URL) -> Int64? {
        if url.scheme?.lowercased() == "bilibili", url.host?.lowercased() == "article",
           let component = url.path.split(separator: "/").first
        {
            let candidate = String(component).lowercased().replacingOccurrences(of: "cv", with: "")
            return candidate.allSatisfy(\.isNumber) ? Int64(candidate) : nil
        }
        let hosts = Set(["bilibili.com", "www.bilibili.com", "m.bilibili.com"])
        guard hosts.contains(url.host?.lowercased() ?? "") else { return nil }
        let parts = url.path.split(separator: "/")
        if parts.count == 2,
           parts[0].caseInsensitiveCompare("read") == .orderedSame,
           parts[1].lowercased().hasPrefix("cv")
        {
            let candidate = String(parts[1].dropFirst(2))
            return candidate.allSatisfy(\.isNumber) ? Int64(candidate) : nil
        }
        guard url.path.lowercased() == "/read/mobile",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("id") == .orderedSame })?
            .value
            .flatMap { $0.allSatisfy(\.isNumber) ? Int64($0) : nil }
    }

    private static func extractJumpURLs(from value: Any) -> [URL] {
        extractURLs(
            from: value,
            matchingKeys: ["jump_url", "url", "link", "target_url", "target", "schema"],
            maxDepth: 4,
            predicate: isLikelyNavigationURL(_:)
        )
    }

    private static func extractImageURLs(from value: Any) -> [URL] {
        extractURLs(
            from: value,
            matchingKeys: ["cover", "src", "url", "image", "img", "pic", "poster"],
            maxDepth: 4,
            predicate: isLikelyImageURL(_:)
        )
    }

    private static func extractTextCandidates(from value: Any) -> [String?] {
        var results: [String] = []
        collectTextCandidates(
            from: value,
            matchingKeys: ["title", "text", "content", "desc", "summary", "copy_text", "name"],
            maxDepth: 4,
            into: &results
        )

        var deduplicated: [String?] = []
        var seen = Set<String>()
        for text in results {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                !trimmed.isEmpty,
                !trimmed.contains("http://"),
                !trimmed.contains("https://"),
                seen.insert(trimmed).inserted
            else {
                continue
            }
            deduplicated.append(trimmed)
        }

        return deduplicated
    }

    private static func extractURLs(
        from value: Any,
        matchingKeys: Set<String>,
        maxDepth: Int,
        predicate: (String) -> Bool
    ) -> [URL] {
        var results: [URL] = []
        collectURLs(
            from: value,
            matchingKeys: matchingKeys,
            maxDepth: maxDepth,
            predicate: predicate,
            into: &results
        )

        var deduplicated: [URL] = []
        var seen = Set<String>()
        for url in results {
            guard seen.insert(url.absoluteString).inserted else {
                continue
            }
            deduplicated.append(url)
        }
        return deduplicated
    }

    private static func collectURLs(
        from value: Any,
        matchingKeys: Set<String>,
        maxDepth: Int,
        predicate: (String) -> Bool,
        into results: inout [URL]
    ) {
        guard maxDepth >= 0 else {
            return
        }

        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                if matchingKeys.contains(key.lowercased()),
                   let rawValue = nestedValue as? String,
                   predicate(rawValue),
                   let url = normalizedURL(rawValue)
                {
                    results.append(url)
                }

                collectURLs(
                    from: nestedValue,
                    matchingKeys: matchingKeys,
                    maxDepth: maxDepth - 1,
                    predicate: predicate,
                    into: &results
                )
            }
            return
        }

        if let array = value as? [Any] {
            for nestedValue in array {
                collectURLs(
                    from: nestedValue,
                    matchingKeys: matchingKeys,
                    maxDepth: maxDepth - 1,
                    predicate: predicate,
                    into: &results
                )
            }
        }
    }

    private static func collectTextCandidates(
        from value: Any,
        matchingKeys: Set<String>,
        maxDepth: Int,
        into results: inout [String]
    ) {
        guard maxDepth >= 0 else {
            return
        }

        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                if matchingKeys.contains(key.lowercased()),
                   let text = nestedValue as? String
                {
                    results.append(text)
                }

                collectTextCandidates(
                    from: nestedValue,
                    matchingKeys: matchingKeys,
                    maxDepth: maxDepth - 1,
                    into: &results
                )
            }
            return
        }

        if let array = value as? [Any] {
            for nestedValue in array {
                collectTextCandidates(
                    from: nestedValue,
                    matchingKeys: matchingKeys,
                    maxDepth: maxDepth - 1,
                    into: &results
                )
            }
        }
    }

    private static func isLikelyNavigationURL(_ rawValue: String) -> Bool {
        guard let url = normalizedURL(rawValue) else {
            return false
        }

        let host = url.host?.lowercased() ?? ""
        guard host.contains("bilibili.com") else {
            return false
        }

        return !isLikelyImageURL(url.absoluteString)
    }

    private static func isLikelyImageURL(_ rawValue: String) -> Bool {
        guard let url = normalizedURL(rawValue) else {
            return false
        }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let imageExtensions = [".jpg", ".jpeg", ".png", ".webp", ".avif", ".gif", ".bmp"]

        if host.contains("hdslb.com") {
            return true
        }

        if imageExtensions.contains(where: path.hasSuffix(_:)) {
            return true
        }

        return path.contains("/bfs/")
    }

    private static func fallbackTargetURL(for id: String, kind: DynamicCard.Kind) -> URL {
        switch kind {
        case .video:
            return URL(string: "https://t.bilibili.com/\(id)")!
        case .text, .image, .articleLike:
            return URL(string: "https://www.bilibili.com/opus/\(id)")!
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func value(at path: [String]) -> Any? {
        guard let key = path.first else {
            return nil
        }

        let nextValue = self[key]
        guard path.count > 1 else {
            return nextValue
        }

        guard let nestedDictionary = nextValue as? [String: Any] else {
            return nil
        }

        return nestedDictionary.value(at: Array(path.dropFirst()))
    }

    func dictionaryValue(at path: [String]) -> [String: Any]? {
        value(at: path) as? [String: Any]
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
        if let int = value(at: path) as? Int {
            return int
        }

        if let number = value(at: path) as? NSNumber {
            return number.intValue
        }

        if let string = value(at: path) as? String {
            return Int(string)
        }

        return nil
    }
}
