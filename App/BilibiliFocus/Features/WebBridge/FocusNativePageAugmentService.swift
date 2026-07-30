#if canImport(UIKit)
import CryptoKit
import FocusCore
import Foundation

enum FocusNativePageKind: String {
    case video
    case opus

    func cacheKey(for url: URL) -> String {
        "\(rawValue)::\(url.absoluteString)"
    }
}

enum FocusNativePageAugmentPayload: Sendable {
    case video(FocusNativeVideoAugmentPayload)
    case opus(FocusNativeOpusAugmentPayload)

    var kind: FocusNativePageKind {
        switch self {
        case .video:
            return .video
        case .opus:
            return .opus
        }
    }

    var summary: String {
        switch self {
        case let .video(payload):
            let episodeCount = payload.groups.reduce(0) { $0 + $1.items.count }
            return "groups=\(payload.groups.count) episodes=\(episodeCount) comments=\(payload.comments.count)"
        case let .opus(payload):
            return "comments=\(payload.comments.count)"
        }
    }

    var javaScript: String {
        switch self {
        case let .video(payload):
            return payload.javaScript
        case let .opus(payload):
            return payload.javaScript
        }
    }

    var renderKey: String? {
        switch self {
        case let .video(payload):
            return payload.renderKey
        case .opus:
            return nil
        }
    }
}

struct FocusNativeVideoAugmentPayload: Encodable, Sendable {
    let title: String
    let authorName: String
    let authorAvatarURL: String
    let authorSpaceURL: String
    let authorMID: Int64
    let authorFollowers: Int64
    let authorFollowersText: String
    let authorIsFollowing: Bool
    let groups: [FocusNativeEpisodeGroupPayload]
    let comments: [FocusNativeCommentPayload]

    var renderKey: String {
        let episodeCount = groups.reduce(0) { $0 + $1.items.count }
        return "\(title)::\(authorName)::\(episodeCount)::\(comments.count)"
    }
}

struct FocusNativeOpusAugmentPayload: Encodable, Sendable {
    let comments: [FocusNativeCommentPayload]
}

struct FocusNativeEpisodeGroupPayload: Encodable, Sendable {
    let title: String
    let items: [FocusNativeEpisodeItemPayload]
}

struct FocusNativeEpisodeItemPayload: Encodable, Sendable {
    let title: String
    let subtitle: String
    let badge: String
    let targetURL: String
    let isCurrent: Bool
}

struct FocusNativeCommentPayload: Encodable, Sendable {
    let author: String
    let avatarURL: String
    let content: String
    let contentRuns: [FocusRichTextRun]
    let likeText: String
    let replyText: String
    let timeText: String
    let previewReplies: [FocusNativeCommentPayload]
}

actor FocusNativePageAugmentService {
    private typealias JSONObject = [String: Any]

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    private static let wbiMixinTable = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 52, 34, 44,
    ]

    private let cookieProvider: WebViewCookieSnapshotProvider
    private let session: URLSession
    private var cachedWbiKey: String?
    private var cachedWbiExpiration = Date.distantPast

    init(cookieProvider: WebViewCookieSnapshotProvider) {
        self.cookieProvider = cookieProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 16
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func loadPayload(for url: URL, kind: FocusNativePageKind) async -> FocusNativePageAugmentPayload? {
        switch kind {
        case .video:
            return await loadVideoPayload(for: url).map(FocusNativePageAugmentPayload.video)
        case .opus:
            return await loadOpusPayload(for: url).map(FocusNativePageAugmentPayload.opus)
        }
    }

    private func loadVideoPayload(for url: URL) async -> FocusNativeVideoAugmentPayload? {
        guard let bvid = Self.extractBvid(from: url) else {
            return nil
        }

        let referer = "https://www.bilibili.com/video/\(bvid)"
        guard
            let viewRoot = try? await requestObject(
                urlString: "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)",
                referer: referer
            ),
            viewRoot.intValue(at: "code") == 0,
            let data = viewRoot.dictionaryValue(at: "data")
        else {
            return nil
        }

        let title = data.stringValue(at: "title") ?? "视频"
        let owner = data.dictionaryValue(at: "owner") ?? [:]
        let authorName = owner.stringValue(at: "name") ?? owner.stringValue(at: "uname") ?? "UP主"
        let authorMID = owner.int64Value(at: "mid") ?? 0
        let rawAuthorAvatar = owner.stringValue(at: "face") ?? ""
        let normalizedAuthorAvatar: String
        if rawAuthorAvatar.hasPrefix("//") {
            normalizedAuthorAvatar = "https:\(rawAuthorAvatar)"
        } else if rawAuthorAvatar.lowercased().hasPrefix("http://") {
            normalizedAuthorAvatar = "https://" + rawAuthorAvatar.dropFirst("http://".count)
        } else {
            normalizedAuthorAvatar = rawAuthorAvatar
        }
        let authorAvatarURL = URL(string: normalizedAuthorAvatar)?.absoluteString ?? ""
        let authorSpaceURL = authorMID > 0 ? "https://space.bilibili.com/\(authorMID)" : ""
        let currentPageNumber = Self.extractPageNumber(from: url)
        var groups: [FocusNativeEpisodeGroupPayload] = []

        let pages = parseVideoPages(from: data, bvid: bvid, currentPageNumber: currentPageNumber)
        if !pages.isEmpty {
            groups.append(
                FocusNativeEpisodeGroupPayload(
                    title: pages.count > 1 ? "分P · 共 \(pages.count) 条" : "分P",
                    items: pages
                )
            )
        }

        groups.append(contentsOf: parseEpisodeGroups(from: data, currentBvid: bvid))

        let aid = data.int64Value(at: "aid") ?? 0
        async let commentsTask: [FocusNativeCommentPayload] = aid > 0
            ? ((try? await fetchComments(oid: String(aid), type: 1, referer: referer)) ?? [])
            : []
        async let relationTask: (following: Int64, followers: Int64) = authorMID > 0
            ? ((try? await fetchRelation(mid: authorMID)) ?? (following: 0, followers: 0))
            : (following: 0, followers: 0)
        async let followStateTask: Bool = authorMID > 0
            ? ((try? await fetchFollowState(mid: authorMID, referer: authorSpaceURL.isEmpty ? referer : authorSpaceURL)) ?? false)
            : false

        let comments = await commentsTask
        let relation = await relationTask
        let isFollowing = await followStateTask

        let meaningfulGroups = groups.filter { $0.items.count > 1 }
        let hasMeaningfulMeta = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !authorAvatarURL.isEmpty
            || !authorSpaceURL.isEmpty

        if meaningfulGroups.isEmpty, comments.isEmpty, !hasMeaningfulMeta {
            return nil
        }

        return FocusNativeVideoAugmentPayload(
            title: title,
            authorName: authorName,
            authorAvatarURL: authorAvatarURL,
            authorSpaceURL: authorSpaceURL,
            authorMID: authorMID,
            authorFollowers: relation.followers,
            authorFollowersText: Self.formatCount(relation.followers),
            authorIsFollowing: isFollowing,
            groups: meaningfulGroups,
            comments: comments
        )
    }

    private func loadOpusPayload(for url: URL) async -> FocusNativeOpusAugmentPayload? {
        guard let opusID = Self.extractOpusID(from: url) else {
            return nil
        }

        let features = "onlyfansVote,onlyfansAssetsV2,decorationCard,htmlNewStyle,ugcDelete,editable,opusPrivateVisible"
        let detailURL = "https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail?id=\(opusID)&timezone_offset=-480&features=\(features)"

        guard
            let detailRoot = try? await requestObject(urlString: detailURL, referer: url.absoluteString),
            detailRoot.intValue(at: "code") == 0
        else {
            return nil
        }

        let item = detailRoot.dictionaryValue(at: "data", "item")
        let basic = item?.dictionaryValue(at: "basic")
        let commentIdString = basic?.stringValue(at: "comment_id_str")
        let ridString = basic?.stringValue(at: "rid_str")
        let directCommentID = basic?.int64Value(at: "comment_id")
        let commentIDFromString = commentIdString.flatMap(Int64.init)
        let commentIDFromRid = ridString.flatMap(Int64.init)
        let commentIDFromOpus = Int64(opusID)
        let commentId: Int64
        if let directCommentID {
            commentId = directCommentID
        } else if let commentIDFromString {
            commentId = commentIDFromString
        } else if let commentIDFromRid {
            commentId = commentIDFromRid
        } else if let commentIDFromOpus {
            commentId = commentIDFromOpus
        } else {
            commentId = 0
        }
        let fallbackID = commentIdString ?? ridString ?? opusID

        let candidates = [commentId > 0 ? String(commentId) : nil, fallbackID]
            .compactMap { $0 }
            .reduce(into: [String]()) { partialResult, value in
                if !partialResult.contains(value) {
                    partialResult.append(value)
                }
            }

        for oid in candidates {
            for type in [17, 11, 12] {
                let comments = (try? await fetchComments(oid: oid, type: type, referer: url.absoluteString)) ?? []
                if !comments.isEmpty {
                    return FocusNativeOpusAugmentPayload(comments: comments)
                }
            }
        }

        return nil
    }

    private func parseVideoPages(from data: JSONObject, bvid: String, currentPageNumber: Int?) -> [FocusNativeEpisodeItemPayload] {
        guard let pages = data.arrayValue(at: "pages") else {
            return []
        }

        return pages.compactMap { page in
            let pageNumber = page.intValue(at: "page") ?? 1
            let title = page.stringValue(at: "part")?.nilIfBlank ?? "P\(pageNumber)"
            let duration = Self.formatDuration(page.int64Value(at: "duration") ?? 0)
            return FocusNativeEpisodeItemPayload(
                title: title,
                subtitle: "P\(pageNumber)",
                badge: duration,
                targetURL: "https://www.bilibili.com/video/\(bvid)/?p=\(pageNumber)",
                isCurrent: currentPageNumber == pageNumber
            )
        }
    }

    private func parseEpisodeGroups(from data: JSONObject, currentBvid: String) -> [FocusNativeEpisodeGroupPayload] {
        guard let ugcSeason = data.dictionaryValue(at: "ugc_season") else {
            return []
        }

        let seasonTitle = ugcSeason.stringValue(at: "title")?.nilIfBlank ?? "选集"
        let sections = ugcSeason.arrayValue(at: "sections") ?? []

        return sections.compactMap { section in
            let groupTitle = section.stringValue(at: "title")?.nilIfBlank ?? seasonTitle
            let episodes = (section.arrayValue(at: "episodes") ?? []).compactMap { episode -> FocusNativeEpisodeItemPayload? in
                guard let bvid = episode.stringValue(at: "bvid")?.nilIfBlank else {
                    return nil
                }

                let arc = episode.dictionaryValue(at: "arc")
                let rawTitle = episode.stringValue(at: "title")
                    ?? episode.stringValue(at: "long_title")
                    ?? arc?.stringValue(at: "title")
                let badge = episode.stringValue(at: "badge")
                    ?? episode.dictionaryValue(at: "badge_info")?.stringValue(at: "text")
                    ?? ""

                return FocusNativeEpisodeItemPayload(
                    title: rawTitle?.nilIfBlank ?? "视频",
                    subtitle: bvid,
                    badge: badge,
                    targetURL: "https://www.bilibili.com/video/\(bvid)/",
                    isCurrent: bvid.caseInsensitiveCompare(currentBvid) == .orderedSame
                )
            }

            guard !episodes.isEmpty else {
                return nil
            }

            return FocusNativeEpisodeGroupPayload(title: groupTitle, items: episodes)
        }
    }

    private func fetchFollowState(mid: Int64, referer: String) async throws -> Bool {
        let query = try await signedWbiQuery(
            parameters: [
                "mid": String(mid)
            ],
            referer: referer
        )
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/space/wbi/acc/relation?\(query)",
            referer: referer
        )
        let code = root.intValue(at: "code") ?? 0
        guard code == 0 else {
            throw URLError(.badServerResponse)
        }

        let data = root.dictionaryValue(at: "data") ?? root
        let relation = data.dictionaryValue(at: "be_relation")
            ?? data.dictionaryValue(at: "relation")
            ?? data

        if let explicitFollow = relation.boolValue(at: "is_follow") ?? data.boolValue(at: "is_follow") {
            return explicitFollow
        }

        let attribute = relation.intValue(at: "attribute")
            ?? data.intValue(at: "attribute")
            ?? 0
        return (attribute & 2) != 0
    }

    private func fetchRelation(mid: Int64) async throws -> (following: Int64, followers: Int64) {
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/relation/stat?vmid=\(mid)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        let data = root.dictionaryValue(at: "data") ?? root
        return (
            following: data.int64Value(at: "following") ?? 0,
            followers: data.int64Value(at: "follower") ?? 0
        )
    }

    func updateFollowState(mid: Int64, shouldFollow: Bool) async throws -> (isFollowing: Bool, followers: Int64) {
        try await modifyRelation(mid: mid, shouldFollow: shouldFollow)
        async let followStateTask = fetchFollowState(mid: mid, referer: "https://space.bilibili.com/\(mid)")
        async let relationTask = fetchRelation(mid: mid)
        let isFollowing = try await followStateTask
        let relation = try await relationTask
        return (isFollowing: isFollowing, followers: relation.followers)
    }

    private func modifyRelation(mid: Int64, shouldFollow: Bool) async throws {
        let cookies = await cookieProvider.loadCookies()
        guard let csrf = cookies.first(where: { $0.name == "bili_jct" })?.value.nilIfBlank else {
            throw URLError(.userAuthenticationRequired)
        }

        guard let url = URL(string: "https://api.bilibili.com/x/relation/modify") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://space.bilibili.com/\(mid)", forHTTPHeaderField: "Referer")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request = CookieRequestPolicy.attach(cookies: cookies, to: request)

        let bodyItems = [
            URLQueryItem(name: "fid", value: String(mid)),
            URLQueryItem(name: "act", value: shouldFollow ? "1" : "2"),
            URLQueryItem(name: "re_src", value: "11"),
            URLQueryItem(name: "csrf", value: csrf),
            URLQueryItem(name: "csrf_token", value: csrf)
        ]
        var components = URLComponents()
        components.queryItems = bodyItems
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let response = try await requestObject(for: request)
        guard response.intValue(at: "code") == 0 else {
            throw URLError(.badServerResponse)
        }
    }

    private func fetchComments(oid: String, type: Int, referer: String) async throws -> [FocusNativeCommentPayload] {
        let query = try await signedWbiQuery(
            parameters: [
                "type": String(type),
                "oid": oid,
                "pn": "1",
                "ps": "20",
                "sort": "2",
            ],
            referer: referer
        )
        let urlString = "https://api.bilibili.com/x/v2/reply/wbi/main?\(query)"
        let root = try await requestObject(urlString: urlString, referer: referer)
        guard root.intValue(at: "code") == 0 else {
            return []
        }

        let replies = root.arrayValue(at: "data", "replies") ?? []
        return replies.compactMap(parseComment(from:))
    }

    private func parseComment(from object: JSONObject) -> FocusNativeCommentPayload? {
        guard
            let member = object.dictionaryValue(at: "member"),
            let content = object.dictionaryValue(at: "content"),
            let message = content.stringValue(at: "message")?.nilIfBlank
        else {
            return nil
        }

        let likeCount = object.int64Value(at: "like") ?? 0
        let replyCount = object.int64Value(at: "rcount") ?? 0
        let publishTime = object.int64Value(at: "ctime") ?? 0

        return FocusNativeCommentPayload(
            author: member.stringValue(at: "uname")?.nilIfBlank ?? "用户",
            avatarURL: member.stringValue(at: "avatar") ?? "",
            content: message,
            contentRuns: Self.parseCommentRuns(content: content, message: message),
            likeText: likeCount > 0 ? "\(Self.formatCount(likeCount))赞" : "",
            replyText: replyCount > 0 ? "\(Self.formatCount(replyCount))回复" : "",
            timeText: Self.formatCommentTime(publishTime),
            previewReplies: (object.arrayValue(at: "replies") ?? []).compactMap(parseComment(from:))
        )
    }

    private static func parseCommentRuns(content: JSONObject, message: String) -> [FocusRichTextRun] {
        if let nodes = content.arrayValue(at: "rich_text_nodes") {
            let parsed = nodes.compactMap { node -> FocusRichTextRun? in
                let text = node.stringValue(at: "text") ?? node.stringValue(at: "orig_text") ?? ""
                let rawEmoji = node.stringValue(at: "emoji", "icon_url")
                    ?? node.stringValue(at: "emoji", "url")
                    ?? node.stringValue(at: "rich", "emoji", "icon_url")
                    ?? node.stringValue(at: "icon_url")
                if let rawEmoji,
                   let normalized = Self.normalizedCommentURLString(rawEmoji),
                   let url = URL(string: normalized)
                {
                    let path = url.path.lowercased()
                    let size = node.intValue(at: "emoji", "meta", "size")
                        ?? node.intValue(at: "rich", "emoji", "meta", "size")
                        ?? 0
                    return .emote(
                        alt: text.isEmpty ? "[表情]" : text,
                        url: url,
                        width: node.intValue(at: "emoji", "width") ?? node.intValue(at: "rich", "emoji", "width") ?? size,
                        height: node.intValue(at: "emoji", "height") ?? node.intValue(at: "rich", "emoji", "height") ?? size,
                        animated: path.hasSuffix(".gif") || path.hasSuffix(".webp") || path.hasSuffix(".apng")
                    )
                }
                guard !text.isEmpty else { return nil }
                return .text(
                    value: text,
                    linkURL: Self.normalizedCommentURLString(node.stringValue(at: "jump_url") ?? node.stringValue(at: "link")).flatMap(URL.init(string:))
                )
            }
            if !parsed.isEmpty { return parsed }
        }

        var replacements: [String: FocusRichTextRun] = [:]
        content.dictionaryValue(at: "emote")?.forEach { token, rawValue in
            guard
                let emote = rawValue as? JSONObject,
                let rawURL = emote.stringValue(at: "gif_url") ?? emote.stringValue(at: "url") ?? emote.stringValue(at: "icon_url"),
                let normalized = Self.normalizedCommentURLString(rawURL),
                let url = URL(string: normalized)
            else { return }
            let path = url.path.lowercased()
            replacements[token] = .emote(
                alt: emote.stringValue(at: "text") ?? token,
                url: url,
                width: emote.intValue(at: "meta", "size") ?? 0,
                height: emote.intValue(at: "meta", "size") ?? 0,
                animated: path.hasSuffix(".gif") || path.hasSuffix(".webp") || path.hasSuffix(".apng")
            )
        }
        content.dictionaryValue(at: "jump_url")?.forEach { token, rawValue in
            guard replacements[token] == nil else { return }
            let rawURL = (rawValue as? String)
                ?? (rawValue as? JSONObject)?.stringValue(at: "url")
                ?? (rawValue as? JSONObject)?.stringValue(at: "jump_url")
            if let normalized = Self.normalizedCommentURLString(rawURL), let url = URL(string: normalized) {
                replacements[token] = .text(value: token, linkURL: url)
            }
        }
        guard !replacements.isEmpty else { return [.text(value: message)] }
        let tokens = replacements.keys.sorted { $0.count > $1.count }
        var result: [FocusRichTextRun] = []
        var cursor = message.startIndex
        while cursor < message.endIndex {
            let matches = tokens.compactMap { token in
                message.range(of: token, range: cursor ..< message.endIndex).map { ($0, token) }
            }
            guard let match = matches.min(by: { lhs, rhs in
                lhs.0.lowerBound == rhs.0.lowerBound ? lhs.1.count > rhs.1.count : lhs.0.lowerBound < rhs.0.lowerBound
            }) else {
                result.append(.text(value: String(message[cursor...])))
                break
            }
            if cursor < match.0.lowerBound { result.append(.text(value: String(message[cursor ..< match.0.lowerBound]))) }
            if let replacement = replacements[match.1] { result.append(replacement) }
            cursor = match.0.upperBound
        }
        return result
    }

    private static func normalizedCommentURLString(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("//") { value = "https:\(value)" }
        else if value.lowercased().hasPrefix("http://") { value = "https://" + value.dropFirst("http://".count) }
        else if value.hasPrefix("/") { value = "https://www.bilibili.com\(value)" }
        return value
    }

    private func requestObject(urlString: String, referer: String?) async throws -> JSONObject {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let data = try await requestData(url: url, referer: referer)
        let rawObject = try JSONSerialization.jsonObject(with: data)
        guard let object = rawObject as? JSONObject else {
            throw URLError(.cannotParseResponse)
        }
        return object
    }

    private func requestObject(for request: URLRequest) async throws -> JSONObject {
        let data = try await requestData(for: request)
        let rawObject = try JSONSerialization.jsonObject(with: data)
        guard let object = rawObject as? JSONObject else {
            throw URLError(.cannotParseResponse)
        }
        return object
    }

    private func requestData(url: URL, referer: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(referer ?? "https://www.bilibili.com/", forHTTPHeaderField: "Referer")

        let cookies = await cookieProvider.loadCookies()
        request = CookieRequestPolicy.attach(cookies: cookies, to: request)

        return try await requestData(for: request)
    }

    private func requestData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func signedWbiQuery(parameters: [String: String], referer: String) async throws -> String {
        let key = try await fetchWbiKey(referer: referer)
        var items = parameters
        items["wts"] = String(Int(Date().timeIntervalSince1970))
        let query = items.keys.sorted().map { key in
            "\(key)=\(items[key] ?? "")"
        }.joined(separator: "&")
        let wrid = Self.md5Hex(query + key)
        return "\(query)&w_rid=\(wrid)"
    }

    private func fetchWbiKey(referer: String) async throws -> String {
        let now = Date()
        if let cachedWbiKey, now < cachedWbiExpiration {
            return cachedWbiKey
        }

        let nav = try await requestObject(
            urlString: "https://api.bilibili.com/x/web-interface/nav",
            referer: referer
        )
        guard
            let imgURL = nav.stringValue(at: "data", "wbi_img", "img_url"),
            let subURL = nav.stringValue(at: "data", "wbi_img", "sub_url")
        else {
            throw URLError(.cannotParseResponse)
        }

        let imgKey = imgURL.substringAfterLast("/").substringBefore(".")
        let subKey = subURL.substringAfterLast("/").substringBefore(".")
        let raw = imgKey + subKey
        let mixed = Self.wbiMixinTable.reduce(into: "") { partialResult, index in
            guard index < raw.count else {
                return
            }
            partialResult.append(raw[raw.index(raw.startIndex, offsetBy: index)])
        }

        let resolved = String(mixed.prefix(32))
        cachedWbiKey = resolved
        cachedWbiExpiration = now.addingTimeInterval(25 * 60)
        return resolved
    }

    private static func extractBvid(from url: URL) -> String? {
        let components = url.path.split(separator: "/")
        guard
            let videoIndex = components.firstIndex(of: "video"),
            components.indices.contains(components.index(after: videoIndex))
        else {
            return nil
        }

        let candidate = String(components[components.index(after: videoIndex)])
        return candidate.nilIfBlank
    }

    private static func extractOpusID(from url: URL) -> String? {
        let host = url.host?.lowercased()
        let components = url.path.split(separator: "/")

        if (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com"),
           let opusIndex = components.firstIndex(of: "opus"),
           components.indices.contains(components.index(after: opusIndex))
        {
            return String(components[components.index(after: opusIndex)]).nilIfBlank
        }

        if host == "t.bilibili.com", let first = components.first {
            let candidate = String(first)
            return candidate.allSatisfy(\.isNumber) ? candidate : nil
        }

        return nil
    }

    private static func extractPageNumber(from url: URL) -> Int? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        return components.queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("p") == .orderedSame })?
            .value
            .flatMap(Int.init)
    }

    private static func formatDuration(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return ""
        }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%lld:%02lld:%02lld", hours, minutes, remainingSeconds)
        }

        return String(format: "%02lld:%02lld", minutes, remainingSeconds)
    }

    private static func formatCount(_ value: Int64) -> String {
        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }

    private static func formatCommentTime(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return ""
        }

        let now = Int64(Date().timeIntervalSince1970)
        let delta = max(now - seconds, 0)

        switch delta {
        case 0 ..< 60:
            return "刚刚"
        case 60 ..< 3600:
            return "\(max(delta / 60, 1))分钟前"
        case 3600 ..< 86_400:
            return "\(max(delta / 3600, 1))小时前"
        case 86_400 ..< 604_800:
            return "\(max(delta / 86_400, 1))天前"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        }
    }

    private static func md5Hex(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private let focusNativeVideoAugmentComponentVersion = "2026-07-10-video-layout-stability"

let focusNativeVideoAugmentMountHelpersJavaScript = #"""
              const ensureNativeVideoAugmentHelpers = () => {
                const existingHelpers = window.__FOCUS_NATIVE_VIDEO_AUGMENT_HELPERS__;
                if (existingHelpers) {
                  return existingHelpers;
                }

                const resolveMountHost = () => {
                  const playerContainer = document.querySelector('.left-container.scroll-sticky, .left-container');
                  if (playerContainer instanceof HTMLElement) {
                    return playerContainer;
                  }

                  const main = document.querySelector('main');
                  if (main instanceof HTMLElement) {
                    return main;
                  }

                  return document.body || document.documentElement;
                };

                const attachRoot = (root) => {
                  if (!(root instanceof HTMLElement)) {
                    return false;
                  }

                  const host = resolveMountHost();
                  if (!host) {
                    return false;
                  }

                  if (root.parentNode !== host) {
                    host.appendChild(root);
                  }

                  return true;
                };

                const repairRoot = () => {
                  const liveRoot = document.getElementById('focus-native-video-augment') || window.__FOCUS_NATIVE_VIDEO_AUGMENT_ROOT__;
                  if (!(liveRoot instanceof HTMLElement)) {
                    return false;
                  }
                  return attachRoot(liveRoot);
                };

                const disconnectObserver = () => {
                  const observer = window.__FOCUS_NATIVE_VIDEO_AUGMENT_OBSERVER__;
                  if (observer) {
                    try {
                      observer.disconnect();
                    } catch (_) {}
                  }
                  window.__FOCUS_NATIVE_VIDEO_AUGMENT_OBSERVER__ = null;
                  if (window.__FOCUS_NATIVE_VIDEO_SUPPRESSION_FRAME__) {
                    cancelAnimationFrame(window.__FOCUS_NATIVE_VIDEO_SUPPRESSION_FRAME__);
                  }
                  window.__FOCUS_NATIVE_VIDEO_SUPPRESSION_FRAME__ = null;
                };

                const scheduleOriginalSectionSuppression = () => {
                  if (window.__FOCUS_NATIVE_VIDEO_SUPPRESSION_FRAME__) {
                    return;
                  }

                  window.__FOCUS_NATIVE_VIDEO_SUPPRESSION_FRAME__ = requestAnimationFrame(() => {
                    window.__FOCUS_NATIVE_VIDEO_SUPPRESSION_FRAME__ = null;
                    try {
                      window.__FOCUS_ENFORCE_NATIVE_VIDEO_ORIGINAL_SUPPRESSION__?.();
                    } catch (_) {}
                  });
                };

                const installObserver = (root) => {
                  if (root instanceof HTMLElement) {
                    window.__FOCUS_NATIVE_VIDEO_AUGMENT_ROOT__ = root;
                  }

                  window.__FOCUS_REPAIR_NATIVE_VIDEO_AUGMENT__ = repairRoot;
                  disconnectObserver();

                  const observer = new MutationObserver(() => {
                    const liveRoot = document.getElementById('focus-native-video-augment') || window.__FOCUS_NATIVE_VIDEO_AUGMENT_ROOT__;
                    if (!(liveRoot instanceof HTMLElement)) {
                      return;
                    }

                    const host = resolveMountHost();
                    if (liveRoot.parentNode !== host) {
                      repairRoot();
                    }
                    scheduleOriginalSectionSuppression();
                  });

                  observer.observe(document.documentElement, { childList: true, subtree: true });
                  window.__FOCUS_NATIVE_VIDEO_AUGMENT_OBSERVER__ = observer;
                  scheduleOriginalSectionSuppression();
                };

                const teardown = () => {
                  disconnectObserver();
                  window.__FOCUS_NATIVE_VIDEO_AUGMENT_ROOT__ = null;
                  window.__FOCUS_REPAIR_NATIVE_VIDEO_AUGMENT__ = null;
                  window.__FOCUS_ENFORCE_NATIVE_VIDEO_ORIGINAL_SUPPRESSION__ = null;
                };

                const helpers = {
                  resolveMountHost,
                  attachRoot,
                  repairRoot,
                  installObserver,
                  teardown
                };
                window.__FOCUS_NATIVE_VIDEO_AUGMENT_HELPERS__ = helpers;
                return helpers;
              };

              const nativeVideoAugmentHelpers = ensureNativeVideoAugmentHelpers();
              const mountNativeVideoAugmentRoot = (root) => {
                if (!(root instanceof HTMLElement)) {
                  return false;
                }
                nativeVideoAugmentHelpers.attachRoot(root);
                nativeVideoAugmentHelpers.installObserver(root);
                return true;
              };
"""#

private extension FocusNativeVideoAugmentPayload {
    var javaScript: String {
        let payloadJSON = focusJSONString
        let componentVersion = focusNativeVideoAugmentComponentVersion
        return #"""
        (() => {
          const payload = \#(payloadJSON);
          const styleId = 'focus-native-video-augment-style';
          const rootId = 'focus-native-video-augment';
          const componentVersion = '\#(componentVersion)';
          \#(focusNativeVideoAugmentMountHelpersJavaScript)
          const hasRenderableContent = !!payload && (
            !!payload.authorName
            || !!payload.authorAvatarURL
            || !!payload.authorSpaceURL
            || (!!payload.groups && payload.groups.length > 0)
            || (!!payload.comments && payload.comments.length > 0)
          );
          if (!hasRenderableContent) {
            document.getElementById(rootId)?.remove?.();
            if (window.__FOCUS_NATIVE_VIDEO_AUGMENT_HELPERS__?.teardown) {
              try {
                window.__FOCUS_NATIVE_VIDEO_AUGMENT_HELPERS__.teardown();
              } catch (_) {}
            }
            return;
          }

          const checkExistingComponent = (existing) => {
            if (!existing) return false;
            if (existing.getAttribute('data-focus-version') !== componentVersion) {
              return false;
            }
            const rect = existing.getBoundingClientRect();
            const hasContent = existing.children.length > 0;
            const isVisible = rect.height > 50;
            const groupsReady = !payload.groups || payload.groups.length === 0 || !!existing.querySelector('.focus-native-episode-card');
            const commentsReady = !payload.comments || payload.comments.length === 0 || !!existing.querySelector('.focus-native-comment-card');

            return hasContent && isVisible && groupsReady && commentsReady;
          };

          const escapeHTML = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#39;'
          })[char] || char);
          const nl2br = (value) => escapeHTML(value).replace(/\n/g, '<br>');
          const safeURL = (value) => {
            try {
              const url = new URL(String(value || ''), location.href);
              return (url.protocol === 'https:' || url.protocol === 'http:') ? url.href : '';
            } catch (_) {
              return '';
            }
          };
          const renderRuns = (comment) => {
            const runs = Array.isArray(comment?.contentRuns) ? comment.contentRuns : [];
            if (runs.length === 0) return nl2br(comment?.content || '');
            return runs.map((run) => {
              if (run?.text) {
                const node = run.text;
                const decorations = [node.underline ? 'underline' : '', node.strikethrough ? 'line-through' : ''].filter(Boolean).join(' ');
                const color = /^#[0-9a-f]{3,8}$/i.test(node.color || '') ? node.color : '';
                const style = [node.bold ? 'font-weight:700' : '', node.italic ? 'font-style:italic' : '', decorations ? `text-decoration:${decorations}` : '', color ? `color:${color}` : ''].filter(Boolean).join(';');
                const value = `<span${style ? ` style="${style}"` : ''}>${nl2br(node.value || '')}</span>`;
                const href = safeURL(node.linkURL);
                return href ? `<a class="focus-native-rich-link" href="${escapeHTML(href)}">${value}</a>` : value;
              }
              if (run?.emote) {
                const node = run.emote;
                const src = safeURL(node.url);
                return src ? `<img class="focus-native-rich-emote" src="${escapeHTML(src)}" alt="${escapeHTML(node.alt || '[表情]')}" loading="lazy">` : escapeHTML(node.alt || '[表情]');
              }
              if (run?.resource) {
                const node = run.resource;
                const href = safeURL(node.url);
                return href ? `<a class="focus-native-rich-link" href="${escapeHTML(href)}">${escapeHTML(node.label || '查看内容')}</a>` : escapeHTML(node.label || '查看内容');
              }
              return '';
            }).join('');
          };
          const renderReplies = (comment) => (comment.previewReplies || []).slice(0, 2).map((reply) => `
            <div class="focus-native-preview-reply"><span class="focus-native-preview-author">${escapeHTML(reply.author)}：</span>${renderRuns(reply)}</div>
          `).join('');
          const ensureStyle = () => {
            let style = document.getElementById(styleId);
            if (!style) {
              style = document.createElement('style');
              style.id = styleId;
              document.head.appendChild(style);
            }
            style.removeAttribute('data-focus-placeholder');
            style.textContent = `
              #${rootId} {
                display: block !important;
                width: 100% !important;
                box-sizing: border-box !important;
                padding: 8px 16px 24px !important;
                position: relative !important;
                z-index: 3 !important;
                order: 2 !important;
                flex: 0 0 auto !important;
              }
              #${rootId} .focus-native-section {
                margin-top: 8px !important;
                padding: 16px !important;
                border-radius: 20px !important;
                background: rgba(248, 250, 252, 0.96) !important;
                border: 1px solid rgba(15, 23, 42, 0.06) !important;
                box-shadow: 0 14px 32px rgba(15, 23, 42, 0.05) !important;
                box-sizing: border-box !important;
              }
              #${rootId} .focus-native-section:first-child {
                margin-top: 0 !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-section {
                background: rgba(17, 24, 39, 0.96) !important;
                border-color: rgba(255, 255, 255, 0.08) !important;
                box-shadow: 0 12px 24px rgba(0, 0, 0, 0.22) !important;
              }
              html.focus-native-video-ready .right-container,
              body.focus-native-video-ready .right-container,
              html.focus-native-video-ready .right-container-inner,
              body.focus-native-video-ready .right-container-inner,
              html.focus-native-video-ready .side-toolbar,
              body.focus-native-video-ready .side-toolbar,
              html.focus-native-video-ready .right-entry,
              body.focus-native-video-ready .right-entry,
              html.focus-native-video-ready #viewbox_report,
              body.focus-native-video-ready #viewbox_report,
              html.focus-native-video-ready .video-pod,
              body.focus-native-video-ready .video-pod,
              html.focus-native-video-ready .video-pod__head,
              body.focus-native-video-ready .video-pod__head,
              html.focus-native-video-ready .video-pod__header,
              body.focus-native-video-ready .video-pod__header,
              html.focus-native-video-ready .video-pod__body,
              body.focus-native-video-ready .video-pod__body,
              html.focus-native-video-ready .video-pod__list,
              body.focus-native-video-ready .video-pod__list,
              html.focus-native-video-ready .multi-page,
              body.focus-native-video-ready .multi-page,
              html.focus-native-video-ready [class*="multi-page"],
              body.focus-native-video-ready [class*="multi-page"],
              html.focus-native-video-ready [class*="episode-list"],
              body.focus-native-video-ready [class*="episode-list"],
              html.focus-native-video-ready [class*="part-list"],
              body.focus-native-video-ready [class*="part-list"],
              html.focus-native-video-ready [class*="page-list"],
              body.focus-native-video-ready [class*="page-list"],
              html.focus-native-video-ready #commentapp,
              body.focus-native-video-ready #commentapp,
              html.focus-native-video-ready #commentapp > *,
              body.focus-native-video-ready #commentapp > *,
              html.focus-native-video-ready bili-comments,
              body.focus-native-video-ready bili-comments,
              html.focus-native-video-ready .comment-container,
              body.focus-native-video-ready .comment-container,
              html.focus-native-video-ready .bb-comment,
              body.focus-native-video-ready .bb-comment,
              html.focus-native-video-ready .comment-container,
              body.focus-native-video-ready .comment-container,
              html.focus-native-video-ready .bb-comment,
              body.focus-native-video-ready .bb-comment {
                display: none !important;
                visibility: hidden !important;
                opacity: 0 !important;
                pointer-events: none !important;
              }
              #${rootId} .focus-native-video-meta {
                display: flex !important;
                align-items: center !important;
                justify-content: space-between !important;
                gap: 12px !important;
                min-width: 0 !important;
              }
              #${rootId} .focus-native-owner {
                display: flex !important;
                align-items: center !important;
                gap: 10px !important;
                text-decoration: none !important;
                color: inherit !important;
                min-width: 0 !important;
                flex: 1 1 auto !important;
              }
              #${rootId} .focus-native-owner-copy {
                min-width: 0 !important;
                flex: 1 1 auto !important;
              }
              #${rootId} .focus-native-owner-avatar {
                width: 40px !important;
                height: 40px !important;
                border-radius: 999px !important;
                overflow: hidden !important;
                background: rgba(148, 163, 184, 0.16) !important;
                flex: 0 0 40px !important;
              }
              #${rootId} .focus-native-owner-avatar img {
                width: 100% !important;
                height: 100% !important;
                object-fit: cover !important;
                display: block !important;
              }
              #${rootId} .focus-native-owner-name {
                font-size: 15px !important;
                font-weight: 700 !important;
                line-height: 1.25 !important;
                color: #111827 !important;
                overflow: hidden !important;
                text-overflow: ellipsis !important;
                white-space: nowrap !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-owner-name {
                color: #f8fafc !important;
              }
              #${rootId} .focus-native-owner-side {
                display: flex !important;
                flex-direction: column !important;
                align-items: flex-end !important;
                justify-content: center !important;
                gap: 4px !important;
                flex: 0 0 auto !important;
              }
              #${rootId} .focus-native-owner-followers {
                font-size: 12px !important;
                font-weight: 600 !important;
                line-height: 1.2 !important;
                color: rgba(100, 116, 139, 0.92) !important;
                white-space: nowrap !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-owner-followers {
                color: rgba(226, 232, 240, 0.72) !important;
              }
              #${rootId} .focus-native-header {
                display: flex !important;
                align-items: center !important;
                justify-content: space-between !important;
                gap: 12px !important;
                margin-bottom: 12px !important;
              }
              #${rootId} .focus-native-title {
                font-size: 17px !important;
                font-weight: 700 !important;
                line-height: 1.3 !important;
                color: #111827 !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-title {
                color: #f8fafc !important;
              }
              #${rootId} .focus-native-scroller {
                display: flex !important;
                gap: 10px !important;
                overflow-x: auto !important;
                overflow-y: hidden !important;
                padding: 2px 0 2px !important;
                scroll-snap-type: x proximity !important;
                -webkit-overflow-scrolling: touch !important;
              }
              #${rootId} .focus-native-scroller::-webkit-scrollbar {
                display: none !important;
              }
              #${rootId} .focus-native-episode-card {
                flex: 0 0 168px !important;
                min-height: 84px !important;
                padding: 11px 12px !important;
                border-radius: 16px !important;
                background: rgba(248, 250, 252, 0.98) !important;
                border: 1px solid rgba(15, 23, 42, 0.06) !important;
                box-sizing: border-box !important;
                text-decoration: none !important;
                color: inherit !important;
                scroll-snap-align: start !important;
                display: flex !important;
                flex-direction: column !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-episode-card {
                background: rgba(30, 41, 59, 0.94) !important;
                border-color: rgba(255, 255, 255, 0.06) !important;
              }
              #${rootId} .focus-native-episode-card.is-current {
                border-color: rgba(251, 114, 153, 0.98) !important;
                border-width: 2px !important;
                box-shadow: inset 0 0 0 1px rgba(251, 114, 153, 0.42) !important;
              }
              #${rootId} .focus-native-episode-card.is-compact {
                min-height: 74px !important;
                justify-content: center !important;
              }
              #${rootId} .focus-native-episode-subtitle {
                font-size: 12px !important;
                font-weight: 700 !important;
                line-height: 1.2 !important;
                color: #fb7299 !important;
                margin-bottom: 8px !important;
              }
              #${rootId} .focus-native-episode-text {
                font-size: 14px !important;
                font-weight: 600 !important;
                line-height: 1.42 !important;
                color: #0f172a !important;
                display: -webkit-box !important;
                -webkit-line-clamp: 2 !important;
                -webkit-box-orient: vertical !important;
                overflow: hidden !important;
                word-break: break-word !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-episode-text {
                color: #f8fafc !important;
              }
              #${rootId} .focus-native-episode-badge {
                margin-top: 8px !important;
                font-size: 12px !important;
                line-height: 1.2 !important;
                color: rgba(100, 116, 139, 0.92) !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-episode-badge {
                color: rgba(226, 232, 240, 0.72) !important;
              }
              #${rootId} .focus-native-comment-list {
                display: grid !important;
                gap: 12px !important;
              }
              #${rootId} .focus-native-comment-card {
                display: flex !important;
                gap: 12px !important;
                padding: 14px !important;
                border-radius: 16px !important;
                background: rgba(248, 250, 252, 0.94) !important;
                border: 1px solid rgba(15, 23, 42, 0.05) !important;
                box-sizing: border-box !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-comment-card {
                background: rgba(30, 41, 59, 0.9) !important;
                border-color: rgba(255, 255, 255, 0.06) !important;
              }
              #${rootId} .focus-native-avatar {
                flex: 0 0 38px !important;
                width: 38px !important;
                height: 38px !important;
                border-radius: 999px !important;
                overflow: hidden !important;
                background: rgba(148, 163, 184, 0.16) !important;
              }
              #${rootId} .focus-native-avatar img {
                display: block !important;
                width: 100% !important;
                height: 100% !important;
                object-fit: cover !important;
              }
              #${rootId} .focus-native-comment-main {
                min-width: 0 !important;
                flex: 1 1 auto !important;
              }
              #${rootId} .focus-native-comment-author {
                font-size: 14px !important;
                font-weight: 700 !important;
                line-height: 1.25 !important;
                color: #fb7299 !important;
                margin-bottom: 6px !important;
              }
              #${rootId} .focus-native-comment-content {
                font-size: 15px !important;
                line-height: 1.6 !important;
                color: #0f172a !important;
                word-break: break-word !important;
              }
              #${rootId} .focus-native-rich-emote {
                display: inline-block !important;
                width: 1.35em !important;
                height: 1.35em !important;
                object-fit: contain !important;
                vertical-align: -0.24em !important;
                margin: 0 1px !important;
              }
              #${rootId} .focus-native-rich-link,
              #${rootId} .focus-native-preview-author {
                color: #fb7299 !important;
                text-decoration: none !important;
              }
              #${rootId} .focus-native-preview-reply {
                margin-top: 6px !important;
                padding-left: 8px !important;
                font-size: 13px !important;
                line-height: 1.55 !important;
                color: rgba(100, 116, 139, 0.96) !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-comment-content {
                color: #f8fafc !important;
              }
              #${rootId} .focus-native-comment-meta {
                margin-top: 8px !important;
                font-size: 12px !important;
                line-height: 1.3 !important;
                color: rgba(100, 116, 139, 0.92) !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-comment-meta {
                color: rgba(226, 232, 240, 0.72) !important;
              }
              #${rootId} .focus-native-footnote {
                margin-top: 12px !important;
                font-size: 12px !important;
                color: rgba(100, 116, 139, 0.92) !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-footnote {
                color: rgba(226, 232, 240, 0.68) !important;
              }
            `;
          };

          const isPlayerRelatedNode = (node) => {
            if (!(node instanceof Element)) {
              return false;
            }
            return !!node.closest([
              '#bilibili-player',
              '#playerWrap',
              '.player-wrap',
              '.bpx-player-container',
              '.bpx-player-video-wrap',
              '.bpx-player-video-area',
              '.bpx-player-state-wrap'
            ].join(','));
          };

          const hideOriginalSections = () => {
            [
              '.right-container',
              '.right-container-inner',
              '.side-toolbar',
              '.right-entry',
              '#viewbox_report',
              '.video-pod',
              '.video-pod__head',
              '.video-pod__header',
              '.video-pod__body',
              '.video-pod__list',
              '.multi-page',
              '[class*="multi-page"]',
              '[class*="episode-list"]',
              '[class*="part-list"]',
              '[class*="page-list"]',
              '#commentapp',
              '#commentapp > *',
              'bili-comments',
              '.comment-container',
              '.bb-comment',
              '[class*="skeleton"]',
              '[class*="loading"]'
            ].forEach((selector) => {
              document.querySelectorAll(selector).forEach((node) => {
                if (node.closest(`#${rootId}`) || isPlayerRelatedNode(node)) {
                  return;
                }
                node.style.setProperty('display', 'none', 'important');
                node.style.setProperty('visibility', 'hidden', 'important');
                node.style.setProperty('position', 'absolute', 'important');
                node.style.setProperty('z-index', '-9999', 'important');
                node.style.setProperty('opacity', '0', 'important');
                node.style.setProperty('pointer-events', 'none', 'important');
              });
            });
          };
          window.__FOCUS_ENFORCE_NATIVE_VIDEO_ORIGINAL_SUPPRESSION__ = hideOriginalSections;

          const buildGroupsHTML = () => (payload.groups || []).map((group) => {
            const items = (group.items || []).map((item) => {
              const subtitle = String(item.subtitle || '').trim();
              const showSubtitle = !!subtitle && !/^BV/i.test(subtitle);
              return `
              <a class="focus-native-episode-card${item.isCurrent ? ' is-current' : ''}${showSubtitle ? '' : ' is-compact'}" href="${escapeHTML(item.targetURL)}">
                ${showSubtitle ? `<div class="focus-native-episode-subtitle">${escapeHTML(subtitle)}</div>` : ''}
                <div class="focus-native-episode-text">${escapeHTML(item.title)}</div>
                ${item.badge ? `<div class="focus-native-episode-badge">${escapeHTML(item.badge)}</div>` : ''}
              </a>
            `;
            }).join('');
            return `
              <section class="focus-native-section">
                <div class="focus-native-header">
                  <div class="focus-native-title">${escapeHTML(group.title)}</div>
                </div>
                <div class="focus-native-scroller">${items}</div>
              </section>
            `;
          }).join('');

          const buildMetaHTML = () => {
            return `
              <section class="focus-native-section">
                <div class="focus-native-video-meta">
                  <a class="focus-native-owner" href="${escapeHTML(payload.authorSpaceURL || '#')}">
                    <div class="focus-native-owner-avatar">${payload.authorAvatarURL ? `<img src="${escapeHTML(payload.authorAvatarURL)}" alt="">` : ''}</div>
                    <div class="focus-native-owner-copy">
                      <div class="focus-native-owner-name">${escapeHTML(payload.authorName || 'UP主')}</div>
                    </div>
                  </a>
                  <div class="focus-native-owner-side">
                    <div class="focus-native-owner-followers">${escapeHTML(payload.authorFollowersText || '0')} 粉丝</div>
                  </div>
                </div>
              </section>
            `;
          };

          const buildCommentsHTML = () => {
            if (!payload.comments || payload.comments.length === 0) {
              return '';
            }
            const items = payload.comments.map((comment) => `
              <article class="focus-native-comment-card">
                <div class="focus-native-avatar">
                  ${comment.avatarURL ? `<img src="${escapeHTML(comment.avatarURL)}" alt="">` : ''}
                </div>
                <div class="focus-native-comment-main">
                  <div class="focus-native-comment-author">${escapeHTML(comment.author)}</div>
                  <div class="focus-native-comment-content">${renderRuns(comment)}${renderReplies(comment)}</div>
                  <div class="focus-native-comment-meta">${[comment.timeText, comment.likeText, comment.replyText].filter(Boolean).map(escapeHTML).join(' · ')}</div>
                </div>
              </article>
            `).join('');
            return `
              <section class="focus-native-section">
                <div class="focus-native-header">
                  <div class="focus-native-title">评论</div>
                </div>
                <div class="focus-native-comment-list">${items}</div>
                <div class="focus-native-footnote">当前展示前 ${payload.comments.length} 条评论。</div>
              </section>
            `;
          };

          ensureStyle();
          const preservedScrollY = window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0;
          const root = document.getElementById(rootId) || document.createElement('section');
          root.id = rootId;
          const renderKey = `${payload.title || ''}::${payload.authorName || ''}::${(payload.groups || []).reduce((sum, group) => sum + ((group.items || []).length), 0)}::${(payload.comments || []).length}`;
          const loadingMaskId = 'focus-native-video-loading-mask';
          const setMountPhase = (phase) => {
            root.setAttribute('data-focus-mount-phase', phase);
          };
          const bumpMountCount = () => {
            const previousCount = Number.parseInt(root.getAttribute('data-focus-mount-count') || '0', 10);
            const nextCount = (Number.isFinite(previousCount) ? previousCount : 0) + 1;
            root.setAttribute('data-focus-mount-count', String(nextCount));
            return nextCount;
          };
          const mountPreparedRoot = (phase) => {
            bumpMountCount();
            setMountPhase(phase);
            mountNativeVideoAugmentRoot(root);
          };
          const applyReadyState = (phase) => {
            document.documentElement.classList.add('focus-native-video-ready');
            document.body?.classList?.add('focus-native-video-ready');
            setMountPhase(phase);
          };
          const clearLoadingMask = () => {
            if (window.__FOCUS_CLEAR_VIDEO_LOADING_MASK__) {
              try {
                window.__FOCUS_CLEAR_VIDEO_LOADING_MASK__(true);
                return;
              } catch (_) {}
            }

            const liveMask = document.getElementById(loadingMaskId);
            if (!liveMask) {
              return;
            }
            liveMask.style.transition = 'opacity 0.18s ease';
            liveMask.style.opacity = '0';
            setTimeout(() => {
              if (liveMask.isConnected) {
                liveMask.remove?.();
              }
            }, 220);
          };

          if (root.getAttribute('data-focus-render-key') === renderKey && checkExistingComponent(root)) {
            hideOriginalSections();
            setMountPhase('sections-hidden');
            root.removeAttribute('data-focus-placeholder');
            mountPreparedRoot('existing-fast-path-mounted');
            applyReadyState('existing-fast-path-ready');
            clearLoadingMask();
            return;
          }

          root.setAttribute('data-focus-version', componentVersion);
          root.setAttribute('data-focus-render-key', renderKey);
          root.removeAttribute('data-focus-placeholder');
          root.style.setProperty('display', 'block', 'important');
          root.style.setProperty('width', '100%', 'important');
          root.style.setProperty('visibility', 'visible', 'important');
          root.style.setProperty('opacity', '1', 'important');
          setMountPhase('content-prepared');
          root.innerHTML = `${buildMetaHTML()}${buildGroupsHTML()}${buildCommentsHTML()}`;

          hideOriginalSections();
          setMountPhase('sections-hidden');
          mountPreparedRoot('single-mount-attached');

          const hideFloatingToolbar = () => {
            document.querySelectorAll([
              '.side-toolbar',
              '.right-entry',
              '[class*="side-toolbar"]',
              '[class*="right-entry"]'
            ].join(',')).forEach((node) => {
              if (!(node instanceof HTMLElement) || node.closest(`#${rootId}`)) {
                return;
              }
              node.style.setProperty('display', 'none', 'important');
              node.style.setProperty('visibility', 'hidden', 'important');
              node.style.setProperty('opacity', '0', 'important');
              node.style.setProperty('pointer-events', 'none', 'important');
            });

            Array.from(document.querySelectorAll('button, a, div, span')).forEach((node) => {
              const text = String(node.textContent || '').trim();
              if (text === '顶部' || text === '小窗' || text === '客服') {
                const element = node.closest('.side-toolbar, .right-entry, button, a, [role="button"], div') || node;
                if (element instanceof HTMLElement && !element.closest(`#${rootId}`)) {
                  element.style.setProperty('display', 'none', 'important');
                  element.style.setProperty('visibility', 'hidden', 'important');
                  element.style.setProperty('opacity', '0', 'important');
                  element.style.setProperty('pointer-events', 'none', 'important');
                }
              }
            });
          };

          hideFloatingToolbar();
          requestAnimationFrame(hideFloatingToolbar);
          setTimeout(hideFloatingToolbar, 160);

          const focusCurrentEpisodeCard = () => {
            const currentCard = root.querySelector('.focus-native-episode-card.is-current');
            const scroller = currentCard?.closest('.focus-native-scroller');
            if (!currentCard || !scroller) {
              return;
            }
            const targetLeft = Math.max(
              currentCard.offsetLeft - Math.max((scroller.clientWidth - currentCard.offsetWidth) / 2, 0),
              0
            );
            scroller.scrollTo({ left: targetLeft, behavior: 'auto' });
          };
          if (payload.groups && payload.groups.length > 0) {
            requestAnimationFrame(focusCurrentEpisodeCard);
          }

          applyReadyState('ready-class-applied');
          requestAnimationFrame(() => {
            setMountPhase('mask-clearing');
            clearLoadingMask();
          });

          const restoreScroll = () => {
            const currentY = window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0;
            if (Math.abs(currentY - preservedScrollY) > 1) {
              window.scrollTo(0, preservedScrollY);
            }
          };
          requestAnimationFrame(() => {
            setMountPhase('scroll-restoring');
            restoreScroll();
          });
          setTimeout(restoreScroll, 90);
        })();
        """#
    }
}

private extension FocusNativeOpusAugmentPayload {
    var javaScript: String {
        let payloadJSON = focusJSONString
        return #"""
        (() => {
          const payload = \#(payloadJSON);
          const styleId = 'focus-native-opus-comments-style';
          const rootId = 'focus-native-opus-comments';
          if (!payload || !payload.comments || payload.comments.length === 0) {
            return;
          }

          const escapeHTML = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#39;'
          })[char] || char);
          const nl2br = (value) => escapeHTML(value).replace(/\n/g, '<br>');
          const safeURL = (value) => {
            try {
              const url = new URL(String(value || ''), location.href);
              return (url.protocol === 'https:' || url.protocol === 'http:') ? url.href : '';
            } catch (_) {
              return '';
            }
          };
          const renderRuns = (comment) => {
            const runs = Array.isArray(comment?.contentRuns) ? comment.contentRuns : [];
            if (runs.length === 0) return nl2br(comment?.content || '');
            return runs.map((run) => {
              if (run?.text) {
                const node = run.text;
                const decorations = [node.underline ? 'underline' : '', node.strikethrough ? 'line-through' : ''].filter(Boolean).join(' ');
                const color = /^#[0-9a-f]{3,8}$/i.test(node.color || '') ? node.color : '';
                const style = [node.bold ? 'font-weight:700' : '', node.italic ? 'font-style:italic' : '', decorations ? `text-decoration:${decorations}` : '', color ? `color:${color}` : ''].filter(Boolean).join(';');
                const value = `<span${style ? ` style="${style}"` : ''}>${nl2br(node.value || '')}</span>`;
                const href = safeURL(node.linkURL);
                return href ? `<a class="focus-native-rich-link" href="${escapeHTML(href)}">${value}</a>` : value;
              }
              if (run?.emote) {
                const node = run.emote;
                const src = safeURL(node.url);
                return src ? `<img class="focus-native-rich-emote" src="${escapeHTML(src)}" alt="${escapeHTML(node.alt || '[表情]')}" loading="lazy">` : escapeHTML(node.alt || '[表情]');
              }
              if (run?.resource) {
                const node = run.resource;
                const href = safeURL(node.url);
                return href ? `<a class="focus-native-rich-link" href="${escapeHTML(href)}">${escapeHTML(node.label || '查看内容')}</a>` : escapeHTML(node.label || '查看内容');
              }
              return '';
            }).join('');
          };
          const renderReplies = (comment) => (comment.previewReplies || []).slice(0, 2).map((reply) => `
            <div class="focus-native-preview-reply"><span class="focus-native-preview-author">${escapeHTML(reply.author)}：</span>${renderRuns(reply)}</div>
          `).join('');
          let style = document.getElementById(styleId);
          if (!style) {
            style = document.createElement('style');
            style.id = styleId;
            document.head.appendChild(style);
          }
          style.textContent = `
            #${rootId} {
              display: block !important;
              width: 100% !important;
              box-sizing: border-box !important;
              padding: 0 12px 24px !important;
            }
            #${rootId} .focus-native-opus-comments {
              padding: 16px !important;
              border-radius: 20px !important;
              background: rgba(255, 255, 255, 0.97) !important;
              border: 1px solid rgba(15, 23, 42, 0.06) !important;
              box-shadow: 0 14px 32px rgba(15, 23, 42, 0.05) !important;
            }
            html[data-focus-theme='dark'] #${rootId} .focus-native-opus-comments {
              background: rgba(23, 27, 35, 0.94) !important;
              border-color: rgba(255, 255, 255, 0.08) !important;
            }
            #${rootId} .focus-native-opus-title {
              margin-bottom: 12px !important;
              font-size: 17px !important;
              font-weight: 700 !important;
              line-height: 1.3 !important;
              color: #111827 !important;
            }
            html[data-focus-theme='dark'] #${rootId} .focus-native-opus-title {
              color: #f8fafc !important;
            }
            #${rootId} .focus-native-opus-list {
              display: grid !important;
              gap: 12px !important;
            }
            #${rootId} .focus-native-opus-item {
              display: flex !important;
              gap: 12px !important;
              padding: 14px !important;
              border-radius: 16px !important;
              background: rgba(248, 250, 252, 0.94) !important;
              border: 1px solid rgba(15, 23, 42, 0.05) !important;
            }
            html[data-focus-theme='dark'] #${rootId} .focus-native-opus-item {
              background: rgba(30, 41, 59, 0.9) !important;
              border-color: rgba(255, 255, 255, 0.06) !important;
            }
            #${rootId} .focus-native-opus-avatar {
              flex: 0 0 38px !important;
              width: 38px !important;
              height: 38px !important;
              border-radius: 999px !important;
              overflow: hidden !important;
              background: rgba(148, 163, 184, 0.16) !important;
            }
            #${rootId} .focus-native-opus-avatar img {
              display: block !important;
              width: 100% !important;
              height: 100% !important;
              object-fit: cover !important;
            }
            #${rootId} .focus-native-opus-main {
              min-width: 0 !important;
              flex: 1 1 auto !important;
            }
            #${rootId} .focus-native-opus-author {
              font-size: 14px !important;
              font-weight: 700 !important;
              line-height: 1.25 !important;
              color: #fb7299 !important;
              margin-bottom: 6px !important;
            }
            #${rootId} .focus-native-opus-content {
              font-size: 15px !important;
              line-height: 1.58 !important;
              color: #0f172a !important;
              word-break: break-word !important;
            }
            #${rootId} .focus-native-rich-emote {
              display: inline-block !important;
              width: 1.35em !important;
              height: 1.35em !important;
              object-fit: contain !important;
              vertical-align: -0.24em !important;
              margin: 0 1px !important;
            }
            #${rootId} .focus-native-rich-link,
            #${rootId} .focus-native-preview-author {
              color: #fb7299 !important;
              text-decoration: none !important;
            }
            #${rootId} .focus-native-preview-reply {
              margin-top: 6px !important;
              padding-left: 8px !important;
              font-size: 13px !important;
              line-height: 1.55 !important;
              color: rgba(100, 116, 139, 0.96) !important;
            }
            html[data-focus-theme='dark'] #${rootId} .focus-native-opus-content {
              color: #f8fafc !important;
            }
            #${rootId} .focus-native-opus-meta {
              margin-top: 8px !important;
              font-size: 12px !important;
              line-height: 1.3 !important;
              color: rgba(100, 116, 139, 0.92) !important;
            }
            html[data-focus-theme='dark'] #${rootId} .focus-native-opus-meta {
              color: rgba(226, 232, 240, 0.72) !important;
            }
          `;

          [
            '#commentapp',
            '#commentapp > *',
            'bili-comments',
            '.comment-container',
            '.bb-comment'
          ].forEach((selector) => {
            document.querySelectorAll(selector).forEach((node) => {
              if (!node.closest(`#${rootId}`)) {
                node.style.setProperty('display', 'none', 'important');
              }
            });
          });

          const root = document.getElementById(rootId) || document.createElement('section');
          root.id = rootId;
          root.innerHTML = `
            <section class="focus-native-opus-comments">
              <div class="focus-native-opus-title">评论</div>
              <div class="focus-native-opus-list">
                ${payload.comments.map((comment) => `
                  <article class="focus-native-opus-item">
                    <div class="focus-native-opus-avatar">
                      ${comment.avatarURL ? `<img src="${escapeHTML(comment.avatarURL)}" alt="">` : ''}
                    </div>
                    <div class="focus-native-opus-main">
                      <div class="focus-native-opus-author">${escapeHTML(comment.author)}</div>
                      <div class="focus-native-opus-content">${renderRuns(comment)}${renderReplies(comment)}</div>
                      <div class="focus-native-opus-meta">${[comment.timeText, comment.likeText, comment.replyText].filter(Boolean).map(escapeHTML).join(' · ')}</div>
                    </div>
                  </article>
                `).join('')}
              </div>
            </section>
          `;

          const anchor = document.querySelector('.opus-detail__primary')
            || document.querySelector('.opus-module-content')
            || document.querySelector('.bili-opus-view');
          if (anchor && anchor.parentNode) {
            anchor.parentNode.insertBefore(root, anchor.nextSibling);
          } else {
            (document.querySelector('main') || document.body || document.documentElement).appendChild(root);
          }
        })();
        """#
    }
}
#endif
