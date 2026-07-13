import CryptoKit
import Foundation

public enum FocusVideoIdentifier: Equatable, Sendable {
    case bvid(String)
    case aid(Int64)

    public static func extract(from url: URL) -> FocusVideoIdentifier? {
        guard let host = url.host?.lowercased(), host == "bilibili.com" || host.hasSuffix(".bilibili.com") else {
            return nil
        }
        let components = url.path.split(separator: "/").map(String.init)
        guard
            let videoIndex = components.firstIndex(where: { $0.caseInsensitiveCompare("video") == .orderedSame }),
            components.indices.contains(components.index(after: videoIndex))
        else {
            return nil
        }

        let candidate = components[components.index(after: videoIndex)]
        if candidate.count == 12,
           candidate.prefix(2).caseInsensitiveCompare("BV") == .orderedSame,
           candidate.dropFirst(2).allSatisfy({ $0.isLetter || $0.isNumber })
        {
            return .bvid(candidate)
        }

        let lowercased = candidate.lowercased()
        if lowercased.hasPrefix("av"),
           let aid = Int64(lowercased.dropFirst(2)),
           aid > 0
        {
            return .aid(aid)
        }

        return nil
    }

    public var requestQueryItem: URLQueryItem {
        switch self {
        case let .bvid(value):
            return URLQueryItem(name: "bvid", value: value)
        case let .aid(value):
            return URLQueryItem(name: "aid", value: String(value))
        }
    }
}

public struct FocusVideoDetail: Equatable, Sendable {
    public let bvid: String
    public let aid: Int64
    public let cid: Int64
    public let title: String
    public let summary: String
    public let coverURL: URL?
    public let duration: Int64
    public let publishedAt: Int64
    public let width: Int
    public let height: Int
    public let owner: FocusVideoOwner
    public let statistics: FocusVideoStatistics
    public let pages: [FocusVideoPage]
    public let episodeGroups: [FocusVideoEpisodeGroup]

    public init(
        bvid: String,
        aid: Int64,
        cid: Int64,
        title: String,
        summary: String,
        coverURL: URL?,
        duration: Int64,
        publishedAt: Int64,
        width: Int,
        height: Int,
        owner: FocusVideoOwner,
        statistics: FocusVideoStatistics,
        pages: [FocusVideoPage],
        episodeGroups: [FocusVideoEpisodeGroup]
    ) {
        self.bvid = bvid
        self.aid = aid
        self.cid = cid
        self.title = title
        self.summary = summary
        self.coverURL = coverURL
        self.duration = duration
        self.publishedAt = publishedAt
        self.width = width
        self.height = height
        self.owner = owner
        self.statistics = statistics
        self.pages = pages
        self.episodeGroups = episodeGroups
    }

    public var aspectRatio: Double {
        guard width > 0, height > 0 else {
            return 16.0 / 9.0
        }
        return Double(width) / Double(height)
    }
}

public struct FocusVideoOwner: Equatable, Sendable {
    public let mid: Int64
    public let name: String
    public let avatarURL: URL?

    public init(mid: Int64, name: String, avatarURL: URL?) {
        self.mid = mid
        self.name = name
        self.avatarURL = avatarURL
    }
}

public struct FocusVideoStatistics: Equatable, Sendable {
    public let views: Int64
    public let danmaku: Int64
    public let replies: Int64
    public let favorites: Int64
    public let coins: Int64
    public let shares: Int64
    public let likes: Int64

    public init(
        views: Int64,
        danmaku: Int64,
        replies: Int64,
        favorites: Int64,
        coins: Int64,
        shares: Int64,
        likes: Int64
    ) {
        self.views = views
        self.danmaku = danmaku
        self.replies = replies
        self.favorites = favorites
        self.coins = coins
        self.shares = shares
        self.likes = likes
    }
}

public struct FocusVideoPage: Identifiable, Equatable, Sendable {
    public var id: Int64 { cid }

    public let pageNumber: Int
    public let cid: Int64
    public let title: String
    public let duration: Int64

    public init(pageNumber: Int, cid: Int64, title: String, duration: Int64) {
        self.pageNumber = pageNumber
        self.cid = cid
        self.title = title
        self.duration = duration
    }
}

public struct FocusVideoEpisodeGroup: Identifiable, Equatable, Sendable {
    public var id: String { "\(title)::\(episodes.first?.bvid ?? "empty")" }

    public let title: String
    public let episodes: [FocusVideoEpisode]

    public init(title: String, episodes: [FocusVideoEpisode]) {
        self.title = title
        self.episodes = episodes
    }
}

public struct FocusVideoEpisode: Identifiable, Equatable, Sendable {
    public var id: String { "\(bvid)::\(cid)" }

    public let bvid: String
    public let aid: Int64
    public let cid: Int64
    public let title: String
    public let coverURL: URL?
    public let badge: String

    public init(
        bvid: String,
        aid: Int64,
        cid: Int64,
        title: String,
        coverURL: URL?,
        badge: String
    ) {
        self.bvid = bvid
        self.aid = aid
        self.cid = cid
        self.title = title
        self.coverURL = coverURL
        self.badge = badge
    }
}

public enum FocusRichTextRun: Codable, Equatable, Sendable {
    case text(
        value: String,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        color: String? = nil,
        linkURL: URL? = nil
    )
    case emote(alt: String, url: URL, width: Int = 0, height: Int = 0, animated: Bool = false)
    case resource(label: String, url: URL)

    public var plainText: String {
        switch self {
        case let .text(value, _, _, _, _, _, _): value
        case let .emote(alt, _, _, _, _): alt
        case let .resource(label, _): label
        }
    }
}

public struct FocusVideoComment: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let authorMID: Int64
    public let authorName: String
    public let avatarURL: URL?
    public let message: String
    public let contentRuns: [FocusRichTextRun]
    public let likes: Int64
    public let replies: Int64
    public let publishedAt: Int64
    public let previewReplies: [FocusVideoComment]

    public init(
        id: Int64,
        authorMID: Int64,
        authorName: String,
        avatarURL: URL?,
        message: String,
        contentRuns: [FocusRichTextRun]? = nil,
        likes: Int64,
        replies: Int64,
        publishedAt: Int64,
        previewReplies: [FocusVideoComment] = []
    ) {
        self.id = id
        self.authorMID = authorMID
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.message = message
        self.contentRuns = contentRuns ?? [.text(value: message)]
        self.likes = likes
        self.replies = replies
        self.publishedAt = publishedAt
        self.previewReplies = previewReplies
    }
}

public enum FocusVideoDanmakuMode: Int, Equatable, Sendable {
    case scrolling = 1
    case bottom = 4
    case top = 5
}

public struct FocusVideoDanmaku: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let progressMilliseconds: Int64
    public let mode: FocusVideoDanmakuMode
    public let fontSize: Int
    public let colorRGB: Int?
    public let content: String
    public let weight: Int
    public let pool: Int

    public init(
        id: Int64,
        progressMilliseconds: Int64,
        mode: FocusVideoDanmakuMode,
        fontSize: Int,
        colorRGB: Int?,
        content: String,
        weight: Int,
        pool: Int
    ) {
        self.id = id
        self.progressMilliseconds = progressMilliseconds
        self.mode = mode
        self.fontSize = fontSize
        self.colorRGB = colorRGB
        self.content = content
        self.weight = weight
        self.pool = pool
    }
}

public struct FocusVideoDanmakuView: Equatable, Sendable {
    public let state: Int
    public let segmentDurationMilliseconds: Int64
    public let totalSegments: Int
    public let count: Int64

    public var isClosed: Bool { state != 0 }

    public init(
        state: Int,
        segmentDurationMilliseconds: Int64,
        totalSegments: Int,
        count: Int64
    ) {
        self.state = state
        self.segmentDurationMilliseconds = segmentDurationMilliseconds
        self.totalSegments = totalSegments
        self.count = count
    }
}

public struct FocusVideoDanmakuSegment: Equatable, Sendable {
    public let danmakus: [FocusVideoDanmaku]
    public let isClosed: Bool

    public init(danmakus: [FocusVideoDanmaku], isClosed: Bool = false) {
        self.danmakus = danmakus
        self.isClosed = isClosed
    }
}

public struct FocusVideoPlaybackSource: Equatable, Sendable {
    public enum Stream: Equatable, Sendable {
        case progressive([URL])
        case dash(videoURL: URL, audioURL: URL?)
    }

    public let stream: Stream
    public let headers: [String: String]
    public let qualityDescription: String

    public init(stream: Stream, headers: [String: String], qualityDescription: String) {
        self.stream = stream
        self.headers = headers
        self.qualityDescription = qualityDescription
    }
}

public actor FocusVideoDetailService {
    public enum ServiceError: Error, Equatable, Sendable, LocalizedError {
        case unsupportedURL
        case invalidResponse
        case noStream
        case api(code: Int, message: String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedURL:
                return "暂不支持这个视频地址"
            case .invalidResponse:
                return "视频接口返回了无效数据"
            case .noStream:
                return "没有找到可用的原生播放源"
            case let .api(code, message):
                return "视频接口失败（\(code)）：\(message)"
            }
        }
    }

    public typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static let wbiMixinTable = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 52, 34, 44,
    ]

    private let cookieProvider: any CookieSnapshotProvider
    private let requestLoader: RequestLoader
    private var cachedWBIKey: String?
    private var cachedWBIKeyExpiration = Date.distantPast

    public init(
        cookieProvider: any CookieSnapshotProvider,
        requestLoader: @escaping RequestLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.cookieProvider = cookieProvider
        self.requestLoader = requestLoader
    }

    public nonisolated static func requestedPageNumber(from url: URL) -> Int? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("p") == .orderedSame })?
            .value
            .flatMap(Int.init)
    }

    public nonisolated static func requestedPageCID(from url: URL) -> Int64? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("cid") == .orderedSame })?
            .value
            .flatMap(Int64.init)
            .flatMap { $0 > 0 ? $0 : nil }
    }

    public func fetchDetail(for url: URL) async throws -> FocusVideoDetail {
        guard let identifier = FocusVideoIdentifier.extract(from: url) else {
            throw ServiceError.unsupportedURL
        }

        let cookies = await cookieProvider.loadCookies()
        var components = URLComponents(string: "https://api.bilibili.com/x/web-interface/view")!
        components.queryItems = [identifier.requestQueryItem]
        let request = makeRequest(
            url: components.url!,
            referer: url.absoluteString,
            cookies: cookies
        )
        let data = try await loadData(for: request)
        return try Self.decodeDetailResponse(data)
    }

    public func fetchComments(aid: Int64, page: Int = 1) async throws -> [FocusVideoComment] {
        guard aid > 0 else {
            return []
        }

        let cookies = await cookieProvider.loadCookies()
        let referer = "https://www.bilibili.com/video/av\(aid)/"
        let query = try await signedWBIQuery(
            parameters: [
                "type": "1",
                "oid": String(aid),
                "pn": String(max(page, 1)),
                "ps": "20",
                "sort": "2",
            ],
            referer: referer,
            cookies: cookies
        )
        let url = URL(string: "https://api.bilibili.com/x/v2/reply/wbi/main?\(query)")!
        let data = try await loadData(for: makeRequest(url: url, referer: referer, cookies: cookies))
        return try Self.decodeCommentsResponse(data)
    }

    public func fetchDanmakuView(aid: Int64, cid: Int64) async throws -> FocusVideoDanmakuView {
        let cookies = await cookieProvider.loadCookies()
        let referer = "https://www.bilibili.com/video/av\(aid)/"
        var components = URLComponents(string: "https://api.bilibili.com/x/v2/dm/web/view")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "oid", value: String(cid)),
            URLQueryItem(name: "pid", value: String(aid)),
        ]
        guard let url = components.url else {
            throw ServiceError.invalidResponse
        }
        var request = makeRequest(url: url, referer: referer, cookies: cookies)
        request.setValue("application/octet-stream, */*", forHTTPHeaderField: "Accept")
        let data = try await loadData(for: request)
        if let apiError = Self.binaryAPIError(data) {
            throw apiError
        }
        do {
            return try Self.decodeDanmakuView(data)
        } catch {
            throw ServiceError.invalidResponse
        }
    }

    public func fetchDanmakuSegment(
        aid: Int64,
        cid: Int64,
        segmentIndex: Int
    ) async throws -> FocusVideoDanmakuSegment {
        guard segmentIndex > 0 else {
            throw ServiceError.invalidResponse
        }
        let cookies = await cookieProvider.loadCookies()
        let referer = "https://www.bilibili.com/video/av\(aid)/"
        var lastError: ServiceError = .invalidResponse

        for attempt in 0 ..< 3 {
            let query = try await signedWBIQuery(
                parameters: [
                    "oid": String(cid),
                    "type": "1",
                    "pid": String(aid),
                    "segment_index": String(segmentIndex),
                    "web_location": "1550101",
                ],
                referer: referer,
                cookies: cookies
            )
            guard let url = URL(string: "https://api.bilibili.com/x/v2/dm/wbi/web/seg.so?\(query)") else {
                throw ServiceError.invalidResponse
            }
            var request = makeRequest(url: url, referer: referer, cookies: cookies)
            request.setValue("application/octet-stream, */*", forHTTPHeaderField: "Accept")
            let (data, response) = try await requestLoader(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ServiceError.invalidResponse
            }
            if httpResponse.statusCode == 403, attempt < 2 {
                invalidateWBIKey()
                continue
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                throw ServiceError.invalidResponse
            }
            if let apiError = Self.binaryAPIError(data) {
                lastError = apiError
                if case .api(code: -403, message: _) = apiError, attempt < 2 {
                    invalidateWBIKey()
                    continue
                }
                throw apiError
            }
            do {
                return try Self.decodeDanmakuSegment(data)
            } catch {
                throw ServiceError.invalidResponse
            }
        }
        throw lastError
    }

    public func fetchPlayback(bvid: String, cid: Int64) async throws -> FocusVideoPlaybackSource {
        let cookies = await cookieProvider.loadCookies()
        let referer = "https://www.bilibili.com/video/\(bvid)/"
        let baseParameters = [
            "bvid": bvid,
            "cid": String(cid),
            "qn": "80",
            "fourk": "1",
            "otype": "json",
        ]
        let headers = Self.mediaHeaders(cookies: cookies, referer: referer)

        var progressiveParameters = baseParameters
        progressiveParameters["fnval"] = "0"
        progressiveParameters["fnver"] = "0"
        progressiveParameters["platform"] = "html5"
        progressiveParameters["high_quality"] = "1"

        if let progressiveData = try? await loadUnsignedPlayURLResponse(
            parameters: progressiveParameters,
            referer: referer,
            cookies: cookies
        ),
           let source = try? Self.decodePlaybackResponse(progressiveData, headers: headers),
           case .progressive = source.stream
        {
            return source
        }

        var dashParameters = baseParameters
        dashParameters["fnval"] = "4048"
        dashParameters["fnver"] = "0"
        let dashData = try await loadPlayURLResponse(
            parameters: dashParameters,
            referer: referer,
            cookies: cookies
        )
        return try Self.decodePlaybackResponse(dashData, headers: headers)
    }

    public nonisolated static func decodeDetailResponse(_ data: Data) throws -> FocusVideoDetail {
        let root = try decodeRootObject(data)
        try validateAPIResponse(root)
        guard let payload = root.dictionaryValue(at: ["data"]) else {
            throw ServiceError.invalidResponse
        }

        let bvid = payload.stringValue(at: ["bvid"]) ?? ""
        let aid = payload.int64Value(at: ["aid"]) ?? 0
        let cid = payload.int64Value(at: ["cid"]) ?? 0
        guard !bvid.isEmpty, aid > 0, cid > 0 else {
            throw ServiceError.invalidResponse
        }

        let ownerPayload = payload.dictionaryValue(at: ["owner"]) ?? [:]
        let statisticsPayload = payload.dictionaryValue(at: ["stat"]) ?? [:]
        let dimensionPayload = payload.dictionaryValue(at: ["dimension"]) ?? [:]
        var pages = parsePages(payload)
        if pages.isEmpty {
            pages = [
                FocusVideoPage(
                    pageNumber: 1,
                    cid: cid,
                    title: payload.stringValue(at: ["title"]) ?? "视频",
                    duration: payload.int64Value(at: ["duration"]) ?? 0
                )
            ]
        }

        return FocusVideoDetail(
            bvid: bvid,
            aid: aid,
            cid: cid,
            title: payload.stringValue(at: ["title"]) ?? "视频",
            summary: payload.stringValue(at: ["desc"]) ?? "",
            coverURL: normalizedURL(payload.stringValue(at: ["pic"])),
            duration: payload.int64Value(at: ["duration"]) ?? 0,
            publishedAt: payload.int64Value(at: ["pubdate"]) ?? 0,
            width: dimensionPayload.intValue(at: ["width"]) ?? 0,
            height: dimensionPayload.intValue(at: ["height"]) ?? 0,
            owner: FocusVideoOwner(
                mid: ownerPayload.int64Value(at: ["mid"]) ?? 0,
                name: ownerPayload.stringValue(at: ["name"]) ?? "UP主",
                avatarURL: normalizedURL(ownerPayload.stringValue(at: ["face"]))
            ),
            statistics: FocusVideoStatistics(
                views: statisticsPayload.int64Value(at: ["view"]) ?? 0,
                danmaku: statisticsPayload.int64Value(at: ["danmaku"]) ?? 0,
                replies: statisticsPayload.int64Value(at: ["reply"]) ?? 0,
                favorites: statisticsPayload.int64Value(at: ["favorite"]) ?? 0,
                coins: statisticsPayload.int64Value(at: ["coin"]) ?? 0,
                shares: statisticsPayload.int64Value(at: ["share"]) ?? 0,
                likes: statisticsPayload.int64Value(at: ["like"]) ?? 0
            ),
            pages: pages,
            episodeGroups: parseEpisodeGroups(payload)
        )
    }

    public nonisolated static func decodeCommentsResponse(_ data: Data) throws -> [FocusVideoComment] {
        let root = try decodeRootObject(data)
        try validateAPIResponse(root)
        let replies = root.arrayValue(at: ["data", "replies"]) ?? []
        return replies.compactMap { ($0 as? [String: Any]).flatMap(decodeComment(_:)) }
    }

    private nonisolated static func decodeComment(_ reply: [String: Any]) -> FocusVideoComment? {
        guard
            let member = reply.dictionaryValue(at: ["member"]),
            let content = reply.dictionaryValue(at: ["content"]),
            let message = content.stringValue(at: ["message"]),
            !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        let previewReplies = (reply.arrayValue(at: ["replies"]) ?? [])
            .compactMap { ($0 as? [String: Any]).flatMap(decodeComment(_:)) }
        return FocusVideoComment(
            id: reply.int64Value(at: ["rpid"]) ?? 0,
            authorMID: reply.int64Value(at: ["mid"]) ?? 0,
            authorName: member.stringValue(at: ["uname"]) ?? "用户",
            avatarURL: normalizedURL(member.stringValue(at: ["avatar"])),
            message: message,
            contentRuns: decodeRichText(content: content, message: message),
            likes: reply.int64Value(at: ["like"]) ?? 0,
            replies: reply.int64Value(at: ["rcount"]) ?? 0,
            publishedAt: reply.int64Value(at: ["ctime"]) ?? 0,
            previewReplies: previewReplies
        )
    }

    private nonisolated static func decodeRichText(content: [String: Any], message: String) -> [FocusRichTextRun] {
        if let rawNodes = content.arrayValue(at: ["rich_text_nodes"]) {
            let nodes = rawNodes.compactMap { rawNode -> FocusRichTextRun? in
                guard let node = rawNode as? [String: Any] else { return nil }
                let text = node.stringValue(at: ["text"])
                    ?? node.stringValue(at: ["orig_text"])
                    ?? ""
                let rawEmojiURL = node.stringValue(at: ["emoji", "icon_url"])
                    ?? node.stringValue(at: ["emoji", "url"])
                    ?? node.stringValue(at: ["rich", "emoji", "icon_url"])
                    ?? node.stringValue(at: ["icon_url"])
                if let url = normalizedURL(rawEmojiURL) {
                    let emoji = node.dictionaryValue(at: ["emoji"])
                        ?? node.dictionaryValue(at: ["rich", "emoji"])
                    let size = emoji?.intValue(at: ["meta", "size"]) ?? 0
                    return .emote(
                        alt: text.isEmpty ? (emoji?.stringValue(at: ["text"]) ?? "[表情]") : text,
                        url: url,
                        width: emoji?.intValue(at: ["width"]) ?? size,
                        height: emoji?.intValue(at: ["height"]) ?? size,
                        animated: isAnimatedImageURL(url)
                    )
                }
                guard !text.isEmpty else { return nil }
                return .text(
                    value: text,
                    linkURL: normalizedURL(node.stringValue(at: ["jump_url"]) ?? node.stringValue(at: ["link"]))
                )
            }
            if !nodes.isEmpty { return nodes }
        }

        var replacements: [String: FocusRichTextRun] = [:]
        content.dictionaryValue(at: ["emote"])?.forEach { token, rawValue in
            guard
                let emote = rawValue as? [String: Any],
                let url = normalizedURL(
                    emote.stringValue(at: ["gif_url"])
                        ?? emote.stringValue(at: ["url"])
                        ?? emote.stringValue(at: ["icon_url"])
                )
            else { return }
            let size = emote.intValue(at: ["meta", "size"]) ?? 0
            replacements[token] = .emote(
                alt: emote.stringValue(at: ["text"]) ?? token,
                url: url,
                width: size,
                height: size,
                animated: isAnimatedImageURL(url)
            )
        }
        content.dictionaryValue(at: ["jump_url"])?.forEach { token, rawValue in
            guard replacements[token] == nil else { return }
            let rawURL = (rawValue as? String)
                ?? (rawValue as? [String: Any])?.stringValue(at: ["url"])
                ?? (rawValue as? [String: Any])?.stringValue(at: ["jump_url"])
            if let url = normalizedURL(rawURL) {
                replacements[token] = .text(value: token, linkURL: url)
            }
        }
        guard !replacements.isEmpty else { return [.text(value: message)] }

        let tokens = replacements.keys.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs < rhs : lhs.count > rhs.count
        }
        var result: [FocusRichTextRun] = []
        var cursor = message.startIndex
        while cursor < message.endIndex {
            let matches = tokens.compactMap { token -> (Range<String.Index>, String)? in
                message.range(of: token, range: cursor ..< message.endIndex).map { ($0, token) }
            }
            guard let match = matches.min(by: { lhs, rhs in
                lhs.0.lowerBound == rhs.0.lowerBound ? lhs.1.count > rhs.1.count : lhs.0.lowerBound < rhs.0.lowerBound
            }) else {
                result.append(.text(value: String(message[cursor...])))
                break
            }
            if cursor < match.0.lowerBound {
                result.append(.text(value: String(message[cursor ..< match.0.lowerBound])))
            }
            if let replacement = replacements[match.1] { result.append(replacement) }
            cursor = match.0.upperBound
        }
        return result
    }

    private nonisolated static func isAnimatedImageURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".gif") || path.hasSuffix(".webp") || path.hasSuffix(".apng")
    }

    public nonisolated static func decodeDanmakuView(_ data: Data) throws -> FocusVideoDanmakuView {
        guard !data.isEmpty else {
            throw FocusProtobufError.invalidData
        }
        var reader = FocusProtobufReader(data: data)
        var state = 0
        var segmentDuration = Int64(360_000)
        var totalSegments = 0
        var count = Int64(0)

        while let tag = try reader.readTag() {
            switch (tag.fieldNumber, tag.wireType) {
            case (1, 0):
                state = Int(try reader.readVarint())
            case (4, 2):
                var segmentReader = FocusProtobufReader(data: try reader.readLengthDelimited())
                while let segmentTag = try segmentReader.readTag() {
                    switch (segmentTag.fieldNumber, segmentTag.wireType) {
                    case (1, 0):
                        let value = try segmentReader.readVarint()
                        if value > 0 {
                            segmentDuration = Int64(clamping: value)
                        }
                    case (2, 0):
                        totalSegments = Int(clamping: try segmentReader.readVarint())
                    default:
                        try segmentReader.skip(tag: segmentTag)
                    }
                }
            case (8, 0):
                count = Int64(clamping: try reader.readVarint())
            default:
                try reader.skip(tag: tag)
            }
        }

        return FocusVideoDanmakuView(
            state: state,
            segmentDurationMilliseconds: segmentDuration,
            totalSegments: totalSegments,
            count: count
        )
    }

    public nonisolated static func decodeDanmakuSegment(_ data: Data) throws -> FocusVideoDanmakuSegment {
        if data == Data([0x10, 0x01]) {
            return FocusVideoDanmakuSegment(danmakus: [], isClosed: true)
        }
        guard !data.isEmpty else {
            return FocusVideoDanmakuSegment(danmakus: [])
        }

        var reader = FocusProtobufReader(data: data)
        var danmakus: [FocusVideoDanmaku] = []
        while let tag = try reader.readTag() {
            if tag.fieldNumber == 1, tag.wireType == 2 {
                if let danmaku = try decodeDanmakuElement(reader.readLengthDelimited()) {
                    danmakus.append(danmaku)
                }
            } else {
                try reader.skip(tag: tag)
            }
        }
        danmakus.sort {
            if $0.progressMilliseconds != $1.progressMilliseconds {
                return $0.progressMilliseconds < $1.progressMilliseconds
            }
            if $0.weight != $1.weight {
                return $0.weight > $1.weight
            }
            return $0.id < $1.id
        }
        return FocusVideoDanmakuSegment(danmakus: danmakus)
    }

    private nonisolated static func decodeDanmakuElement(_ data: Data) throws -> FocusVideoDanmaku? {
        var reader = FocusProtobufReader(data: data)
        var id = Int64(0)
        var progress = Int64(0)
        var mode: FocusVideoDanmakuMode?
        var fontSize = 25
        var colorRGB: Int? = 0xffffff
        var content = ""
        var weight = 0
        var pool = 0

        while let tag = try reader.readTag() {
            switch (tag.fieldNumber, tag.wireType) {
            case (1, 0):
                id = Int64(clamping: try reader.readVarint())
            case (2, 0):
                progress = Int64(clamping: try reader.readVarint())
            case (3, 0):
                mode = FocusVideoDanmakuMode(rawValue: Int(try reader.readVarint()))
            case (4, 0):
                fontSize = Int(clamping: try reader.readVarint())
            case (5, 0):
                let value = Int(clamping: try reader.readVarint())
                colorRGB = value == 60_001 ? nil : value & 0xffffff
            case (7, 2):
                content = String(decoding: try reader.readLengthDelimited(), as: UTF8.self)
            case (9, 0):
                weight = Int(clamping: try reader.readVarint())
            case (11, 0):
                pool = Int(clamping: try reader.readVarint())
            default:
                try reader.skip(tag: tag)
            }
        }

        guard
            let mode,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return FocusVideoDanmaku(
            id: id,
            progressMilliseconds: progress,
            mode: mode,
            fontSize: min(max(fontSize, 12), 64),
            colorRGB: colorRGB,
            content: content,
            weight: weight,
            pool: pool
        )
    }

    public nonisolated static func decodePlaybackResponse(
        _ data: Data,
        headers: [String: String]
    ) throws -> FocusVideoPlaybackSource {
        let root = try decodeRootObject(data)
        try validateAPIResponse(root)
        guard let payload = root.dictionaryValue(at: ["data"]) else {
            throw ServiceError.invalidResponse
        }

        let quality = payload.intValue(at: ["quality"])
            .map { "清晰度 \($0)" }
            ?? "自动清晰度"

        let progressiveURLs = (payload.arrayValue(at: ["durl"]) ?? []).compactMap { rawValue -> URL? in
            guard let item = rawValue as? [String: Any] else {
                return nil
            }
            return preferredMediaURL(from: item)
        }
        if !progressiveURLs.isEmpty {
            return FocusVideoPlaybackSource(
                stream: .progressive(progressiveURLs),
                headers: headers,
                qualityDescription: quality
            )
        }

        guard let dash = payload.dictionaryValue(at: ["dash"]) else {
            throw ServiceError.noStream
        }
        let videoCandidates = (dash.arrayValue(at: ["video"]) ?? [])
            .compactMap { $0 as? [String: Any] }
        let compatibleVideos = videoCandidates.filter { $0.intValue(at: ["codecid"]) == 7 }
        let selectedVideo = (compatibleVideos.isEmpty ? videoCandidates : compatibleVideos)
            .max { lhs, rhs in
                let lhsScore = lhs.int64Value(at: ["bandwidth"]) ?? lhs.int64Value(at: ["id"]) ?? 0
                let rhsScore = rhs.int64Value(at: ["bandwidth"]) ?? rhs.int64Value(at: ["id"]) ?? 0
                return lhsScore < rhsScore
            }
        guard let selectedVideo, let videoURL = preferredMediaURL(from: selectedVideo) else {
            throw ServiceError.noStream
        }

        let selectedAudio = (dash.arrayValue(at: ["audio"]) ?? [])
            .compactMap { $0 as? [String: Any] }
            .max { lhs, rhs in
                (lhs.int64Value(at: ["bandwidth"]) ?? 0) < (rhs.int64Value(at: ["bandwidth"]) ?? 0)
            }
        let audioURL = selectedAudio.flatMap(preferredMediaURL(from:))
        return FocusVideoPlaybackSource(
            stream: .dash(videoURL: videoURL, audioURL: audioURL),
            headers: headers,
            qualityDescription: quality
        )
    }

    private func loadPlayURLResponse(
        parameters: [String: String],
        referer: String,
        cookies: [HTTPCookie]
    ) async throws -> Data {
        let query = try await signedWBIQuery(parameters: parameters, referer: referer, cookies: cookies)
        let url = URL(string: "https://api.bilibili.com/x/player/wbi/playurl?\(query)")!
        return try await loadData(for: makeRequest(url: url, referer: referer, cookies: cookies))
    }

    private func loadUnsignedPlayURLResponse(
        parameters: [String: String],
        referer: String,
        cookies: [HTTPCookie]
    ) async throws -> Data {
        var components = URLComponents(string: "https://api.bilibili.com/x/player/playurl")!
        components.queryItems = parameters.keys.sorted().map { key in
            URLQueryItem(name: key, value: parameters[key])
        }
        guard let url = components.url else {
            throw ServiceError.invalidResponse
        }
        return try await loadData(for: makeRequest(url: url, referer: referer, cookies: cookies))
    }

    private func signedWBIQuery(
        parameters: [String: String],
        referer: String,
        cookies: [HTTPCookie]
    ) async throws -> String {
        let key = try await wbiKey(referer: referer, cookies: cookies)
        var signedParameters = parameters
        signedParameters["wts"] = String(Int(Date().timeIntervalSince1970))
        let query = signedParameters.keys.sorted().map { name in
            let value = Self.encodedWBIValue(signedParameters[name] ?? "")
            return "\(name)=\(value)"
        }.joined(separator: "&")
        return "\(query)&w_rid=\(Self.md5Hex(query + key))"
    }

    private func wbiKey(referer: String, cookies: [HTTPCookie]) async throws -> String {
        if let cachedWBIKey, Date() < cachedWBIKeyExpiration {
            return cachedWBIKey
        }

        let url = URL(string: "https://api.bilibili.com/x/web-interface/nav")!
        let data = try await loadData(for: makeRequest(url: url, referer: referer, cookies: cookies))
        let root = try Self.decodeRootObject(data)
        try Self.validateAPIResponse(root)
        guard
            let imageURL = root.stringValue(at: ["data", "wbi_img", "img_url"]),
            let subtitleURL = root.stringValue(at: ["data", "wbi_img", "sub_url"])
        else {
            throw ServiceError.invalidResponse
        }

        let imageKey = imageURL.split(separator: "/").last?.split(separator: ".").first.map(String.init) ?? ""
        let subtitleKey = subtitleURL.split(separator: "/").last?.split(separator: ".").first.map(String.init) ?? ""
        let rawCharacters = Array(imageKey + subtitleKey)
        let mixed = Self.wbiMixinTable.compactMap { index in
            rawCharacters.indices.contains(index) ? rawCharacters[index] : nil
        }
        let key = String(mixed.prefix(32))
        guard key.count == 32 else {
            throw ServiceError.invalidResponse
        }

        cachedWBIKey = key
        cachedWBIKeyExpiration = Date().addingTimeInterval(30 * 60)
        return key
    }

    private func invalidateWBIKey() {
        cachedWBIKey = nil
        cachedWBIKeyExpiration = .distantPast
    }

    private func makeRequest(url: URL, referer: String, cookies: [HTTPCookie]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        return DynamicFeedService.attach(cookies: cookies, to: request)
    }

    private func loadData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await requestLoader(request)
        guard
            let response = response as? HTTPURLResponse,
            (200 ..< 300).contains(response.statusCode)
        else {
            throw ServiceError.invalidResponse
        }
        return data
    }

    private nonisolated static func mediaHeaders(cookies: [HTTPCookie], referer: String) -> [String: String] {
        var headers = [
            "User-Agent": userAgent,
            "Referer": referer,
            "Origin": "https://www.bilibili.com",
        ]
        if let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        return headers
    }

    private nonisolated static func decodeRootObject(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.invalidResponse
        }
        return root
    }

    private nonisolated static func binaryAPIError(_ data: Data) -> ServiceError? {
        let whitespace: Set<UInt8> = [0x09, 0x0a, 0x0d, 0x20]
        guard data.first(where: { !whitespace.contains($0) }) == 0x7b else {
            return nil
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let code = root.intValue(at: ["code"]),
            code != 0
        else {
            return nil
        }
        return .api(
            code: code,
            message: root.stringValue(at: ["message"]) ?? "弹幕接口失败"
        )
    }

    private nonisolated static func validateAPIResponse(_ root: [String: Any]) throws {
        let code = root.intValue(at: ["code"]) ?? -1
        guard code == 0 else {
            throw ServiceError.api(
                code: code,
                message: root.stringValue(at: ["message"]) ?? "未知错误"
            )
        }
    }

    private nonisolated static func parsePages(_ payload: [String: Any]) -> [FocusVideoPage] {
        (payload.arrayValue(at: ["pages"]) ?? []).compactMap { rawValue in
            guard
                let page = rawValue as? [String: Any],
                let cid = page.int64Value(at: ["cid"]),
                cid > 0
            else {
                return nil
            }
            let number = page.intValue(at: ["page"]) ?? 1
            return FocusVideoPage(
                pageNumber: number,
                cid: cid,
                title: page.stringValue(at: ["part"]) ?? "P\(number)",
                duration: page.int64Value(at: ["duration"]) ?? 0
            )
        }
    }

    private nonisolated static func parseEpisodeGroups(_ payload: [String: Any]) -> [FocusVideoEpisodeGroup] {
        guard let season = payload.dictionaryValue(at: ["ugc_season"]) else {
            return []
        }
        let fallbackTitle = season.stringValue(at: ["title"]) ?? "选集"
        return (season.arrayValue(at: ["sections"]) ?? []).compactMap { rawSection in
            guard let section = rawSection as? [String: Any] else {
                return nil
            }
            let episodes = (section.arrayValue(at: ["episodes"]) ?? []).compactMap { rawEpisode -> FocusVideoEpisode? in
                guard let episode = rawEpisode as? [String: Any] else {
                    return nil
                }
                let arc = episode.dictionaryValue(at: ["arc"]) ?? [:]
                guard let bvid = episode.stringValue(at: ["bvid"]) ?? arc.stringValue(at: ["bvid"]), !bvid.isEmpty else {
                    return nil
                }
                return FocusVideoEpisode(
                    bvid: bvid,
                    aid: episode.int64Value(at: ["aid"]) ?? arc.int64Value(at: ["aid"]) ?? 0,
                    cid: episode.int64Value(at: ["cid"]) ?? arc.int64Value(at: ["cid"]) ?? 0,
                    title: episode.stringValue(at: ["title"])
                        ?? episode.stringValue(at: ["long_title"])
                        ?? arc.stringValue(at: ["title"])
                        ?? bvid,
                    coverURL: normalizedURL(
                        episode.stringValue(at: ["cover"])
                            ?? arc.stringValue(at: ["pic"])
                    ),
                    badge: episode.stringValue(at: ["badge"])
                        ?? episode.stringValue(at: ["badge_info", "text"])
                        ?? ""
                )
            }
            guard !episodes.isEmpty else {
                return nil
            }
            return FocusVideoEpisodeGroup(
                title: section.stringValue(at: ["title"]) ?? fallbackTitle,
                episodes: episodes
            )
        }
    }

    private nonisolated static func preferredMediaURL(from payload: [String: Any]) -> URL? {
        var candidates: [String] = []
        if let baseURL = payload.stringValue(at: ["baseUrl"]) ?? payload.stringValue(at: ["base_url"]) ?? payload.stringValue(at: ["url"]) {
            candidates.append(baseURL)
        }
        for rawValue in payload.arrayValue(at: ["backupUrl"]) ?? payload.arrayValue(at: ["backup_url"]) ?? [] {
            if let value = rawValue as? String {
                candidates.append(value)
            }
        }

        let preferred = candidates.first(where: { value in
            let lowercased = value.lowercased()
            return !lowercased.contains("mcdn") && !lowercased.contains("szbdyd")
        }) ?? candidates.first
        return normalizedURL(preferred)
    }

    private nonisolated static func normalizedURL(_ rawValue: String?) -> URL? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("//") {
            value = "https:\(value)"
        } else if value.lowercased().hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        }
        return URL(string: value)
    }

    private nonisolated static func encodedWBIValue(_ value: String) -> String {
        let filtered = value.filter { !"!'()*".contains($0) }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/?%")
        return filtered.addingPercentEncoding(withAllowedCharacters: allowed) ?? filtered
    }

    private nonisolated static func md5Hex(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private enum FocusProtobufError: Error {
    case invalidData
    case truncated
    case invalidWireType
}

private struct FocusProtobufTag {
    let fieldNumber: Int
    let wireType: Int
}

private struct FocusProtobufReader {
    let data: Data
    private(set) var offset = 0

    mutating func readTag() throws -> FocusProtobufTag? {
        guard offset < data.count else {
            return nil
        }
        let raw = try readVarint()
        let fieldNumber = Int(raw >> 3)
        guard fieldNumber > 0 else {
            throw FocusProtobufError.invalidData
        }
        return FocusProtobufTag(
            fieldNumber: fieldNumber,
            wireType: Int(raw & 0x07)
        )
    }

    mutating func readVarint() throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while shift < 64 {
            guard offset < data.count else {
                throw FocusProtobufError.truncated
            }
            let byte = data[offset]
            offset += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                return value
            }
            shift += 7
        }
        throw FocusProtobufError.invalidData
    }

    mutating func readLengthDelimited() throws -> Data {
        let rawLength = try readVarint()
        guard rawLength <= UInt64(Int.max) else {
            throw FocusProtobufError.invalidData
        }
        let length = Int(rawLength)
        let end = offset + length
        guard end >= offset, end <= data.count else {
            throw FocusProtobufError.truncated
        }
        defer { offset = end }
        return data.subdata(in: offset ..< end)
    }

    mutating func skip(tag: FocusProtobufTag) throws {
        switch tag.wireType {
        case 0:
            _ = try readVarint()
        case 1:
            try skipBytes(8)
        case 2:
            _ = try readLengthDelimited()
        case 5:
            try skipBytes(4)
        default:
            throw FocusProtobufError.invalidWireType
        }
    }

    private mutating func skipBytes(_ count: Int) throws {
        let end = offset + count
        guard end >= offset, end <= data.count else {
            throw FocusProtobufError.truncated
        }
        offset = end
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

    func dictionaryValue(at path: [String]) -> [String: Any]? {
        value(at: path) as? [String: Any]
    }

    func arrayValue(at path: [String]) -> [Any]? {
        value(at: path) as? [Any]
    }

    func stringValue(at path: [String]) -> String? {
        if let value = value(at: path) as? String {
            return value
        }
        if let value = value(at: path) as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    func intValue(at path: [String]) -> Int? {
        if let value = value(at: path) as? NSNumber {
            return value.intValue
        }
        if let value = value(at: path) as? String {
            return Int(value)
        }
        return nil
    }

    func int64Value(at path: [String]) -> Int64? {
        if let value = value(at: path) as? NSNumber {
            return value.int64Value
        }
        if let value = value(at: path) as? String {
            return Int64(value)
        }
        return nil
    }
}
