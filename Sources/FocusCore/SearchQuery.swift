import Foundation

public struct SearchQuery: Equatable, Sendable {
    public let keyword: String

    public init(keyword: String) {
        self.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var resultURL: URL {
        var components = URLComponents(string: "https://search.bilibili.com/all")!
        components.queryItems = [
            URLQueryItem(name: "keyword", value: keyword),
        ]
        return components.url!
    }
}

public enum SearchResultFilter: String, CaseIterable, Equatable, Sendable, Identifiable {
    case all
    case video
    case users
    case live
    case bangumi
    case film

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            return "综合"
        case .video:
            return "视频"
        case .users:
            return "UP主"
        case .live:
            return "直播"
        case .bangumi:
            return "番剧"
        case .film:
            return "影视"
        }
    }

    var apiSearchType: String? {
        switch self {
        case .all:
            return nil
        case .video:
            return "video"
        case .users:
            return "bili_user"
        case .live:
            return "live_room"
        case .bangumi:
            return "media_bangumi"
        case .film:
            return "media_ft"
        }
    }

    var sectionTitle: String {
        switch self {
        case .all:
            return "综合"
        case .video:
            return "视频结果"
        case .users:
            return "相关 UP 主"
        case .live:
            return "直播"
        case .bangumi:
            return "番剧"
        case .film:
            return "影视"
        }
    }

    public static let defaultOrder: [SearchResultFilter] = [
        .all,
        .video,
        .users,
        .live,
        .bangumi,
        .film,
    ]
}

public enum SearchVideoSortOption: String, CaseIterable, Equatable, Sendable, Identifiable {
    case `default`
    case mostPlayed
    case latestPublished

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .default:
            return "默认"
        case .mostPlayed:
            return "最多播放"
        case .latestPublished:
            return "最新发布"
        }
    }

    var apiOrderValue: String? {
        switch self {
        case .default:
            return nil
        case .mostPlayed:
            return "click"
        case .latestPublished:
            return "pubdate"
        }
    }
}

public struct SearchResultPage: Equatable, Sendable {
    public let sections: [SearchResultSection]
    public let nextPage: Int?

    public init(sections: [SearchResultSection], nextPage: Int?) {
        self.sections = sections
        self.nextPage = nextPage
    }
}

public struct SearchResultSection: Equatable, Sendable, Identifiable {
    public let filter: SearchResultFilter
    public let items: [SearchResultItem]

    public init(filter: SearchResultFilter, items: [SearchResultItem]) {
        self.filter = filter
        self.items = items
    }

    public var id: String { filter.rawValue }
    public var title: String { filter.sectionTitle }
}

public struct SearchResultItem: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case video
        case user
        case live
        case media
    }

    public struct PreviewVideo: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let coverURL: URL?
        public let targetURL: URL
        public let metadataText: String
        public let badgeText: String

        public init(
            id: String,
            title: String,
            coverURL: URL?,
            targetURL: URL,
            metadataText: String = "",
            badgeText: String = ""
        ) {
            self.id = id
            self.title = title
            self.coverURL = coverURL
            self.targetURL = targetURL
            self.metadataText = metadataText
            self.badgeText = badgeText
        }
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let metadataText: String
    public let badgeText: String
    public let descriptionText: String
    public let coverURL: URL?
    public let avatarURL: URL?
    public let targetURL: URL
    public let previews: [PreviewVideo]

    public init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String = "",
        metadataText: String = "",
        badgeText: String = "",
        descriptionText: String = "",
        coverURL: URL? = nil,
        avatarURL: URL? = nil,
        targetURL: URL,
        previews: [PreviewVideo] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.metadataText = metadataText
        self.badgeText = badgeText
        self.descriptionText = descriptionText
        self.coverURL = coverURL
        self.avatarURL = avatarURL
        self.targetURL = targetURL
        self.previews = previews
    }
}

public struct SearchResultService: Sendable {
    public enum ServiceError: Error, Equatable, Sendable, LocalizedError {
        case invalidResponse
        case api(code: Int, message: String)
        case signingUnavailable

        public var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "搜索接口返回无效数据"
            case let .api(code, message):
                if code == -412 {
                    return "搜索接口触发风控（\(code)）：先在网页登录一次 bilibili 再重试"
                }
                return "搜索接口失败（\(code)）：\(message)"
            case .signingUnavailable:
                return "搜索签名初始化失败"
            }
        }
    }

    public typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let cookieProvider: any CookieSnapshotProvider
    private let requestLoader: RequestLoader
    private let userAgent: String
    private let wbiSigner: WBISigner

    public init(
        cookieProvider: any CookieSnapshotProvider,
        userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        requestLoader: @escaping RequestLoader = { request in
            try await BiliAPINetwork.data(for: request)
        }
    ) {
        self.cookieProvider = cookieProvider
        self.requestLoader = requestLoader
        self.userAgent = userAgent
        wbiSigner = .shared
    }

    init(
        cookieProvider: any CookieSnapshotProvider,
        userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        wbiSigner: WBISigner,
        requestLoader: @escaping RequestLoader
    ) {
        self.cookieProvider = cookieProvider
        self.requestLoader = requestLoader
        self.userAgent = userAgent
        self.wbiSigner = wbiSigner
    }

    public func fetchPage(
        for query: SearchQuery,
        filter: SearchResultFilter = .all,
        page: Int = 1,
        videoSort: SearchVideoSortOption = .default
    ) async throws -> SearchResultPage {
        let cookies = await cookieProvider.loadCookies()
        let navigationRequest = Self.makeNavigationRequest(
            cookies: cookies,
            userAgent: userAgent
        )
        let response: WBISigner.HTTPResponse
        do {
            response = try await wbiSigner.execute(
                parameters: Self.searchParameters(
                    query: query,
                    filter: filter,
                    page: page,
                    videoSort: videoSort
                ),
                navigationRequest: navigationRequest,
                requestLoader: requestLoader
            ) { signedQuery in
                try Self.makeSearchRequest(
                    query: query,
                    filter: filter,
                    signedQuery: signedQuery,
                    cookies: cookies,
                    userAgent: userAgent
                )
            }
        } catch is WBISigner.SigningError {
            throw ServiceError.signingUnavailable
        }

        guard
            (200 ..< 300).contains(response.response.statusCode)
        else {
            throw ServiceError.invalidResponse
        }

        return try Self.decodePage(
            from: response.data,
            query: query,
            filter: filter,
            requestedPage: page
        )
    }

    public static func decodePage(
        from data: Data,
        query: SearchQuery,
        filter: SearchResultFilter,
        requestedPage: Int = 1
    ) throws -> SearchResultPage {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.invalidResponse
        }

        let code = intValue(in: payload, path: ["code"]) ?? -1
        let message = stringValue(in: payload, path: ["message"]) ?? "unknown"
        guard code == 0 else {
            throw ServiceError.api(code: code, message: message)
        }

        guard let dataPayload = dictionaryValue(in: payload, path: ["data"]) else {
            return SearchResultPage(sections: [], nextPage: nil)
        }

        if filter == .all {
            let sections = makeOverviewSections(from: dataPayload)
            let nextPage = sections.contains(where: { $0.filter == .video && !$0.items.isEmpty }) ? 2 : nil
            return SearchResultPage(sections: sections, nextPage: nextPage)
        }

        let items = arrayValue(in: dataPayload, path: ["result"])?.compactMap { $0 as? [String: Any] } ?? []
        let section = makeSection(filter: filter, items: items)
        let currentPage = intValue(in: dataPayload, path: ["page"]) ?? requestedPage
        let totalPages = intValue(in: dataPayload, path: ["numPages"]) ?? currentPage
        let nextPage = currentPage < totalPages ? currentPage + 1 : nil
        return SearchResultPage(sections: section.items.isEmpty ? [] : [section], nextPage: nextPage)
    }

    public static func attach(cookies: [HTTPCookie], to request: URLRequest) -> URLRequest {
        CookieRequestPolicy.attach(cookies: cookies, to: request)
    }

    private static func makeOverviewSections(from dataPayload: [String: Any]) -> [SearchResultSection] {
        let blocks = arrayValue(in: dataPayload, path: ["result"])?.compactMap { $0 as? [String: Any] } ?? []
        let mappedSections: [SearchResultSection] = blocks.compactMap { block in
            guard
                let resultType = stringValue(in: block, path: ["result_type"]),
                let filter = filter(for: resultType)
            else {
                return nil
            }

            let items = arrayValue(in: block, path: ["data"])?.compactMap { $0 as? [String: Any] } ?? []
            return makeSection(filter: filter, items: items)
        }

        var sectionMap: [SearchResultFilter: SearchResultSection] = [:]
        for section in mappedSections where !section.items.isEmpty {
            sectionMap[section.filter] = section
        }

        return SearchResultFilter.defaultOrder
            .filter { $0 != .all }
            .compactMap { sectionMap[$0] }
    }

    private static func filter(for rawResultType: String) -> SearchResultFilter? {
        switch rawResultType {
        case "video":
            return .video
        case "bili_user":
            return .users
        case "live_room":
            return .live
        case "media_bangumi":
            return .bangumi
        case "media_ft":
            return .film
        default:
            return nil
        }
    }

    private static func makeSection(filter: SearchResultFilter, items: [[String: Any]]) -> SearchResultSection {
        let mappedItems: [SearchResultItem] = items.compactMap { item in
            switch filter {
            case .all:
                return nil
            case .video:
                return makeVideoItem(from: item)
            case .users:
                return makeUserItem(from: item)
            case .live:
                return makeLiveItem(from: item)
            case .bangumi, .film:
                return makeMediaItem(from: item, filter: filter)
            }
        }

        return SearchResultSection(filter: filter, items: mappedItems)
    }

    private static func makeVideoItem(from item: [String: Any]) -> SearchResultItem? {
        guard
            let targetURL = normalizedNavigationURL(
                stringValue(in: item, path: ["arcurl"])
                    ?? stringValue(in: item, path: ["url"])
            )
        else {
            return nil
        }

        let title = cleanText(
            stringValue(in: item, path: ["title"])
                ?? stringValue(in: item, path: ["typename"])
        )
        let subtitle = cleanText(
            stringValue(in: item, path: ["author"])
                ?? stringValue(in: item, path: ["up_name"])
                ?? stringValue(in: item, path: ["uname"])
        )
        let playText = formattedCount(
            stringValue(in: item, path: ["play"])
                ?? stringValue(in: item, path: ["stat", "view"])
        )
        let durationText = durationLabel(
            stringValue(in: item, path: ["duration"])
                ?? stringValue(in: item, path: ["length"])
        )
        let badgeText = durationText
        let metadataText = playText.isEmpty ? cleanText(stringValue(in: item, path: ["pubdate"])) : "\(playText)播放"
        let descriptionText = cleanText(
            stringValue(in: item, path: ["description"])
                ?? stringValue(in: item, path: ["desc"])
        )
        let coverURL = normalizedImageURL(
            stringValue(in: item, path: ["pic"])
                ?? stringValue(in: item, path: ["cover"])
        )
        let id = stringValue(in: item, path: ["bvid"])
            ?? stringValue(in: item, path: ["id"])
            ?? targetURL.absoluteString

        return SearchResultItem(
            id: id,
            kind: .video,
            title: title.isEmpty ? "视频" : title,
            subtitle: subtitle,
            metadataText: metadataText,
            badgeText: badgeText,
            descriptionText: descriptionText,
            coverURL: coverURL,
            targetURL: targetURL
        )
    }

    private static func makeUserItem(from item: [String: Any]) -> SearchResultItem? {
        let id = stringValue(in: item, path: ["mid"])
            ?? stringValue(in: item, path: ["uid"])
            ?? UUID().uuidString
        let fallbackSpaceURL = URL(string: "https://space.bilibili.com/\(id)")!
        let targetURL = normalizedNavigationURL(
            stringValue(in: item, path: ["uri"])
                ?? stringValue(in: item, path: ["url"])
                ?? stringValue(in: item, path: ["space_url"])
                ?? fallbackSpaceURL.absoluteString
        ) ?? fallbackSpaceURL
        let title = cleanText(
            stringValue(in: item, path: ["uname"])
                ?? stringValue(in: item, path: ["title"])
        )
        let signature = cleanText(
            stringValue(in: item, path: ["usign"])
                ?? stringValue(in: item, path: ["desc"])
        )
        let fansText = formattedCount(
            stringValue(in: item, path: ["fans"])
                ?? stringValue(in: item, path: ["fans_count"])
        )
        let videoCount = plainCountString(
            stringValue(in: item, path: ["videos"])
                ?? stringValue(in: item, path: ["archive_count"])
        )
        let metadataText = [
            fansText.isEmpty ? nil : "粉丝 \(fansText)",
            videoCount.isEmpty ? nil : "视频 \(videoCount)"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let avatarURL = normalizedImageURL(
            stringValue(in: item, path: ["face"])
                ?? stringValue(in: item, path: ["upic"])
        )
        let previews = arrayValue(in: item, path: ["res"])?.compactMap { preview -> SearchResultItem.PreviewVideo? in
            guard let dictionary = preview as? [String: Any] else {
                return nil
            }

            guard let previewURL = normalizedNavigationURL(
                stringValue(in: dictionary, path: ["arcurl"])
                    ?? stringValue(in: dictionary, path: ["url"])
            ) else {
                return nil
            }

            let previewID = stringValue(in: dictionary, path: ["bvid"])
                ?? stringValue(in: dictionary, path: ["id"])
                ?? previewURL.absoluteString
            let previewTitle = cleanText(
                stringValue(in: dictionary, path: ["title"])
                    ?? stringValue(in: dictionary, path: ["typename"])
            )
            let previewCover = normalizedImageURL(
                stringValue(in: dictionary, path: ["pic"])
                    ?? stringValue(in: dictionary, path: ["cover"])
            )
            let previewMetadata = formattedCount(
                stringValue(in: dictionary, path: ["play"])
                    ?? stringValue(in: dictionary, path: ["stat", "view"])
            )
            let previewBadge = durationLabel(
                stringValue(in: dictionary, path: ["duration"])
                    ?? stringValue(in: dictionary, path: ["length"])
            )

            return .init(
                id: previewID,
                title: previewTitle.isEmpty ? "视频" : previewTitle,
                coverURL: previewCover,
                targetURL: previewURL,
                metadataText: previewMetadata.isEmpty ? "" : "\(previewMetadata)播放",
                badgeText: previewBadge
            )
        } ?? []

        return SearchResultItem(
            id: id,
            kind: .user,
            title: title.isEmpty ? "UP主" : title,
            subtitle: signature,
            metadataText: metadataText,
            coverURL: nil,
            avatarURL: avatarURL,
            targetURL: targetURL,
            previews: previews
        )
    }

    private static func makeLiveItem(from item: [String: Any]) -> SearchResultItem? {
        let roomID = stringValue(in: item, path: ["roomid"])
            ?? stringValue(in: item, path: ["id"])
        let directRoomURL = roomID.flatMap { roomID in
            URL(string: "https://live.bilibili.com/\(roomID)")
        }
        guard
            let targetURL = directRoomURL.map(FocusNavigationPolicy.canonicalWebURL(for:))
                ?? normalizedNavigationURL(
                    stringValue(in: item, path: ["link"])
                        ?? stringValue(in: item, path: ["url"])
                )
        else {
            return nil
        }

        let title = cleanText(stringValue(in: item, path: ["title"]))
        let uname = cleanText(stringValue(in: item, path: ["uname"]))
        let areaText = cleanText(
            stringValue(in: item, path: ["area"])
                ?? stringValue(in: item, path: ["cate_name"])
        )
        let subtitle = [uname, areaText]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let onlineText = formattedCount(
            stringValue(in: item, path: ["online"])
                ?? stringValue(in: item, path: ["online_total"])
        )
        let badgeText = liveStatusText(
            rawValue: stringValue(in: item, path: ["live_status"]),
            fallback: areaText
        )
        let descriptionText = cleanText(
            stringValue(in: item, path: ["watched_show", "text_large"])
                ?? stringValue(in: item, path: ["desc"])
        )
        let coverURL = normalizedImageURL(
            stringValue(in: item, path: ["cover"])
                ?? stringValue(in: item, path: ["user_cover"])
                ?? stringValue(in: item, path: ["room_cover"])
        )
        let id = roomID ?? targetURL.absoluteString

        return SearchResultItem(
            id: id,
            kind: .live,
            title: title.isEmpty ? "直播" : title,
            subtitle: subtitle,
            metadataText: onlineText.isEmpty ? "" : "\(onlineText)人气",
            badgeText: badgeText,
            descriptionText: descriptionText,
            coverURL: coverURL,
            targetURL: targetURL
        )
    }

    private static func makeMediaItem(from item: [String: Any], filter: SearchResultFilter) -> SearchResultItem? {
        let rawURL = stringValue(in: item, path: ["url"])
            ?? stringValue(in: item, path: ["share_url"])
            ?? stringValue(in: item, path: ["media_url"])

        guard let targetURL = normalizedNavigationURL(rawURL) else {
            return nil
        }

        let title = cleanText(
            stringValue(in: item, path: ["title"])
                ?? stringValue(in: item, path: ["org_title"])
        )
        let styleText = cleanText(
            stringValue(in: item, path: ["styles"])
                ?? stringValue(in: item, path: ["style"])
        )
        let areaText = cleanText(stringValue(in: item, path: ["areas"]))
        let subtitle = [styleText, areaText]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let scoreText = mediaScoreText(from: item)
        let badgeText = cleanText(
            stringValue(in: item, path: ["season_type_name"])
                ?? stringValue(in: item, path: ["badge"])
        )
        let descriptionText = cleanText(
            stringValue(in: item, path: ["index_show"])
                ?? stringValue(in: item, path: ["desc"])
        )
        let coverURL = normalizedImageURL(
            stringValue(in: item, path: ["cover"])
                ?? stringValue(in: item, path: ["season_cover"])
                ?? stringValue(in: item, path: ["vertical_cover"])
        )
        let id = stringValue(in: item, path: ["season_id"])
            ?? stringValue(in: item, path: ["media_id"])
            ?? targetURL.absoluteString

        return SearchResultItem(
            id: id,
            kind: .media,
            title: title.isEmpty ? filter.sectionTitle : title,
            subtitle: subtitle,
            metadataText: scoreText,
            badgeText: badgeText,
            descriptionText: descriptionText,
            coverURL: coverURL,
            targetURL: targetURL
        )
    }

    private static func searchParameters(
        query: SearchQuery,
        filter: SearchResultFilter,
        page: Int,
        videoSort: SearchVideoSortOption
    ) -> [String: String] {
        var parameters = [
            "keyword": query.keyword,
            "page": String(max(page, 1)),
        ]
        if let searchType = filter.apiSearchType {
            parameters["search_type"] = searchType
        }

        if filter == .video, let orderValue = videoSort.apiOrderValue {
            parameters["order"] = orderValue
        }
        return parameters
    }

    private static func makeSearchRequest(
        query: SearchQuery,
        filter: SearchResultFilter,
        signedQuery: String,
        cookies: [HTTPCookie],
        userAgent: String
    ) throws -> URLRequest {
        let endpoint = BiliAPIContractCatalog.require(
            filter == .all
                ? "search.search.web_search"
                : "search.search.web_search_by_type"
        ).url
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw ServiceError.signingUnavailable
        }
        components.percentEncodedQuery = signedQuery
        guard let url = components.url else {
            throw ServiceError.signingUnavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(query.resultURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return attach(cookies: cookies, to: request)
    }

    private static func makeNavigationRequest(
        cookies: [HTTPCookie],
        userAgent: String
    ) -> URLRequest {
        var request = URLRequest(
            url: BiliAPIContractCatalog.require("credential.info.valid").url
        )
        request.httpMethod = "GET"
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return attach(cookies: cookies, to: request)
    }
}

private extension SearchResultService {
    static func dictionaryValue(in dictionary: [String: Any], path: [String]) -> [String: Any]? {
        value(in: dictionary, path: path) as? [String: Any]
    }

    static func arrayValue(in dictionary: [String: Any], path: [String]) -> [Any]? {
        value(in: dictionary, path: path) as? [Any]
    }

    static func stringValue(in dictionary: [String: Any], path: [String]) -> String? {
        if let string = value(in: dictionary, path: path) as? String {
            return string
        }

        if let number = value(in: dictionary, path: path) as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    static func intValue(in dictionary: [String: Any], path: [String]) -> Int? {
        if let int = value(in: dictionary, path: path) as? Int {
            return int
        }

        if let number = value(in: dictionary, path: path) as? NSNumber {
            return number.intValue
        }

        if let string = value(in: dictionary, path: path) as? String {
            return Int(string)
        }

        return nil
    }

    static func value(in dictionary: [String: Any], path: [String]) -> Any? {
        guard let key = path.first else {
            return dictionary
        }

        let nextValue = dictionary[key]
        guard path.count > 1 else {
            return nextValue
        }

        guard let nestedDictionary = nextValue as? [String: Any] else {
            return nil
        }

        return value(in: nestedDictionary, path: Array(path.dropFirst()))
    }

    static func cleanText(_ rawValue: String?) -> String {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return ""
        }

        value = value.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        let htmlEntities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " ",
        ]
        for (entity, replacement) in htmlEntities {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }

        return value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedNavigationURL(_ rawValue: String?) -> URL? {
        guard var rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            return nil
        }

        if rawValue.hasPrefix("//") {
            rawValue = "https:\(rawValue)"
        } else if rawValue.hasPrefix("/") {
            rawValue = "https://www.bilibili.com\(rawValue)"
        }

        guard let url = URL(string: rawValue) else {
            return nil
        }

        return FocusNavigationPolicy.canonicalWebURL(for: url)
    }

    static func normalizedImageURL(_ rawValue: String?) -> URL? {
        guard var rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            return nil
        }

        if rawValue.hasPrefix("//") {
            rawValue = "https:\(rawValue)"
        }

        return URL(string: rawValue)
    }

    static func formattedCount(_ rawValue: String?) -> String {
        let rawText = cleanText(rawValue)
        guard !rawText.isEmpty else {
            return ""
        }

        if rawText.contains("万") || rawText.contains("亿") {
            return rawText
        }

        let normalized = rawText.replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized) else {
            return rawText
        }

        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", value / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", value / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return String(Int(value))
        }
    }

    static func plainCountString(_ rawValue: String?) -> String {
        let rawText = cleanText(rawValue)
        guard !rawText.isEmpty else {
            return ""
        }

        if rawText.contains("万") || rawText.contains("亿") {
            return rawText
        }

        let normalized = rawText.replacingOccurrences(of: ",", with: "")
        guard let value = Int(normalized) else {
            return rawText
        }
        return String(value)
    }

    static func durationLabel(_ rawValue: String?) -> String {
        let rawText = cleanText(rawValue)
        guard !rawText.isEmpty else {
            return ""
        }

        if rawText.contains(":") {
            return rawText
        }

        let normalized = rawText.replacingOccurrences(of: ",", with: "")
        guard let seconds = Int(normalized), seconds > 0 else {
            return rawText
        }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func mediaScoreText(from item: [String: Any]) -> String {
        let rawScore = cleanText(
            stringValue(in: item, path: ["media_score", "score"])
                ?? stringValue(in: item, path: ["score"])
        )
        if !rawScore.isEmpty {
            return rawScore.hasPrefix("评分") ? rawScore : "评分 \(rawScore)"
        }

        let rawCount = cleanText(
            stringValue(in: item, path: ["cv"])
                ?? stringValue(in: item, path: ["index_show"])
        )
        return rawCount
    }

    static func liveStatusText(rawValue: String?, fallback: String) -> String {
        switch cleanText(rawValue) {
        case "1":
            return "直播中"
        case "0":
            return fallback.isEmpty ? "未开播" : fallback
        default:
            return fallback
        }
    }
}
