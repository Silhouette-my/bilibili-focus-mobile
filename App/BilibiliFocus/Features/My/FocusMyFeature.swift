#if canImport(UIKit)
import Combine
import CryptoKit
import FocusCore
import Foundation
import SwiftUI
import UIKit

struct FocusMyProfile: Sendable {
    let mid: Int64
    let name: String
    let avatarURL: URL?
    let level: Int
    let following: Int64
    let followers: Int64
}

struct FocusMyHistoryItem: Identifiable, Sendable {
    let id: String
    let title: String
    let coverURL: URL?
    let bvid: String
    let authorName: String
    let viewAt: Int64
    let progress: Int64
    let duration: Int64

    var videoURL: URL? {
        guard !bvid.isEmpty else {
            return nil
        }
        return URL(string: "https://www.bilibili.com/video/\(bvid)/")
    }
}

struct FocusMyFolder: Identifiable, Sendable {
    let id: Int64
    let title: String
    let mediaCount: Int
    let coverURL: URL?
    let previews: [FocusMyFavoriteItem]
}

struct FocusMyPage: Sendable {
    let profile: FocusMyProfile
    let history: [FocusMyHistoryItem]
    let folders: [FocusMyFolder]
    let watchLater: [FocusWatchLaterItem]
}

struct FocusMyFavoriteItem: Identifiable, Sendable {
    let id: String
    let title: String
    let coverURL: URL?
    let bvid: String
    let authorName: String
    let durationText: String
    let playText: String

    var videoURL: URL? {
        guard !bvid.isEmpty else {
            return nil
        }
        return URL(string: "https://www.bilibili.com/video/\(bvid)/")
    }
}

struct FocusUserSpaceProfile {
    let mid: Int64
    let name: String
    let avatarURL: URL?
    let sign: String
    let level: Int
    let following: Int64
    let followers: Int64
    let videoCount: Int
    let articleCount: Int
}

struct FocusUserSpaceVideo: Identifiable {
    let id: String
    let bvid: String
    let title: String
    let coverURL: URL?
    let playText: String
    let durationText: String
    let publishText: String

    var targetURL: URL? {
        guard !bvid.isEmpty else {
            return nil
        }
        return URL(string: "https://www.bilibili.com/video/\(bvid)/")
    }
}

struct FocusUserSpaceCollection: Identifiable {
    enum Kind: String {
        case season
        case series

        var title: String {
            switch self {
            case .season:
                return "合集"
            case .series:
                return "系列"
            }
        }
    }

    let id: String
    let ownerMID: Int64
    let rawID: Int64
    let kind: Kind
    let title: String
    let subtitle: String
    let description: String
    let badgeText: String
    let coverURL: URL?
    let itemCount: Int
}

struct FocusUserSpaceArticle: Identifiable {
    let id: String
    let title: String
    let summary: String
    let coverURL: URL?
    let publishText: String
    let viewText: String
    let targetURL: URL
}

struct FocusUserSpacePage {
    let profile: FocusUserSpaceProfile
    let videos: [FocusUserSpaceVideo]
    let collections: [FocusUserSpaceCollection]
    let articles: [FocusUserSpaceArticle]
    let nextVideoPage: Int?
}

struct FocusUserCollectionPage {
    let collection: FocusUserSpaceCollection
    let videos: [FocusUserSpaceVideo]
    let nextPage: Int?
}

enum FocusArticleRouting {
    private static let webHosts = Set(["bilibili.com", "www.bilibili.com", "m.bilibili.com"])

    static func extractCVID(from url: URL) -> Int64? {
        if url.scheme?.lowercased() == "bilibili", url.host?.lowercased() == "article" {
            guard let component = url.path.split(separator: "/").first else { return nil }
            let candidate = String(component).lowercased().replacingOccurrences(of: "cv", with: "")
            return candidate.allSatisfy(\.isNumber) ? Int64(candidate) : nil
        }

        guard webHosts.contains(url.host?.lowercased() ?? "") else { return nil }
        let path = url.path.lowercased()
        let pathComponents = url.path.split(separator: "/")
        if pathComponents.count == 2,
           pathComponents[0].caseInsensitiveCompare("read") == .orderedSame,
           pathComponents[1].lowercased().hasPrefix("cv")
        {
            let candidate = String(pathComponents[1].dropFirst(2))
            return candidate.allSatisfy(\.isNumber) ? Int64(candidate) : nil
        }

        guard path == "/read/mobile", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("id") == .orderedSame })?
            .value
            .flatMap { $0.allSatisfy(\.isNumber) ? Int64($0) : nil }
    }

    static func canonicalURL(for url: URL) -> URL? {
        extractCVID(from: url).flatMap { URL(string: "https://www.bilibili.com/read/cv\($0)") }
    }
}

struct FocusArticleAuthor {
    let mid: Int64
    let name: String
    let avatarURL: URL?
}

struct FocusArticleStats {
    let views: Int64
    let likes: Int64
    let coins: Int64
    let favorites: Int64
    let comments: Int64
}

struct FocusArticlePage {
    let cvid: Int64
    let title: String
    let author: FocusArticleAuthor
    let publishTime: Int64
    let stats: FocusArticleStats
    let bannerURL: URL?
    let tags: [String]
    let blocks: [FocusArticleBlock]
    let originalURL: URL
}

enum FocusArticleTextAlignment {
    case leading
    case center
    case trailing
}

enum FocusArticleBlock {
    case paragraph([FocusRichTextRun], alignment: FocusArticleTextAlignment)
    case heading([FocusRichTextRun], level: Int)
    case image(url: URL, width: Int, height: Int, caption: String)
    case quote([FocusRichTextRun])
    case list(ordered: Bool, items: [[FocusRichTextRun]])
    case code(language: String, content: String)
    case resource(title: String, url: URL)
    case divider
}

struct FocusOpusAuthor {
    let name: String
    let mid: Int64
    let avatarURL: URL?
}

struct FocusOpusImage: Identifiable {
    let id: String
    let url: URL?
    let width: Int
    let height: Int

    var aspectRatio: CGFloat? {
        guard width > 0, height > 0 else {
            return nil
        }
        return CGFloat(width) / CGFloat(height)
    }
}

enum FocusOpusBlock {
    case text([FocusRichTextRun])
    case image([FocusOpusImage])
    case code(lang: String, content: String)
}

struct FocusOpusParagraph: Identifiable {
    let id = UUID()
    let blocks: [FocusOpusBlock]
}

struct FocusOpusDetailPage {
    let id: String
    let author: FocusOpusAuthor
    let publishTime: String
    let paragraphs: [FocusOpusParagraph]
    let comments: [FocusNativeCommentPayload]
}

private struct FocusHistoryCursor {
    let max: Int64
    let viewAt: Int64
    let business: String

    var hasMore: Bool {
        max > 0 || viewAt > 0 || !business.isEmpty
    }
}

private struct FocusMyHistoryPage {
    let items: [FocusMyHistoryItem]
    let nextCursor: FocusHistoryCursor?
}

private enum FocusMyServiceError: Error {
    case loginRequired
    case message(String)
}

final class FocusMyDataService: @unchecked Sendable {
    private let cookieProvider: any CookieSnapshotProvider

    var sessionVersion: UInt64 { cookieProvider.sessionVersion }
    var sessionReadiness: CookieSessionReadiness { cookieProvider.sessionReadiness }

    func prepareSessionVersion() async -> UInt64 {
        await cookieProvider.loadSnapshot().version
    }
    private let requestLoader: FocusWatchLaterService.RequestLoader

    init(
        cookieProvider: any CookieSnapshotProvider,
        requestLoader: FocusWatchLaterService.RequestLoader? = nil
    ) {
        self.cookieProvider = cookieProvider
        self.requestLoader = requestLoader ?? { request in try await BiliAPINetwork.data(for: request) }
    }

    func resolveLoggedInNavData() async throws -> [String: Any] {
        // Restoration is shared by the provider, not retried by each page.
        let nav = try await requestObject(
            urlString: "https://api.bilibili.com/x/web-interface/nav",
            referer: "https://www.bilibili.com/"
        )
        let code = nav.intValue(at: "code") ?? -1
        if code == -101 { throw FocusMyServiceError.loginRequired }
        guard code == 0, let data = nav.dictionaryValue(at: "data") else {
            throw FocusMyServiceError.message(nav.stringValue(at: "message") ?? "账号资料暂时不可用")
        }
        guard data.boolValue(at: "isLogin") == true else { throw FocusMyServiceError.loginRequired }
        return data
    }

    func fetchRelation(mid: Int64) async throws -> (following: Int64, followers: Int64) {
        let relation = try await requestObject(
            urlString: "https://api.bilibili.com/x/relation/stat?vmid=\(mid)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        let code = relation.intValue(at: "code") ?? -1
        if code == -101 {
            throw FocusMyServiceError.loginRequired
        }
        guard code == 0 else {
            throw FocusMyServiceError.message(relation.stringValue(at: "message") ?? "关注数据加载失败")
        }
        return (
            relation.int64Value(at: "data", "following") ?? 0,
            relation.int64Value(at: "data", "follower") ?? 0
        )
    }

    fileprivate func fetchHistoryPage(pageSize: Int, cursor: FocusHistoryCursor? = nil) async throws -> FocusMyHistoryPage {
        var components = URLComponents(string: "https://api.bilibili.com/x/web-interface/history/cursor")
        var queryItems = [URLQueryItem(name: "ps", value: "\(pageSize)")]
        if let cursor {
            if cursor.max > 0 {
                queryItems.append(URLQueryItem(name: "max", value: "\(cursor.max)"))
            }
            if cursor.viewAt > 0 {
                queryItems.append(URLQueryItem(name: "view_at", value: "\(cursor.viewAt)"))
            }
            if !cursor.business.isEmpty {
                queryItems.append(URLQueryItem(name: "business", value: cursor.business))
            }
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw FocusMyServiceError.message("历史记录请求地址无效")
        }

        let root = try await requestObject(url: url, referer: "https://www.bilibili.com/")
        let code = root.intValue(at: "code") ?? -1
        if code == -101 {
            throw FocusMyServiceError.loginRequired
        }
        guard code == 0 else {
            throw FocusMyServiceError.message(root.stringValue(at: "message") ?? "历史记录加载失败")
        }

        let list = root.arrayValue(at: "data", "list") ?? []
        let rawItems = list.compactMap { item -> FocusMyHistoryItem? in
            let history = item.dictionaryValue(at: "history")
            let bvid = history?.stringValue(at: "bvid") ?? ""
            guard !bvid.isEmpty else {
                return nil
            }
            let coverString = item.stringValue(at: "cover")?.nilIfBlank
                ?? history?.stringValue(at: "cover")?.nilIfBlank
                ?? Self.firstString(in: item["covers"])?.nilIfBlank
                ?? Self.firstString(in: history?["covers"])?.nilIfBlank
            return FocusMyHistoryItem(
                id: "\(item.int64Value(at: "view_at") ?? 0)-\(bvid)",
                title: item.stringValue(at: "title") ?? "",
                coverURL: URL(string: Self.normalizedURLString(coverString) ?? ""),
                bvid: bvid,
                authorName: item.stringValue(at: "author_name") ?? "",
                viewAt: item.int64Value(at: "view_at") ?? 0,
                progress: item.int64Value(at: "progress") ?? 0,
                duration: item.int64Value(at: "duration") ?? 0
            )
        }

        let cursorData = root.dictionaryValue(at: "data", "cursor")
        let nextCursor = FocusHistoryCursor(
            max: cursorData?.int64Value(at: "max") ?? 0,
            viewAt: cursorData?.int64Value(at: "view_at") ?? 0,
            business: cursorData?.stringValue(at: "business") ?? ""
        )

        return FocusMyHistoryPage(
            items: await enrichHistoryItems(rawItems),
            nextCursor: nextCursor.hasMore ? nextCursor : nil
        )
    }

    func fetchFolders(mid: Int64) async throws -> [FocusMyFolder] {
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/v3/fav/folder/created/list-all?up_mid=\(mid)&web_location=333.1387",
            referer: "https://www.bilibili.com/"
        )
        let code = root.intValue(at: "code") ?? -1
        if code == -101 {
            throw FocusMyServiceError.loginRequired
        }
        guard code == 0 else {
            throw FocusMyServiceError.message(root.stringValue(at: "message") ?? "收藏夹加载失败")
        }

        let list = root.arrayValue(at: "data", "list") ?? []
        var folders: [FocusMyFolder] = []
        for folder in list {
            guard let id = folder.int64Value(at: "id") else {
                continue
            }
            folders.append(FocusMyFolder(
                id: id,
                title: folder.stringValue(at: "title") ?? "",
                mediaCount: folder.intValue(at: "media_count") ?? 0,
                coverURL: URL(string: Self.normalizedURLString(folder.stringValue(at: "cover")) ?? ""),
                previews: []
            ))
        }
        return folders
    }

    func fetchFolderContents(mediaID: Int64, page: Int = 1, pageSize: Int = 20) async throws -> [FocusMyFavoriteItem] {
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/v3/fav/resource/list?media_id=\(mediaID)&pn=\(max(page, 1))&ps=\(max(pageSize, 1))&order=mtime&type=0&tid=0&platform=web&web_location=333.1387",
            referer: "https://www.bilibili.com/"
        )
        let code = root.intValue(at: "code") ?? -1
        if code == -101 {
            throw FocusMyServiceError.loginRequired
        }
        guard code == 0 else {
            throw FocusMyServiceError.message(root.stringValue(at: "message") ?? "收藏夹内容加载失败")
        }

        let medias = root.arrayValue(at: "data", "medias") ?? []
        return medias.compactMap { media -> FocusMyFavoriteItem? in
            let bvid = media.stringValue(at: "bvid")?.nilIfBlank ?? ""
            guard !bvid.isEmpty else {
                return nil
            }
            return FocusMyFavoriteItem(
                id: bvid,
                title: Self.cleanText(media.stringValue(at: "title")).nilIfBlank ?? "视频",
                coverURL: URL(string: Self.normalizedURLString(media.stringValue(at: "cover")) ?? ""),
                bvid: bvid,
                authorName: Self.cleanText(media.stringValue(at: "upper", "name")),
                durationText: Self.formatVideoLength(
                    media.stringValue(at: "duration"),
                    seconds: media.int64Value(at: "duration")
                ),
                playText: Self.formatCount(media.int64Value(at: "cnt_info", "play") ?? 0)
            )
        }
    }

    private func requestObject(urlString: String, referer: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw FocusMyServiceError.message("请求地址无效")
        }
        return try await requestObject(url: url, referer: referer)
    }

    private func requestObject(url: URL, referer: String) async throws -> [String: Any] {
        let data = try await requestData(url: url, referer: referer)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw FocusMyServiceError.message("接口返回无效数据")
        }
        return object
    }

    private func requestData(url: URL, referer: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(FocusNativePageAugmentService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")

        let snapshot = await cookieProvider.loadSnapshot()
        let version = snapshot.version
        guard version == cookieProvider.sessionVersion else { throw CancellationError() }
        if snapshot.readiness == .expired { throw FocusMyServiceError.loginRequired }
        if snapshot.cookies.isEmpty && (snapshot.readiness == .restoring || snapshot.readiness == .unconfirmed) {
            throw URLError(.resourceUnavailable)
        }
        request = CookieRequestPolicy.attach(cookies: snapshot.cookies, to: request)

        let (data, response) = try await requestLoader(request)
        try Task.checkCancellation()
        guard version == cookieProvider.sessionVersion else { throw CancellationError() }
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw FocusMyServiceError.loginRequired }
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw FocusMyServiceError.message("网络请求失败")
        }
        return data
    }

    private func enrichHistoryItems(_ items: [FocusMyHistoryItem]) async -> [FocusMyHistoryItem] {
        guard items.contains(where: { $0.coverURL == nil }) else {
            return items
        }

        var resolved: [FocusMyHistoryItem] = []
        resolved.reserveCapacity(items.count)

        for item in items {
            guard item.coverURL == nil else {
                resolved.append(item)
                continue
            }

            guard let resolvedURL = try? await fetchVideoCoverURL(for: item.bvid) else {
                resolved.append(item)
                continue
            }

            resolved.append(
                FocusMyHistoryItem(
                    id: item.id,
                    title: item.title,
                    coverURL: resolvedURL,
                    bvid: item.bvid,
                    authorName: item.authorName,
                    viewAt: item.viewAt,
                    progress: item.progress,
                    duration: item.duration
                )
            )
        }

        return resolved
    }

    private func fetchVideoCoverURL(for bvid: String) async throws -> URL? {
        guard !bvid.isEmpty else {
            return nil
        }

        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)",
            referer: "https://www.bilibili.com/video/\(bvid)"
        )
        guard root.intValue(at: "code") == 0, let cover = root.stringValue(at: "data", "pic") else {
            return nil
        }
        return URL(string: Self.normalizedURLString(cover) ?? "")
    }

    static func parseArticleContent(_ rawContent: String) -> [FocusArticleBlock] {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return [] }
        if
            content.hasPrefix("{"),
            let data = content.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let ops = object["ops"] as? [[String: Any]]
        {
            return parseArticleOps(ops)
        }
        return parseStructuredArticleHTML(content)
    }

    private static func parseArticleOps(_ ops: [[String: Any]]) -> [FocusArticleBlock] {
        var blocks: [FocusArticleBlock] = []
        var runs: [FocusRichTextRun] = []
        func flush(_ attributes: [String: Any]? = nil) {
            guard !runs.isEmpty else { return }
            let value = runs
            runs.removeAll(keepingCapacity: true)
            if let level = attributes?["header"] as? NSNumber {
                blocks.append(.heading(value, level: min(max(level.intValue, 1), 6)))
            } else if (attributes?["blockquote"] as? Bool) == true {
                blocks.append(.quote(value))
            } else if let list = attributes?["list"] as? String {
                let ordered = list == "ordered"
                if case let .list(previousOrdered, items)? = blocks.last, previousOrdered == ordered {
                    blocks[blocks.count - 1] = .list(ordered: ordered, items: items + [value])
                } else {
                    blocks.append(.list(ordered: ordered, items: [value]))
                }
            } else if attributes?["code-block"] != nil {
                let code = value.map(\.plainText).joined()
                if case let .code(language, previous)? = blocks.last {
                    blocks[blocks.count - 1] = .code(language: language, content: previous + "\n" + code)
                } else {
                    blocks.append(.code(language: "", content: code))
                }
            } else {
                let alignment: FocusArticleTextAlignment = switch attributes?["align"] as? String {
                case "center": .center
                case "right", "end": .trailing
                default: .leading
                }
                blocks.append(.paragraph(value, alignment: alignment))
            }
        }
        for op in ops {
            let attributes = op["attributes"] as? [String: Any]
            if let text = op["insert"] as? String {
                let pieces = text.split(separator: "\n", omittingEmptySubsequences: false)
                for (index, piece) in pieces.enumerated() {
                    if !piece.isEmpty {
                        runs.append(
                            .text(
                                value: decodeArticleHTMLEntities(String(piece)),
                                bold: attributes?["bold"] as? Bool ?? false,
                                italic: attributes?["italic"] as? Bool ?? false,
                                underline: attributes?["underline"] as? Bool ?? false,
                                strikethrough: attributes?["strike"] as? Bool ?? false,
                                color: attributes?["color"] as? String,
                                linkURL: normalizedArticleURL(attributes?["link"] as? String)
                            )
                        )
                    }
                    if index < pieces.count - 1 { flush(attributes) }
                }
                continue
            }
            guard let embed = op["insert"] as? [String: Any] else { continue }
            if let image = (embed["native-image"] ?? embed["image"]) as? [String: Any] {
                flush()
                if let url = normalizedArticleURL(image["url"] as? String ?? image["src"] as? String) {
                    blocks.append(
                        .image(
                            url: url,
                            width: (image["width"] as? NSNumber)?.intValue ?? 0,
                            height: (image["height"] as? NSNumber)?.intValue ?? 0,
                            caption: image["alt"] as? String ?? ""
                        )
                    )
                }
                continue
            }
            if let rawImage = embed["image"] as? String, let url = normalizedArticleURL(rawImage) {
                flush()
                blocks.append(.image(url: url, width: 0, height: 0, caption: ""))
                continue
            }
            if embed["cut-off"] != nil || embed["divider"] != nil || embed["hr"] != nil {
                flush()
                blocks.append(.divider)
                continue
            }
            if let entry = embed.first(where: { $0.value is [String: Any] }),
               let resource = entry.value as? [String: Any]
            {
                flush()
                blocks.append(.resource(
                    title: resource["title"] as? String ?? resource["name"] as? String ?? "站内内容",
                    url: normalizedArticleURL(resource["url"] as? String ?? resource["jump_url"] as? String)
                        ?? embeddedArticleResourceURL(kind: entry.key, resource: resource)
                        ?? URL(string: "https://www.bilibili.com/")!
                ))
            }
        }
        flush()
        return blocks
    }

    private static func parseStructuredArticleHTML(_ source: String) -> [FocusArticleBlock] {
        let html = source.replacingOccurrences(
            of: #"(?is)<(script|style)[^>]*>.*?</\1>"#,
            with: "",
            options: .regularExpression
        )
        guard let tokenExpression = try? NSRegularExpression(pattern: #"(?s)<[^>]+>|[^<]+"#) else { return [] }

        var blocks: [FocusArticleBlock] = []
        var runs: [FocusRichTextRun] = []
        var boldDepth = 0
        var italicDepth = 0
        var underlineDepth = 0
        var strikeDepth = 0
        var linkURL: URL?
        var color: String?
        var colorStack: [String?] = []
        var alignment: FocusArticleTextAlignment = .leading
        var headingLevel: Int?
        var isQuote = false
        var listOrdered: Bool?
        var listItems: [[FocusRichTextRun]] = []
        var codeLanguage = ""
        var codeBuffer: String?

        func trimmed(_ values: [FocusRichTextRun]) -> [FocusRichTextRun] {
            var result = values
            if let first = result.first,
               case let .text(value, bold, italic, underline, strike, runColor, link) = first
            {
                result[0] = .text(
                    value: value.trimmingCharacters(in: .whitespacesAndNewlines),
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    strikethrough: strike,
                    color: runColor,
                    linkURL: link
                )
            }
            if result.count > 1,
               let last = result.last,
               case let .text(value, bold, italic, underline, strike, runColor, link) = last
            {
                result[result.count - 1] = .text(
                    value: value.trimmingCharacters(in: .whitespacesAndNewlines),
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    strikethrough: strike,
                    color: runColor,
                    linkURL: link
                )
            }
            return result.filter { !$0.plainText.isEmpty }
        }

        func flushRuns() {
            let value = trimmed(runs)
            runs.removeAll(keepingCapacity: true)
            guard !value.isEmpty else { return }
            if let headingLevel {
                blocks.append(.heading(value, level: headingLevel))
            } else if isQuote {
                blocks.append(.quote(value))
            } else if listOrdered != nil {
                listItems.append(value)
            } else {
                blocks.append(.paragraph(value, alignment: alignment))
            }
        }

        func flushList() {
            flushRuns()
            guard let ordered = listOrdered else { return }
            if !listItems.isEmpty { blocks.append(.list(ordered: ordered, items: listItems)) }
            listItems.removeAll(keepingCapacity: true)
            listOrdered = nil
        }

        let fullRange = NSRange(html.startIndex ..< html.endIndex, in: html)
        for match in tokenExpression.matches(in: html, range: fullRange) {
            guard let tokenRange = Range(match.range, in: html) else { continue }
            let token = String(html[tokenRange])
            if !token.hasPrefix("<") {
                let text = decodeArticleHTMLEntities(token)
                if codeBuffer != nil {
                    codeBuffer?.append(contentsOf: text)
                } else if !text.isEmpty, !(runs.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    runs.append(.text(
                        value: text,
                        bold: boldDepth > 0,
                        italic: italicDepth > 0,
                        underline: underlineDepth > 0,
                        strikethrough: strikeDepth > 0,
                        color: color,
                        linkURL: linkURL
                    ))
                }
                continue
            }

            let closing = token.hasPrefix("</")
            guard let tagRange = token.range(of: #"^</?\s*[A-Za-z0-9]+"#, options: .regularExpression) else { continue }
            let tag = token[tagRange]
                .trimmingCharacters(in: CharacterSet(charactersIn: "</> \t\r\n"))
                .lowercased()
            let attributes = parseArticleHTMLAttributes(token)

            if closing {
                switch tag {
                case "strong", "b": boldDepth = max(0, boldDepth - 1)
                case "em", "i": italicDepth = max(0, italicDepth - 1)
                case "u": underlineDepth = max(0, underlineDepth - 1)
                case "s", "del": strikeDepth = max(0, strikeDepth - 1)
                case "span": color = colorStack.popLast() ?? nil
                case "a": linkURL = nil
                case "p", "div": flushRuns(); alignment = .leading
                case "h1", "h2", "h3", "h4", "h5", "h6": flushRuns(); headingLevel = nil
                case "blockquote": flushRuns(); isQuote = false
                case "li": flushRuns()
                case "ul", "ol": flushList()
                case "pre":
                    let code = codeBuffer?.trimmingCharacters(in: .newlines) ?? ""
                    if !code.isEmpty { blocks.append(.code(language: codeLanguage, content: code)) }
                    codeBuffer = nil
                    codeLanguage = ""
                case "figcaption":
                    let caption = trimmed(runs).map(\.plainText).joined()
                    runs.removeAll(keepingCapacity: true)
                    if !caption.isEmpty, case let .image(url, width, height, _)? = blocks.last {
                        blocks[blocks.count - 1] = .image(url: url, width: width, height: height, caption: caption)
                    }
                default: break
                }
                continue
            }

            switch tag {
            case "strong", "b": boldDepth += 1
            case "em", "i": italicDepth += 1
            case "u": underlineDepth += 1
            case "s", "del": strikeDepth += 1
            case "span":
                colorStack.append(color)
                color = articleColor(from: attributes["style"]) ?? color
            case "a": linkURL = normalizedArticleURL(attributes["href"])
            case "br":
                runs.append(.text(
                    value: "\n",
                    bold: boldDepth > 0,
                    italic: italicDepth > 0,
                    underline: underlineDepth > 0,
                    strikethrough: strikeDepth > 0,
                    color: color,
                    linkURL: linkURL
                ))
            case "p", "div": flushRuns(); alignment = articleAlignment(from: attributes["style"])
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flushRuns()
                headingLevel = Int(tag.dropFirst()) ?? 2
            case "blockquote": flushRuns(); isQuote = true
            case "ul", "ol": flushList(); listOrdered = tag == "ol"
            case "li": flushRuns()
            case "pre":
                flushRuns()
                codeBuffer = ""
                codeLanguage = attributes["data-lang"]?.components(separatedBy: "@").first
                    ?? attributes["lang"]
                    ?? ""
                if let encoded = attributes["codecontent"] { codeBuffer = encoded.removingPercentEncoding ?? encoded }
            case "hr": flushRuns(); blocks.append(.divider)
            case "img":
                let classes = attributes["class"] ?? ""
                if classes.contains("cut-off") {
                    flushRuns()
                    blocks.append(.divider)
                } else if let aid = attributes["aid"], classes.contains("card") {
                    flushRuns()
                    blocks.append(.resource(
                        title: articleResourceTitle(classes),
                        url: articleResourceURL(classes: classes, id: aid)
                    ))
                } else if let rawURL = attributes["data-src"] ?? attributes["data-original"] ?? attributes["src"],
                          let url = normalizedArticleURL(rawURL)
                {
                    flushRuns()
                    blocks.append(.image(
                        url: url,
                        width: Int(attributes["width"] ?? "") ?? 0,
                        height: Int(attributes["height"] ?? "") ?? 0,
                        caption: attributes["alt"] ?? ""
                    ))
                }
            default: break
            }
        }

        flushList()
        flushRuns()
        return blocks
    }

    private static func parseArticleHTMLAttributes(_ tag: String) -> [String: String] {
        var attributes: [String: String] = [:]
        let fullRange = NSRange(tag.startIndex ..< tag.endIndex, in: tag)
        if let quoted = try? NSRegularExpression(
            pattern: #"([A-Za-z0-9_:-]+)\s*=\s*([\"'])(.*?)\2"#,
            options: .dotMatchesLineSeparators
        ) {
            for match in quoted.matches(in: tag, range: fullRange) {
                guard
                    let nameRange = Range(match.range(at: 1), in: tag),
                    let valueRange = Range(match.range(at: 3), in: tag)
                else { continue }
                attributes[String(tag[nameRange]).lowercased()] = decodeArticleHTMLEntities(String(tag[valueRange]))
            }
        }
        if let unquoted = try? NSRegularExpression(pattern: #"([A-Za-z0-9_:-]+)\s*=\s*([^\s>\"']+)"#) {
            for match in unquoted.matches(in: tag, range: fullRange) {
                guard
                    let nameRange = Range(match.range(at: 1), in: tag),
                    let valueRange = Range(match.range(at: 2), in: tag)
                else { continue }
                let name = String(tag[nameRange]).lowercased()
                if attributes[name] == nil {
                    attributes[name] = decodeArticleHTMLEntities(String(tag[valueRange]))
                }
            }
        }
        return attributes
    }

    private static func articleAlignment(from style: String?) -> FocusArticleTextAlignment {
        let value = style?.lowercased() ?? ""
        if value.range(of: #"text-align\s*:\s*center"#, options: .regularExpression) != nil { return .center }
        if value.range(of: #"text-align\s*:\s*(right|end)"#, options: .regularExpression) != nil { return .trailing }
        return .leading
    }

    private static func articleColor(from style: String?) -> String? {
        guard
            let style,
            let range = style.range(of: #"(?i)color\s*:\s*([^;]+)"#, options: .regularExpression),
            let value = style[range].split(separator: ":", maxSplits: 1).last
        else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func articleResourceTitle(_ classes: String) -> String {
        if classes.contains("video-card") { return "视频" }
        if classes.contains("article-card") { return "专栏" }
        if classes.contains("fanju-card") { return "番剧" }
        if classes.contains("live-card") { return "直播" }
        if classes.contains("music-card") { return "音频" }
        return "站内内容"
    }

    private static func articleResourceURL(classes: String, id: String) -> URL {
        let raw: String
        if classes.contains("video-card") {
            raw = "https://www.bilibili.com/video/av\(id.components(separatedBy: ",").first ?? id)"
        } else if classes.contains("article-card") {
            raw = "https://www.bilibili.com/read/cv\(id)"
        } else if classes.contains("fanju-card") {
            raw = "https://www.bilibili.com/bangumi/play/\(id)"
        } else if classes.contains("live-card") {
            raw = "https://live.bilibili.com/\(id)"
        } else if classes.contains("music-card") {
            raw = "https://www.bilibili.com/audio/\(id)"
        } else {
            raw = "https://www.bilibili.com/"
        }
        return URL(string: raw)!
    }

    private static func embeddedArticleResourceURL(kind: String, resource: [String: Any]) -> URL? {
        let type = (resource.stringValue(at: "type") ?? kind).lowercased()
        let bvid = resource.stringValue(at: "bvid") ?? resource.stringValue(at: "bv_id")
        if let bvid { return URL(string: "https://www.bilibili.com/video/\(bvid)") }
        if type.contains("video") || type.contains("archive") {
            if let aid = resource.stringValue(at: "aid") ?? resource.stringValue(at: "id") ?? resource.int64Value(at: "aid").map(String.init) {
                return URL(string: "https://www.bilibili.com/video/av\(aid.replacingOccurrences(of: "av", with: ""))")
            }
        }
        if type.contains("article"),
           let cvid = resource.stringValue(at: "cvid") ?? resource.stringValue(at: "id") ?? resource.int64Value(at: "id").map(String.init)
        {
            return URL(string: "https://www.bilibili.com/read/cv\(cvid.replacingOccurrences(of: "cv", with: ""))")
        }
        if type.contains("bangumi") || type.contains("pgc") || type.contains("episode"),
           let episode = resource.stringValue(at: "ep_id") ?? resource.stringValue(at: "id") ?? resource.int64Value(at: "ep_id").map(String.init)
        {
            return URL(string: "https://www.bilibili.com/bangumi/play/ep\(episode.replacingOccurrences(of: "ep", with: ""))")
        }
        if type.contains("live"),
           let room = resource.stringValue(at: "room_id") ?? resource.stringValue(at: "id") ?? resource.int64Value(at: "room_id").map(String.init)
        {
            return URL(string: "https://live.bilibili.com/\(room)")
        }
        if type.contains("audio") || type.contains("music"),
           let audio = resource.stringValue(at: "auid") ?? resource.stringValue(at: "id") ?? resource.int64Value(at: "id").map(String.init)
        {
            return URL(string: "https://www.bilibili.com/audio/au\(audio.replacingOccurrences(of: "au", with: ""))")
        }
        return nil
    }

    private static func decodeArticleHTMLEntities(_ raw: String) -> String {
        var result = raw
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        guard let expression = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else { return result }
        while let match = expression.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              let fullRange = Range(match.range(at: 0), in: result),
              let valueRange = Range(match.range(at: 1), in: result)
        {
            let value = String(result[valueRange])
            let scalar = value.lowercased().hasPrefix("x")
                ? UInt32(value.dropFirst(), radix: 16)
                : UInt32(value, radix: 10)
            result.replaceSubrange(fullRange, with: scalar.flatMap(UnicodeScalar.init).map(String.init) ?? "")
        }
        return result
    }

    private static func normalizedArticleURL(_ raw: String?) -> URL? {
        guard let value = normalizedURLString(raw) else { return nil }
        if value.hasPrefix("/") { return URL(string: "https://www.bilibili.com\(value)") }
        return URL(string: value)
    }

    private static func firstString(in rawValue: Any?) -> String? {
        if let string = rawValue as? String {
            return string
        }
        if let array = rawValue as? [Any] {
            for item in array {
                if let string = item as? String, !string.isEmpty {
                    return string
                }
                if let dictionary = item as? [String: Any] {
                    if let string = dictionary.stringValue(at: "self")?.nilIfBlank {
                        return string
                    }
                    if let string = dictionary.stringValue(at: "url")?.nilIfBlank {
                        return string
                    }
                    if let string = dictionary.stringValue(at: "src")?.nilIfBlank {
                        return string
                    }
                }
            }
        }
        return nil
    }

    private static func cleanText(_ raw: String?) -> String {
        guard let raw else {
            return ""
        }
        return raw
            .replacingOccurrences(of: "<em class=\"keyword\">", with: "")
            .replacingOccurrences(of: "</em>", with: "")
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func formatVideoLength(_ length: String?, seconds: Int64?) -> String {
        if let length = length?.nilIfBlank {
            return length
        }
        guard let seconds, seconds > 0 else {
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

    static func normalizedURLString(_ raw: String?) -> String? {
        guard let raw = raw?.nilIfBlank else {
            return nil
        }
        if raw.lowercased().hasPrefix("http://") {
            return "https://" + raw.dropFirst("http://".count)
        }
        if raw.hasPrefix("//") {
            return "https:\(raw)"
        }
        return raw
    }
}

@MainActor
final class FocusMyViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loginRequired
        case failed(String)
        case loaded(FocusMyPage)
    }

    enum Section: String, CaseIterable, Sendable {
        case relation, history, folders, previews, watchLater

        var title: String {
            switch self {
            case .relation: return "关注与粉丝"
            case .history: return "播放历史"
            case .folders: return "收藏夹"
            case .previews: return "收藏夹预览"
            case .watchLater: return "稍后再看"
            }
        }
    }

    enum SectionState: Equatable {
        case loading, loaded, failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshErrorMessage: String?
    @Published private(set) var sectionStates: [Section: SectionState] = [:]
    @Published private(set) var previewErrors: [Int64: String] = [:]
    @Published private(set) var watchLaterActionsInFlight: Set<Int64> = []
    @Published var actionErrorMessage: String?

    private let service: FocusMyDataService
    private let watchLaterService: FocusWatchLaterService
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var loadedSessionVersion: UInt64?
    private var requestSessionVersion: UInt64?
    private var sectionTasks: [Section: Task<Void, Never>] = [:]
    private var watchLaterActionTasks: [Int64: Task<Void, Never>] = [:]

    static let previewFolderLimit = 6
    static let previewConcurrency = 2

    init(
        service: FocusMyDataService,
        watchLaterService: FocusWatchLaterService
    ) {
        self.service = service
        self.watchLaterService = watchLaterService
    }

    deinit {
        task?.cancel()
        watchLaterActionTasks.values.forEach { $0.cancel() }
    }

    func suspend() {
        generation = UUID()
        task?.cancel()
        task = nil
        sectionTasks.values.forEach { $0.cancel() }
        sectionTasks.removeAll()
        watchLaterActionTasks.values.forEach { $0.cancel() }
        watchLaterActionTasks.removeAll()
        watchLaterActionsInFlight.removeAll()
        isRefreshing = false
        if case .loading = state { state = .idle }
    }

    func resetForSessionChange() {
        suspend()
        state = .idle
        loadedSessionVersion = nil
        sectionStates.removeAll()
        previewErrors.removeAll()
        refreshErrorMessage = nil
        actionErrorMessage = nil
    }

    func reconcileSessionVersion(_ version: UInt64) {
        // The shared coordinator calls this only after confirming unchanged
        // credentials, never while a cookie read is merely uncertain.
        guard version == service.sessionVersion else { return }
        if page != nil { loadedSessionVersion = version }
        let hasActiveWork = task != nil || (!sectionTasks.isEmpty && sectionStates.values.contains(.loading))
        if hasActiveWork, requestSessionVersion != version {
            reload()
        } else if case .loading = state, task == nil {
            reload()
        }
    }

    func removeFromWatchLater(aid: Int64) {
        guard case .loaded = state, loadedSessionVersion == service.sessionVersion,
              aid > 0, watchLaterActionsInFlight.insert(aid).inserted else {
            return
        }
        actionErrorMessage = nil
        let actionGeneration = generation
        let actionVersion = service.sessionVersion
        let actionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == actionGeneration {
                    watchLaterActionsInFlight.remove(aid)
                    watchLaterActionTasks[aid] = nil
                }
            }
            do {
                try await watchLaterService.remove(aid: aid)
                guard isCurrent(actionGeneration, version: actionVersion), case let .loaded(page) = state else {
                    return
                }
                state = .loaded(
                    FocusMyPage(
                        profile: page.profile,
                        history: page.history,
                        folders: page.folders,
                        watchLater: page.watchLater.filter { $0.aid != aid }
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(actionGeneration, version: actionVersion) else { return }
                actionErrorMessage = error.localizedDescription
            }
        }
        watchLaterActionTasks[aid] = actionTask
    }

    func dismissActionError() {
        actionErrorMessage = nil
    }

    var navigationTitle: String {
        "我的"
    }

    func loadIfNeeded() {
        guard case .idle = state else {
            return
        }
        reload()
    }

    func refreshForAppearance() {
        if loadedSessionVersion != nil && loadedSessionVersion != service.sessionVersion,
           service.sessionReadiness == .expired || service.sessionReadiness == .anonymous {
            resetForSessionChange()
        }
        switch state {
        case .idle, .loginRequired, .failed: reload()
        case .loaded:
            if task == nil && sectionStates.values.contains(.loading) { reload() }
        case .loading: break
        }
    }

    func reload() {
        suspend()
        requestSessionVersion = service.sessionVersion
        let requestID = generation
        task = Task { [weak self] in await self?.performLoad(requestID: requestID) }
    }

    func refresh() async {
        reload()
        await task?.value
    }

    func retrySection(_ section: Section) {
        guard case .loaded = state, sectionStates[section] != .loading,
              let version = loadedSessionVersion, version == service.sessionVersion else { return }
        let requestID = generation
        sectionStates[section] = .loading
        sectionTasks[section]?.cancel()
        sectionTasks[section] = Task { [weak self] in
            await self?.loadSection(section, requestID: requestID, version: version)
        }
    }

    private func isCurrent(_ requestID: UUID, version: UInt64) -> Bool {
        !Task.isCancelled && generation == requestID && service.sessionVersion == version
    }

    private var page: FocusMyPage? {
        guard case let .loaded(page) = state else { return nil }
        return page
    }

    private func updatePage(
        profile: FocusMyProfile? = nil,
        history: [FocusMyHistoryItem]? = nil,
        folders: [FocusMyFolder]? = nil,
        watchLater: [FocusWatchLaterItem]? = nil
    ) {
        guard let page else { return }
        state = .loaded(FocusMyPage(
            profile: profile ?? page.profile, history: history ?? page.history,
            folders: folders ?? page.folders, watchLater: watchLater ?? page.watchLater
        ))
    }

    private func expireSession() {
        suspend()
        loadedSessionVersion = nil
        sectionStates.removeAll()
        previewErrors.removeAll()
        state = .loginRequired
    }

    private func displayError(_ error: Error) -> String {
        if case let FocusMyServiceError.message(message) = error { return message }
        return error.localizedDescription
    }

    private func performLoad(requestID: UUID) async {
        if loadedSessionVersion != nil && loadedSessionVersion != service.sessionVersion,
           service.sessionReadiness == .expired || service.sessionReadiness == .anonymous {
            state = .idle
        }
        isRefreshing = page != nil
        refreshErrorMessage = nil
        if page == nil { state = .loading }
        defer {
            if generation == requestID { isRefreshing = false; task = nil }
        }
        let version = await service.prepareSessionVersion()
        guard isCurrent(requestID, version: version) else { return }
        let span = BiliPerformanceStore.shared.begin(.myProfile, correlationID: requestID)
        do {
            let data = try await service.resolveLoggedInNavData()
            guard isCurrent(requestID, version: version) else {
                BiliPerformanceStore.shared.end(span, outcome: .stale)
                return
            }
            let mid = data.int64Value(at: "mid") ?? 0
            let previous = page?.profile.mid == mid ? page : nil
            let profile = FocusMyProfile(
                mid: mid, name: data.stringValue(at: "uname") ?? "",
                avatarURL: URL(string: FocusMyDataService.normalizedURLString(data.stringValue(at: "face")) ?? ""),
                level: data.intValue(at: "level_info", "current_level") ?? 0,
                following: previous?.profile.following ?? 0,
                followers: previous?.profile.followers ?? 0
            )
            loadedSessionVersion = version
            sectionStates = Dictionary(uniqueKeysWithValues: Section.allCases.map { ($0, .loading) })
            previewErrors.removeAll()
            state = .loaded(FocusMyPage(
                profile: profile, history: previous?.history ?? [],
                folders: previous?.folders ?? [], watchLater: previous?.watchLater ?? []
            ))
            BiliPerformanceStore.shared.end(span)
            // Each branch publishes on completion; none is on the basic-profile path.
            async let relation: Void = loadSection(.relation, requestID: requestID, version: version)
            async let history: Void = loadSection(.history, requestID: requestID, version: version)
            async let folders: Void = loadSection(.folders, requestID: requestID, version: version)
            async let watchLater: Void = loadSection(.watchLater, requestID: requestID, version: version)
            _ = await (relation, history, folders, watchLater)
        } catch {
            BiliPerformanceStore.shared.end(span, outcome: error is CancellationError ? .cancelled : .failure)
            guard isCurrent(requestID, version: version) else { return }
            if case FocusMyServiceError.loginRequired = error { expireSession() }
            else if page != nil { refreshErrorMessage = displayError(error) }
            else { state = .failed(displayError(error)) }
        }
    }

    private func loadSection(_ section: Section, requestID: UUID, version: UInt64) async {
        guard isCurrent(requestID, version: version), let currentPage = page else { return }
        if section == .previews {
            await loadPreviews(requestID: requestID, version: version)
            return
        }
        let stage: BiliPerformanceStage
        switch section {
        case .relation: stage = .myFollowing
        case .history: stage = .myHistory
        case .folders: stage = .myFavorites
        case .watchLater: stage = .myWatchLater
        case .previews: stage = .favoritePreviews
        }
        let span = BiliPerformanceStore.shared.begin(stage, correlationID: requestID)
        do {
            switch section {
            case .relation:
                let relation = try await service.fetchRelation(mid: currentPage.profile.mid)
                guard isCurrent(requestID, version: version) else { throw CancellationError() }
                let profile = currentPage.profile
                updatePage(profile: FocusMyProfile(
                    mid: profile.mid, name: profile.name, avatarURL: profile.avatarURL,
                    level: profile.level, following: relation.following, followers: relation.followers
                ))
            case .history:
                let history = try await service.fetchHistoryPage(pageSize: 12).items
                guard isCurrent(requestID, version: version) else { throw CancellationError() }
                updatePage(history: history)
            case .folders:
                let folders = try await service.fetchFolders(mid: currentPage.profile.mid)
                guard isCurrent(requestID, version: version) else { throw CancellationError() }
                let previousPreviews = Dictionary(uniqueKeysWithValues: currentPage.folders.map { ($0.id, $0.previews) })
                updatePage(folders: folders.map { folder in
                    FocusMyFolder(id: folder.id, title: folder.title, mediaCount: folder.mediaCount,
                                  coverURL: folder.coverURL, previews: previousPreviews[folder.id] ?? [])
                })
            case .watchLater:
                let items = try await watchLaterService.fetchList().items
                guard isCurrent(requestID, version: version) else { throw CancellationError() }
                updatePage(watchLater: items)
            case .previews: break
            }
            sectionStates[section] = .loaded
            BiliPerformanceStore.shared.end(span)
            if section == .folders {
                await loadPreviews(requestID: requestID, version: version)
            }
        } catch {
            BiliPerformanceStore.shared.end(span, outcome: error is CancellationError ? .cancelled : .failure)
            guard isCurrent(requestID, version: version) else { return }
            if case FocusMyServiceError.loginRequired = error { expireSession(); return }
            if case FocusWatchLaterService.ServiceError.loginRequired = error { expireSession(); return }
            sectionStates[section] = .failed(displayError(error))
            if section == .folders { sectionStates[.previews] = .failed("请先重试收藏夹列表") }
        }
    }

    private enum PreviewResult: Sendable {
        case value(Int64, [FocusMyFavoriteItem]), failure(Int64, String), expired, cancelled
    }

    private nonisolated static func preview(service: FocusMyDataService, id: Int64) async -> PreviewResult {
        do { return .value(id, try await service.fetchFolderContents(mediaID: id, pageSize: 3)) }
        catch is CancellationError { return .cancelled }
        catch FocusMyServiceError.loginRequired { return .expired }
        catch { return .failure(id, error.localizedDescription) }
    }

    private func loadPreviews(requestID: UUID, version: UInt64) async {
        guard isCurrent(requestID, version: version), let page else { return }
        let folders = Array(page.folders.prefix(Self.previewFolderLimit))
        let span = BiliPerformanceStore.shared.begin(.favoritePreviews, correlationID: requestID)
        sectionStates[.previews] = .loading
        previewErrors.removeAll()
        await withTaskGroup(of: PreviewResult.self) { group in
            var next = 0
            for folder in folders.prefix(Self.previewConcurrency) {
                next += 1
                group.addTask { [service] in await Self.preview(service: service, id: folder.id) }
            }
            for await result in group {
                guard isCurrent(requestID, version: version) else { group.cancelAll(); break }
                switch result {
                case let .value(id, items):
                    updatePage(folders: self.page?.folders.map { folder in
                        guard folder.id == id else { return folder }
                        return FocusMyFolder(id: id, title: folder.title, mediaCount: folder.mediaCount,
                                             coverURL: folder.coverURL, previews: items)
                    })
                case let .failure(id, message): previewErrors[id] = message
                case .expired: expireSession(); group.cancelAll()
                case .cancelled: break
                }
                if isCurrent(requestID, version: version), next < folders.count {
                    let id = folders[next].id
                    next += 1
                    group.addTask { [service] in await Self.preview(service: service, id: id) }
                }
            }
        }
        guard isCurrent(requestID, version: version) else {
            BiliPerformanceStore.shared.end(span, outcome: .cancelled)
            return
        }
        sectionStates[.previews] = previewErrors.isEmpty ? .loaded : .failed("部分收藏夹预览加载失败，列表仍可打开")
        BiliPerformanceStore.shared.end(span, outcome: previewErrors.isEmpty ? .success : .failure, count: folders.count)
    }
}

@MainActor
final class FocusHistoryViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loginRequired
        case failed(String)
        case loaded([FocusMyHistoryItem])
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isLoadingMore = false

    private let service: FocusMyDataService
    private var nextCursor: FocusHistoryCursor?
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    init(service: FocusMyDataService) {
        self.service = service
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
    }

    func suspend() {
        task?.cancel()
        task = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
        if case .loading = state {
            state = .idle
        }
    }

    func resetForSessionChange() {
        suspend()
        state = .idle
        nextCursor = nil
    }

    var navigationTitle: String {
        "播放历史"
    }

    func loadIfNeeded() {
        if case .loaded = state {
            return
        }
        guard case .loading = state else {
            reload()
            return
        }
    }

    func refreshForAppearance() {
        guard case .loading = state else {
            reload()
            return
        }
    }

    func reload() {
        suspend()
        task = Task { [weak self] in
            await self?.performLoad()
        }
    }

    func loadMoreIfNeeded(currentItemID: String) {
        guard case let .loaded(items) = state else {
            return
        }
        guard !isLoadingMore, let nextCursor else {
            return
        }
        guard let index = items.firstIndex(where: { $0.id == currentItemID }), index >= items.count - 6 else {
            return
        }

        isLoadingMore = true
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let page = try await service.fetchHistoryPage(pageSize: 20, cursor: nextCursor)
                guard !Task.isCancelled else {
                    return
                }

                var seen = Set<String>()
                let merged = (items + page.items).filter { seen.insert($0.id).inserted }
                self.nextCursor = page.nextCursor
                self.state = .loaded(merged)
            } catch {
                // 保留当前历史列表，下一次滚动或下拉刷新时继续尝试。
            }
            guard !Task.isCancelled else { return }
            self.isLoadingMore = false
        }
    }

    private func performLoad() async {
        state = .loading
        nextCursor = nil

        do {
            let page = try await service.fetchHistoryPage(pageSize: 20)
            guard !Task.isCancelled else {
                return
            }
            nextCursor = page.nextCursor
            state = .loaded(page.items)
        } catch let error as FocusMyServiceError {
            guard !Task.isCancelled else {
                return
            }
            switch error {
            case .loginRequired:
                state = .loginRequired
            case let .message(message):
                state = .failed(message)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }
}

@MainActor
final class FocusUserSpaceViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case failed(String)
        case loaded(FocusUserSpacePage)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isLoadingMoreVideos = false

    private let service: FocusUserSpaceService
    private var currentURL: URL?
    private var currentMID: Int64?
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    init(service: FocusUserSpaceService) {
        self.service = service
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
    }

    func suspend() {
        task?.cancel()
        task = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMoreVideos = false
        if case .loading = state {
            state = .idle
        }
    }

    var navigationTitle: String {
        if case let .loaded(page) = state, !page.profile.name.isEmpty {
            return page.profile.name
        }
        return "UP主空间"
    }

    var hasActiveLoadTask: Bool {
        task.map { !$0.isCancelled } ?? false
    }

    func open(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        currentURL = canonicalURL
        currentMID = Self.extractMID(from: canonicalURL)

        guard let currentMID else {
            state = .failed("UP 主空间地址无效")
            return
        }

        if case let .loaded(page) = state, page.profile.mid == currentMID {
            return
        }

        reload()
    }

    func loadIfNeeded() {
        guard currentMID != nil else {
            return
        }
        guard case .idle = state else {
            return
        }
        reload()
    }

    func reload() {
        guard let currentMID else {
            state = .failed("UP 主空间地址无效")
            return
        }

        task?.cancel()
        loadMoreTask?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(mid: currentMID)
        }
    }

    func loadMoreIfNeeded(currentVideoID: String) {
        guard
            let currentMID,
            case let .loaded(page) = state,
            shouldLoadMore(after: currentVideoID, in: page.videos),
            !isLoadingMoreVideos,
            let nextPage = page.nextVideoPage
        else {
            return
        }

        isLoadingMoreVideos = true
        let currentPage = page

        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let payload = try await service.fetchVideoPage(mid: currentMID, page: nextPage)
                guard !Task.isCancelled else {
                    return
                }

                var seen = Set(currentPage.videos.map(\.id))
                let mergedVideos = currentPage.videos + payload.items.filter { seen.insert($0.id).inserted }
                state = .loaded(
                    FocusUserSpacePage(
                        profile: currentPage.profile,
                        videos: mergedVideos,
                        collections: currentPage.collections,
                        articles: currentPage.articles,
                        nextVideoPage: payload.nextPage
                    )
                )
            } catch {
                guard !Task.isCancelled else {
                    return
                }
            }

            if !Task.isCancelled {
                isLoadingMoreVideos = false
            }
        }
    }

    private func performLoad(mid: Int64) async {
        isLoadingMoreVideos = false
        state = .loading

        do {
            let page = try await service.fetchPage(mid: mid)
            guard !Task.isCancelled else {
                return
            }
            state = .loaded(page)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func shouldLoadMore(after currentVideoID: String, in videos: [FocusUserSpaceVideo]) -> Bool {
        guard let currentIndex = videos.firstIndex(where: { $0.id == currentVideoID }) else {
            return false
        }
        return currentIndex >= max(videos.count - 4, 0)
    }

    private static func extractMID(from url: URL) -> Int64? {
        guard url.host?.lowercased() == "space.bilibili.com" else {
            return nil
        }

        guard let first = url.path.split(separator: "/").first else {
            return nil
        }

        let candidate = String(first)
        guard candidate.allSatisfy(\.isNumber) else {
            return nil
        }

        return Int64(candidate)
    }
}

@MainActor
final class FocusFavoriteFolderViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loginRequired
        case failed(String)
        case loaded(FocusMyFolder, [FocusMyFavoriteItem])
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isLoadingMore = false

    private let service: FocusMyDataService
    private var folder: FocusMyFolder?
    private var currentPage = 1
    private var hasMore = false
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    init(service: FocusMyDataService) {
        self.service = service
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
    }

    func loadIfNeeded() {
        guard folder != nil, case .idle = state else {
            return
        }
        reload()
    }

    func suspend() {
        task?.cancel()
        task = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
        if case .loading = state {
            state = .idle
        }
    }

    var navigationTitle: String {
        switch state {
        case let .loaded(folder, _):
            return folder.title
        default:
            return folder?.title ?? "收藏夹"
        }
    }

    func resetForSessionChange() {
        suspend()
        state = .idle
        folder = nil
        currentPage = 1
        hasMore = false
    }

    func open(_ folder: FocusMyFolder) {
        self.folder = folder
        reload()
    }

    func reload() {
        guard let folder else {
            return
        }
        suspend()
        task = Task { [weak self] in
            await self?.performLoad(folder: folder)
        }
    }

    func loadMoreIfNeeded(currentItemID: String) {
        guard case let .loaded(folder, items) = state else {
            return
        }
        guard hasMore, !isLoadingMore else {
            return
        }
        guard let index = items.firstIndex(where: { $0.id == currentItemID }), index >= items.count - 6 else {
            return
        }

        isLoadingMore = true
        let nextPage = currentPage + 1
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let pageItems = try await service.fetchFolderContents(mediaID: folder.id, page: nextPage)
                guard !Task.isCancelled else {
                    return
                }
                var seen = Set<String>()
                let merged = (items + pageItems).filter { seen.insert($0.id).inserted }
                currentPage = nextPage
                hasMore = pageItems.count >= 20
                state = .loaded(folder, merged)
            } catch {
                // 保留已加载结果。
            }
            guard !Task.isCancelled else { return }
            isLoadingMore = false
        }
    }

    private func performLoad(folder: FocusMyFolder) async {
        state = .loading
        currentPage = 1
        hasMore = false

        do {
            let items = try await service.fetchFolderContents(mediaID: folder.id, page: 1)
            guard !Task.isCancelled else {
                return
            }
            hasMore = items.count >= 20
            state = .loaded(folder, items)
        } catch let error as FocusMyServiceError {
            guard !Task.isCancelled else {
                return
            }
            switch error {
            case .loginRequired:
                state = .loginRequired
            case let .message(message):
                state = .failed(message)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }
}

@MainActor
final class FocusDynamicAuthorSettingsViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded([DynamicCard.Author])
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let service: FocusFollowingAuthorsService
    private let fallbackAuthors: [DynamicCard.Author]
    private var task: Task<Void, Never>?

    init(service: FocusFollowingAuthorsService, fallbackAuthors: [DynamicCard.Author] = []) {
        self.service = service
        self.fallbackAuthors = Self.deduplicatedAuthors(fallbackAuthors)
    }

    deinit {
        task?.cancel()
    }

    func loadIfNeeded() {
        guard case .idle = state else {
            return
        }
        reload()
    }

    func reload() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            state = .loading
            do {
                let authors = try await service.fetchFollowingAuthors()
                guard !Task.isCancelled else { return }
                state = .loaded(Self.mergedAuthors(primary: authors, fallback: fallbackAuthors))
            } catch {
                guard !Task.isCancelled else { return }
                if !fallbackAuthors.isEmpty {
                    state = .loaded(fallbackAuthors)
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private static func mergedAuthors(primary: [DynamicCard.Author], fallback: [DynamicCard.Author]) -> [DynamicCard.Author] {
        deduplicatedAuthors(primary + fallback)
    }

    private static func deduplicatedAuthors(_ authors: [DynamicCard.Author]) -> [DynamicCard.Author] {
        var seen = Set<String>()
        var result: [DynamicCard.Author] = []
        result.reserveCapacity(authors.count)

        for author in authors {
            let normalizedName = author.name.nilIfBlank ?? "UP主"
            let normalized = DynamicCard.Author(mid: author.mid, name: normalizedName, avatarURL: author.avatarURL)
            let key = normalized.filterIdentity
            guard seen.insert(key).inserted else {
                continue
            }
            result.append(normalized)
        }

        return result
    }
}

final class FocusFollowingAuthorsService: @unchecked Sendable {
    enum ServiceError: Error, LocalizedError {
        case loginRequired
        case invalidResponse
        case message(String)

        var errorDescription: String? {
            switch self {
            case .loginRequired:
                return "需要登录"
            case .invalidResponse:
                return "关注列表返回无效数据"
            case let .message(message):
                return message
            }
        }
    }

    private let cookieProvider: WebViewCookieSnapshotProvider
    private let session: URLSession

    init(cookieProvider: WebViewCookieSnapshotProvider) {
        self.cookieProvider = cookieProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 16
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func fetchFollowingAuthors() async throws -> [DynamicCard.Author] {
        let nav = try await requestObject(urlString: "https://api.bilibili.com/x/web-interface/nav", referer: "https://www.bilibili.com/")
        guard nav.intValue(at: "code") == 0, let mid = nav.int64Value(at: "data", "mid"), mid > 0 else {
            throw ServiceError.loginRequired
        }

        var aggregated: [DynamicCard.Author] = []
        var seen = Set<String>()

        if let allFollowings = try? await fetchAllFollowingAuthors(mid: mid), !allFollowings.isEmpty {
            for author in allFollowings {
                let key = author.filterIdentity
                guard seen.insert(key).inserted else {
                    continue
                }
                aggregated.append(author)
            }
        }

        let pageSize = FocusFollowingAuthorsPagination.pageSize
        var page = 1
        var expectedTotal: Int?
        var fetchedFollowingCount = 0

        while page <= FocusFollowingAuthorsPagination.maxPages {
            let root: [String: Any]
            do {
                root = try await requestObject(
                    urlString: "https://api.bilibili.com/x/relation/followings?vmid=\(mid)&pn=\(page)&ps=\(pageSize)&order=desc&order_type=attention",
                    referer: "https://space.bilibili.com/\(mid)/fans/follow"
                )
            } catch {
                if aggregated.isEmpty {
                    throw error
                }
                break
            }
            if root.intValue(at: "code") == -101 {
                throw ServiceError.loginRequired
            }
            guard root.intValue(at: "code") == 0 else {
                if !aggregated.isEmpty {
                    break
                }
                throw ServiceError.message(root.stringValue(at: "message") ?? "关注列表加载失败")
            }

            if expectedTotal == nil {
                expectedTotal = root.intValue(at: "data", "total")
            }

            let pageAuthors = (root.arrayValue(at: "data", "list") ?? []).compactMap(Self.makeAuthor(from:))
            fetchedFollowingCount += pageAuthors.count
            for author in pageAuthors {
                let key = author.filterIdentity
                guard seen.insert(key).inserted else {
                    continue
                }
                aggregated.append(author)
            }

            guard FocusFollowingAuthorsPagination.shouldLoadNextPage(
                currentPage: page,
                receivedCount: pageAuthors.count,
                fetchedCount: fetchedFollowingCount,
                expectedTotal: expectedTotal
            ) else {
                break
            }
            page += 1
        }

        return aggregated
    }

    private func fetchAllFollowingAuthors(mid: Int64) async throws -> [DynamicCard.Author] {
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/web-interface/attentions?mid=\(mid)",
            referer: "https://space.bilibili.com/\(mid)/fans/follow"
        )
        if root.intValue(at: "code") == -101 {
            throw ServiceError.loginRequired
        }
        guard root.intValue(at: "code") == 0 else {
            throw ServiceError.message(root.stringValue(at: "message") ?? "关注列表加载失败")
        }

        let list = root.arrayValue(at: "data", "list")
            ?? root.arrayValue(at: "data")
            ?? root.arrayValue(at: "list")
            ?? []
        return list.compactMap(Self.makeAuthor(from:))
    }

    private static func makeAuthor(from item: [String: Any]) -> DynamicCard.Author? {
        let itemMid = item.int64Value(at: "mid") ?? item.int64Value(at: "uid") ?? 0
        let name = item.stringValue(at: "uname")?.nilIfBlank ?? item.stringValue(at: "name")?.nilIfBlank ?? "UP主"
        let avatarURL = URL(string: FocusMyDataService.normalizedURLString(item.stringValue(at: "face")) ?? "")
        if itemMid <= 0, name == "UP主" {
            return nil
        }
        return DynamicCard.Author(mid: itemMid, name: name, avatarURL: avatarURL)
    }

    private func requestObject(urlString: String, referer: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        request.setValue(FocusNativePageAugmentService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        let cookies = await cookieProvider.loadCookies()
        request = CookieRequestPolicy.attach(cookies: cookies, to: request)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw ServiceError.invalidResponse
        }
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw ServiceError.invalidResponse
        }
        return object
    }
}

enum FocusFollowingAuthorsPagination {
    static let pageSize = 50
    static let maxPages = 200

    static func shouldLoadNextPage(
        currentPage: Int,
        receivedCount: Int,
        fetchedCount: Int,
        expectedTotal: Int?
    ) -> Bool {
        guard currentPage < maxPages, receivedCount > 0 else {
            return false
        }
        if let expectedTotal {
            return fetchedCount < expectedTotal
        }
        return receivedCount >= pageSize
    }
}

extension DynamicCard.Author {
    var filterIdentity: String {
        mid > 0 ? "mid:\(mid)" : "name:\(name)"
    }
}

actor FocusUserSpaceService {
    private struct ProfileSeed {
        let mid: Int64
        let name: String
        let avatarURL: URL?
        let sign: String
        let level: Int
        let videoCount: Int
        let articleCount: Int
    }

    struct VideoPayload {
        let totalCount: Int
        let items: [FocusUserSpaceVideo]
        let nextPage: Int?
    }

    private struct ArticlePayload {
        let totalCount: Int
        let items: [FocusUserSpaceArticle]
    }

    private let cookieProvider: WebViewCookieSnapshotProvider
    private let session: URLSession
    private var cachedWbiKey: String?
    private var cachedWbiExpiration = Date.distantPast

    init(cookieProvider: WebViewCookieSnapshotProvider) {
        self.cookieProvider = cookieProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: configuration)
    }

    func fetchPage(mid: Int64) async throws -> FocusUserSpacePage {
        async let profileSeedTask = fetchProfileSeed(mid: mid)
        async let relationTask = fetchRelation(mid: mid)
        async let videoTask = fetchVideos(mid: mid)
        async let collectionTask = fetchCollections(mid: mid)
        async let articleTask = fetchArticles(mid: mid)

        let profileSeed = try await profileSeedTask
        let relation = (try? await relationTask) ?? (following: Int64(0), followers: Int64(0))
        let videos = (try? await videoTask) ?? VideoPayload(totalCount: 0, items: [], nextPage: nil)
        let collections = (try? await collectionTask) ?? []
        let articles = (try? await articleTask) ?? ArticlePayload(totalCount: 0, items: [])

        let profile = FocusUserSpaceProfile(
            mid: profileSeed.mid,
            name: profileSeed.name,
            avatarURL: profileSeed.avatarURL,
            sign: profileSeed.sign,
            level: profileSeed.level,
            following: relation.following,
            followers: relation.followers,
            videoCount: max(profileSeed.videoCount, videos.totalCount),
            articleCount: max(profileSeed.articleCount, articles.totalCount)
        )

        return FocusUserSpacePage(
            profile: profile,
            videos: videos.items,
            collections: collections,
            articles: articles.items,
            nextVideoPage: videos.nextPage
        )
    }

    private func fetchProfileSeed(mid: Int64) async throws -> ProfileSeed {
        let query = try await signedWbiQuery(
            parameters: [
                "mid": String(mid),
            ],
            referer: "https://space.bilibili.com/\(mid)"
        )
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/space/wbi/acc/info?\(query)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        let code = root.intValue(at: "code") ?? 0
        guard code == 0 else {
            throw URLError(.badServerResponse)
        }

        let data = root.dictionaryValue(at: "data") ?? root
        return ProfileSeed(
            mid: data.int64Value(at: "mid") ?? mid,
            name: data.stringValue(at: "name")?.nilIfBlank ?? data.stringValue(at: "uname")?.nilIfBlank ?? "UP主",
            avatarURL: URL(string: Self.normalizedURLString(data.stringValue(at: "face")) ?? ""),
            sign: data.stringValue(at: "sign")?.nilIfBlank ?? "",
            level: data.intValue(at: "level") ?? data.intValue(at: "level_info", "current_level") ?? 0,
            videoCount: data.intValue(at: "archive_count") ?? data.intValue(at: "archive") ?? 0,
            articleCount: data.intValue(at: "article_count") ?? data.intValue(at: "article") ?? 0
        )
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

    func fetchVideoPage(mid: Int64, page: Int, pageSize: Int = 12) async throws -> VideoPayload {
        let query = try await signedWbiQuery(
            parameters: [
                "mid": String(mid),
                "ps": String(pageSize),
                "pn": String(page),
                "tid": "0",
                "keyword": "",
                "order": "pubdate",
                "order_avoided": "true",
                "platform": "web",
            ],
            referer: "https://space.bilibili.com/\(mid)"
        )
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/space/wbi/arc/search?\(query)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        let code = root.intValue(at: "code") ?? 0
        guard code == 0 else {
            return VideoPayload(totalCount: 0, items: [], nextPage: nil)
        }

        let data = root.dictionaryValue(at: "data") ?? root
        let list = data.dictionaryValue(at: "list") ?? data
        let items = list.arrayValue(at: "vlist") ?? data.arrayValue(at: "vlist") ?? []
        let totalCount = data.intValue(at: "page", "count")
            ?? data.intValue(at: "page", "total")
            ?? items.count
        let nextPage = items.isEmpty
            ? nil
            : ((page * pageSize) < totalCount || items.count >= pageSize ? page + 1 : nil)

        return VideoPayload(
            totalCount: totalCount,
            items: items.compactMap { item in
                let bvid = item.stringValue(at: "bvid")?.nilIfBlank ?? ""
                guard !bvid.isEmpty else {
                    return nil
                }

                let createdAt = item.int64Value(at: "created") ?? item.int64Value(at: "pubdate") ?? 0
                return FocusUserSpaceVideo(
                    id: bvid,
                    bvid: bvid,
                    title: Self.cleanText(item.stringValue(at: "title")) .nilIfBlank ?? "视频",
                    coverURL: URL(string: Self.normalizedURLString(item.stringValue(at: "pic")) ?? ""),
                    playText: Self.formatCount(item.int64Value(at: "play") ?? 0),
                    durationText: Self.formatVideoLength(
                        item.stringValue(at: "length"),
                        seconds: item.int64Value(at: "duration")
                    ),
                    publishText: Self.formatDate(createdAt)
                )
            },
            nextPage: nextPage
        )
    }

    private func fetchVideos(mid: Int64) async throws -> VideoPayload {
        try await fetchVideoPage(mid: mid, page: 1)
    }

    private func fetchCollections(mid: Int64) async throws -> [FocusUserSpaceCollection] {
        let query = try await signedWbiQuery(
            parameters: [
                "mid": String(mid),
                "page_num": "1",
                "page_size": "10",
            ],
            referer: "https://space.bilibili.com/\(mid)"
        )
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/polymer/web-space/seasons_series_list?\(query)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        let code = root.intValue(at: "code") ?? 0
        guard code == 0 else {
            return []
        }

        let data = root.dictionaryValue(at: "data") ?? root
        let itemsLists = data.dictionaryValue(at: "items_lists") ?? data
        let seasons = itemsLists.arrayValue(at: "seasons_list") ?? []
        let series = itemsLists.arrayValue(at: "series_list") ?? []

        let mappedSeasons = seasons.compactMap { item in
            mapCollection(item: item, mid: mid, kind: .season)
        }
        let mappedSeries = series.compactMap { item in
            mapCollection(item: item, mid: mid, kind: .series)
        }

        return mappedSeasons + mappedSeries
    }

    private func fetchArticles(mid: Int64) async throws -> ArticlePayload {
        let query = try await signedWbiQuery(
            parameters: [
                "mid": String(mid),
                "pn": "1",
                "ps": "6",
                "sort": "publish_time",
            ],
            referer: "https://space.bilibili.com/\(mid)"
        )
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/space/wbi/article?\(query)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        let code = root.intValue(at: "code") ?? 0
        guard code == 0 else {
            return ArticlePayload(totalCount: 0, items: [])
        }

        let data = root.dictionaryValue(at: "data") ?? root
        let items = data.arrayValue(at: "articles") ?? data.arrayValue(at: "list") ?? []
        let totalCount = data.intValue(at: "count")
            ?? data.intValue(at: "page", "count")
            ?? items.count

        return ArticlePayload(
            totalCount: totalCount,
            items: items.compactMap { item in
                let id = item.int64Value(at: "id")
                    ?? item.int64Value(at: "cvid")
                    ?? item.int64Value(at: "cv")
                guard let id else {
                    return nil
                }

                let fallbackURL = URL(string: "https://www.bilibili.com/read/cv\(id)")!
                let targetURL = URL(string: Self.normalizedURLString(item.stringValue(at: "share_url")) ?? "")
                    ?? fallbackURL
                return FocusUserSpaceArticle(
                    id: String(id),
                    title: Self.cleanText(item.stringValue(at: "title")).nilIfBlank ?? "专栏",
                    summary: Self.cleanText(
                        item.stringValue(at: "summary")
                            ?? item.stringValue(at: "description")
                    ),
                    coverURL: URL(string: Self.normalizedURLString(
                        item.stringValue(at: "banner_url")
                            ?? item.stringValue(at: "image_url")
                            ?? Self.firstString(in: item["image_urls"])
                            ?? Self.firstString(in: item["covers"])
                    ) ?? ""),
                    publishText: Self.formatDate(
                        item.int64Value(at: "publish_time_seconds")
                            ?? item.int64Value(at: "publish_time")
                            ?? item.int64Value(at: "ctime")
                            ?? 0
                    ),
                    viewText: Self.formatCount(
                        item.int64Value(at: "stats", "view")
                            ?? item.int64Value(at: "view")
                            ?? 0
                    ),
                    targetURL: targetURL
                )
            }
        )
    }

    func fetchCollectionPage(
        collection: FocusUserSpaceCollection,
        page: Int,
        pageSize: Int = 20
    ) async throws -> FocusUserCollectionPage {
        switch collection.kind {
        case .season:
            let query = try await signedWbiQuery(
                parameters: [
                    "mid": String(collection.ownerMID),
                    "season_id": String(collection.rawID),
                    "sort_reverse": "false",
                    "page_num": String(page),
                    "page_size": String(pageSize),
                ],
                referer: "https://space.bilibili.com/\(collection.ownerMID)"
            )
            let root = try await requestObject(
                urlString: "https://api.bilibili.com/x/polymer/web-space/seasons_archives_list?\(query)",
                referer: "https://space.bilibili.com/\(collection.ownerMID)"
            )
            return parseCollectionPage(root: root, collection: collection, page: page, pageSize: pageSize)

        case .series:
            let query = try await signedWbiQuery(
                parameters: [
                    "mid": String(collection.ownerMID),
                    "series_id": String(collection.rawID),
                    "pn": String(page),
                    "ps": String(pageSize),
                    "sort": "desc",
                ],
                referer: "https://space.bilibili.com/\(collection.ownerMID)"
            )
            let root = try await requestObject(
                urlString: "https://api.bilibili.com/x/series/archives?\(query)",
                referer: "https://space.bilibili.com/\(collection.ownerMID)"
            )
            return parseCollectionPage(root: root, collection: collection, page: page, pageSize: pageSize)
        }
    }

    private func parseCollectionPage(
        root: [String: Any],
        collection: FocusUserSpaceCollection,
        page: Int,
        pageSize: Int
    ) -> FocusUserCollectionPage {
        let code = root.intValue(at: "code") ?? 0
        guard code == 0 else {
            return FocusUserCollectionPage(collection: collection, videos: [], nextPage: nil)
        }

        let data = root.dictionaryValue(at: "data") ?? root
        let items = data.arrayValue(at: "archives")
            ?? data.dictionaryValue(at: "list")?.arrayValue(at: "archives")
            ?? data.arrayValue(at: "items")
            ?? []
        let videos = items.compactMap(Self.mapUserSpaceVideo(item:))
        let totalCount = data.intValue(at: "page", "total")
            ?? data.intValue(at: "page", "count")
            ?? data.intValue(at: "meta", "total")
            ?? collection.itemCount
        let nextPage = videos.isEmpty
            ? nil
            : ((page * pageSize) < totalCount || videos.count >= pageSize ? page + 1 : nil)

        return FocusUserCollectionPage(
            collection: collection,
            videos: videos,
            nextPage: nextPage
        )
    }

    private func mapCollection(
        item: [String: Any],
        mid: Int64,
        kind: FocusUserSpaceCollection.Kind
    ) -> FocusUserSpaceCollection? {
        let meta = item.dictionaryValue(at: "meta") ?? item
        let rawID = kind == .season
            ? meta.int64Value(at: "season_id")
            : meta.int64Value(at: "series_id")
        guard let rawID else {
            return nil
        }

        let title = meta.stringValue(at: "name")?.nilIfBlank
            ?? meta.stringValue(at: "title")?.nilIfBlank
            ?? kind.title
        let count = meta.intValue(at: "total")
            ?? meta.intValue(at: "archives_count")
            ?? meta.intValue(at: "media_count")
            ?? item.arrayValue(at: "archives")?.count
            ?? 0
        let updateTime = meta.int64Value(at: "mtime")
            ?? meta.int64Value(at: "ctime")
            ?? meta.int64Value(at: "pub_time")
            ?? 0

        return FocusUserSpaceCollection(
            id: "\(kind.rawValue)-\(rawID)",
            ownerMID: mid,
            rawID: rawID,
            kind: kind,
            title: title,
            subtitle: count > 0 ? "\(kind.title) · \(count) 个视频" : kind.title,
            description: meta.stringValue(at: "description")?.nilIfBlank
                ?? meta.stringValue(at: "desc")?.nilIfBlank
                ?? meta.stringValue(at: "intro")?.nilIfBlank
                ?? "",
            badgeText: updateTime > 0 ? "更新于 \(Self.formatDate(updateTime))" : kind.title,
            coverURL: URL(string: Self.normalizedURLString(
                meta.stringValue(at: "cover")
                    ?? meta.stringValue(at: "image")
            ) ?? ""),
            itemCount: count
        )
    }

    private static func mapUserSpaceVideo(item: [String: Any]) -> FocusUserSpaceVideo? {
        let bvid = item.stringValue(at: "bvid")?.nilIfBlank ?? ""
        guard !bvid.isEmpty else {
            return nil
        }

        let createdAt = item.int64Value(at: "created")
            ?? item.int64Value(at: "pubdate")
            ?? item.int64Value(at: "ptime")
            ?? item.int64Value(at: "ctime")
            ?? 0
        let playValue = item.int64Value(at: "play")
            ?? item.int64Value(at: "stat", "view")
            ?? 0

        return FocusUserSpaceVideo(
            id: bvid,
            bvid: bvid,
            title: Self.cleanText(item.stringValue(at: "title")).nilIfBlank ?? "视频",
            coverURL: URL(string: Self.normalizedURLString(
                item.stringValue(at: "pic")
                    ?? item.stringValue(at: "cover")
            ) ?? ""),
            playText: Self.formatCount(playValue),
            durationText: Self.formatVideoLength(
                item.stringValue(at: "length"),
                seconds: item.int64Value(at: "duration")
            ),
            publishText: Self.formatDate(createdAt)
        )
    }

    private func requestObject(urlString: String, referer: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let data = try await requestData(url: url, referer: referer)
        let rawObject = try JSONSerialization.jsonObject(with: data)
        guard let object = rawObject as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return object
    }

    private func requestData(url: URL, referer: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        request.setValue(FocusNativePageAugmentService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")

        let cookies = await cookieProvider.loadCookies()
        request = CookieRequestPolicy.attach(cookies: cookies, to: request)

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
            let sanitizedValue = Self.sanitizeWBIValue(items[key] ?? "")
            return "\(key)=\(sanitizedValue)"
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

    private static func cleanText(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }

        return raw.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
    }

    private static func formatVideoLength(_ raw: String?, seconds: Int64?) -> String {
        if let raw = raw?.nilIfBlank {
            return raw
        }
        guard let seconds else {
            return ""
        }
        return formatDuration(seconds)
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

    private static func formatDate(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return ""
        }

        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatCount(_ value: Int64) -> String {
        guard value > 0 else {
            return ""
        }

        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }

    private static func firstString(in rawValue: Any?) -> String? {
        if let string = rawValue as? String, !string.isEmpty {
            return string
        }
        if let array = rawValue as? [Any] {
            for item in array {
                if let string = item as? String, !string.isEmpty {
                    return string
                }
                if let dictionary = item as? [String: Any] {
                    if let string = dictionary.stringValue(at: "url")?.nilIfBlank {
                        return string
                    }
                    if let string = dictionary.stringValue(at: "src")?.nilIfBlank {
                        return string
                    }
                }
            }
        }
        return nil
    }

    private static func normalizedURLString(_ raw: String?) -> String? {
        guard let raw = raw?.nilIfBlank else {
            return nil
        }
        if raw.lowercased().hasPrefix("http://") {
            return "https://" + raw.dropFirst("http://".count)
        }
        if raw.hasPrefix("//") {
            return "https:\(raw)"
        }
        return raw
    }

    private static func sanitizeWBIValue(_ value: String) -> String {
        value.filter { character in
            !"!'()*".contains(character)
        }
    }

    private static func md5Hex(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let wbiMixinTable: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32,
        15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19,
        29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61,
        26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63,
        57, 62, 11, 36, 20, 34, 44, 52,
    ]
}

@MainActor
final class FocusUserCollectionViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case failed(String)
        case loaded(FocusUserCollectionPage)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isLoadingMoreVideos = false

    private let service: FocusUserSpaceService
    private var currentCollection: FocusUserSpaceCollection?
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    init(service: FocusUserSpaceService) {
        self.service = service
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
    }

    func suspend() {
        task?.cancel()
        task = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMoreVideos = false
        if case .loading = state {
            state = .idle
        }
    }

    var navigationTitle: String {
        switch state {
        case let .loaded(page):
            return page.collection.title
        default:
            return currentCollection?.title ?? "合集"
        }
    }

    func open(_ collection: FocusUserSpaceCollection) {
        currentCollection = collection
        if case let .loaded(page) = state, page.collection.id == collection.id {
            return
        }
        reload()
    }

    func loadIfNeeded() {
        guard currentCollection != nil else {
            return
        }
        guard case .idle = state else {
            return
        }
        reload()
    }

    func reload() {
        guard let currentCollection else {
            state = .failed("合集信息无效")
            return
        }

        task?.cancel()
        loadMoreTask?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(collection: currentCollection)
        }
    }

    func loadMoreIfNeeded(currentVideoID: String) {
        guard
            let collection = currentCollection,
            case let .loaded(page) = state,
            shouldLoadMore(after: currentVideoID, in: page.videos),
            !isLoadingMoreVideos,
            let nextPage = page.nextPage
        else {
            return
        }

        isLoadingMoreVideos = true
        let currentPage = page

        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let payload = try await service.fetchCollectionPage(collection: collection, page: nextPage)
                guard !Task.isCancelled else {
                    return
                }

                var seen = Set(currentPage.videos.map(\.id))
                let mergedVideos = currentPage.videos + payload.videos.filter { seen.insert($0.id).inserted }
                state = .loaded(
                    FocusUserCollectionPage(
                        collection: currentPage.collection,
                        videos: mergedVideos,
                        nextPage: payload.nextPage
                    )
                )
            } catch {
                guard !Task.isCancelled else {
                    return
                }
            }

            if !Task.isCancelled {
                isLoadingMoreVideos = false
            }
        }
    }

    private func performLoad(collection: FocusUserSpaceCollection) async {
        isLoadingMoreVideos = false
        state = .loading

        do {
            let page = try await service.fetchCollectionPage(collection: collection, page: 1)
            guard !Task.isCancelled else {
                return
            }
            state = .loaded(page)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func shouldLoadMore(after currentVideoID: String, in videos: [FocusUserSpaceVideo]) -> Bool {
        guard let currentIndex = videos.firstIndex(where: { $0.id == currentVideoID }) else {
            return false
        }
        return currentIndex >= max(videos.count - 4, 0)
    }
}

@MainActor
final class FocusArticleViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loginRequired
        case failed(String)
        case loaded(FocusArticlePage)
    }

    @Published private(set) var state: State = .idle

    private let service: FocusArticleService
    private var currentURL: URL?
    private var task: Task<Void, Never>?

    init(service: FocusArticleService) {
        self.service = service
    }

    deinit {
        task?.cancel()
    }

    func suspend() {
        task?.cancel()
        task = nil
        if case .loading = state {
            state = .idle
        }
    }

    var navigationTitle: String {
        if case let .loaded(page) = state, !page.title.isEmpty {
            return page.title
        }
        return "专栏"
    }

    var originalURL: URL? {
        currentURL.flatMap { FocusArticleRouting.canonicalURL(for: $0) }
    }

    func open(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard currentURL != canonicalURL || !isContentLoaded else {
            return
        }

        currentURL = canonicalURL
        task?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(url: canonicalURL)
        }
    }

    func loadIfNeeded() {
        guard currentURL != nil else {
            return
        }
        guard case .idle = state else {
            return
        }
        reload()
    }

    func reload() {
        guard let currentURL else {
            state = .idle
            return
        }

        task?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(url: currentURL)
        }
    }

    private var isContentLoaded: Bool {
        if case .loaded = state {
            return true
        }
        return false
    }

    private func performLoad(url: URL) async {
        state = .loading

        do {
            let page = try await service.fetchPage(for: url)
            guard !Task.isCancelled else {
                return
            }
            state = .loaded(page)
        } catch let error as FocusArticleService.ServiceError {
            guard !Task.isCancelled else {
                return
            }
            switch error {
            case .loginRequired:
                state = .loginRequired
            case let .message(message):
                state = .failed(message)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }
}

final class FocusArticleService: @unchecked Sendable {
    enum ServiceError: Error {
        case loginRequired
        case message(String)
    }

    private let cookieProvider: WebViewCookieSnapshotProvider
    private let session: URLSession

    init(cookieProvider: WebViewCookieSnapshotProvider) {
        self.cookieProvider = cookieProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: configuration)
    }

    func fetchPage(for url: URL) async throws -> FocusArticlePage {
        guard let cvid = Self.extractCVID(from: url) else {
            throw ServiceError.message("专栏地址无效")
        }

        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/article/view?id=\(cvid)&mobi_app=pc&from=web",
            referer: url.absoluteString
        )
        let code = root.intValue(at: "code") ?? -1
        if code == -101 {
            throw ServiceError.loginRequired
        }
        guard code == 0, let data = root.dictionaryValue(at: "data") else {
            throw ServiceError.message(root.stringValue(at: "message") ?? "专栏加载失败")
        }

        let authorData = data.dictionaryValue(at: "author") ?? [:]
        let statsData = data.dictionaryValue(at: "stats") ?? [:]
        var tags = (data.arrayValue(at: "tags") ?? []).compactMap {
            $0.stringValue(at: "name")?.nilIfBlank
        }
        if let keywords = data.stringValue(at: "keywords") {
            tags.append(contentsOf: keywords.split(whereSeparator: { $0 == "," || $0 == "，" }).map(String.init))
        }
        if let category = data.stringValue(at: "category", "name")?.nilIfBlank {
            tags.append(category)
        }
        tags = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        let bannerURLString = Self.normalizedURLString(
            data.stringValue(at: "banner_url")
                ?? Self.firstString(in: data["origin_image_urls"])
                ?? Self.firstString(in: data["image_urls"])
        )
        let blocks = FocusMyDataService.parseArticleContent(data.stringValue(at: "content") ?? "")
        guard !blocks.isEmpty else {
            throw ServiceError.message("专栏正文为空或暂时无法解析")
        }
        let originalURL = URL(string: "https://www.bilibili.com/read/cv\(cvid)")!

        return FocusArticlePage(
            cvid: cvid,
            title: data.stringValue(at: "title")?.nilIfBlank ?? "专栏",
            author: FocusArticleAuthor(
                mid: authorData.int64Value(at: "mid") ?? data.int64Value(at: "mid") ?? 0,
                name: authorData.stringValue(at: "name")?.nilIfBlank ?? data.stringValue(at: "author_name")?.nilIfBlank ?? "作者",
                avatarURL: URL(string: Self.normalizedURLString(authorData.stringValue(at: "face") ?? data.stringValue(at: "author_face")) ?? "")
            ),
            publishTime: data.int64Value(at: "publish_time") ?? data.int64Value(at: "ctime") ?? 0,
            stats: FocusArticleStats(
                views: statsData.int64Value(at: "view") ?? 0,
                likes: statsData.int64Value(at: "like") ?? 0,
                coins: statsData.int64Value(at: "coin") ?? 0,
                favorites: statsData.int64Value(at: "favorite") ?? 0,
                comments: statsData.int64Value(at: "reply") ?? 0
            ),
            bannerURL: URL(string: bannerURLString ?? ""),
            tags: tags,
            blocks: blocks,
            originalURL: originalURL
        )
    }

    private func requestObject(urlString: String, referer: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw ServiceError.message("请求地址无效")
        }
        let data = try await requestData(url: url, referer: referer)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw ServiceError.message("接口返回无效数据")
        }
        return object
    }

    private func requestData(url: URL, referer: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.httpMethod = "GET"
        request.setValue(FocusNativePageAugmentService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")

        let cookies = await cookieProvider.loadCookies()
        request = CookieRequestPolicy.attach(cookies: cookies, to: request)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw ServiceError.message("网络请求失败")
        }
        return data
    }

    private static func extractCVID(from url: URL) -> Int64? {
        FocusArticleRouting.extractCVID(from: url)
    }

    private static func firstString(in rawValue: Any?) -> String? {
        if let string = rawValue as? String, !string.isEmpty {
            return string
        }
        if let array = rawValue as? [Any] {
            for item in array {
                if let string = item as? String, !string.isEmpty {
                    return string
                }
                if let dictionary = item as? [String: Any] {
                    if let string = dictionary.stringValue(at: "url")?.nilIfBlank {
                        return string
                    }
                    if let string = dictionary.stringValue(at: "src")?.nilIfBlank {
                        return string
                    }
                }
            }
        }
        return nil
    }

    private static func normalizedURLString(_ raw: String?) -> String? {
        guard let raw = raw?.nilIfBlank else {
            return nil
        }
        if raw.lowercased().hasPrefix("http://") {
            return "https://" + raw.dropFirst("http://".count)
        }
        if raw.hasPrefix("//") {
            return "https:\(raw)"
        }
        return raw
    }
}

@MainActor
final class FocusOpusDetailViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loginRequired
        case failed(String)
        case loaded(FocusOpusDetailPage)
    }

    @Published private(set) var state: State = .idle

    private let detailService: FocusOpusDetailService
    private let augmentService: FocusNativePageAugmentService
    private var currentURL: URL?
    private var task: Task<Void, Never>?

    init(
        detailService: FocusOpusDetailService,
        augmentService: FocusNativePageAugmentService
    ) {
        self.detailService = detailService
        self.augmentService = augmentService
    }

    deinit {
        task?.cancel()
    }

    func suspend() {
        task?.cancel()
        task = nil
        if case .loading = state {
            state = .idle
        }
    }

    var navigationTitle: String {
        "图文动态"
    }

#if DEBUG
    // Exercise the real rich-detail layout without credentials or live APIs.
    func installFixtureDetail(_ page: FocusOpusDetailPage) {
        precondition(FocusTestRuntime.isRunningFixtures)
        suspend()
        state = .loaded(page)
    }
#endif

    func open(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard currentURL != canonicalURL || !isContentLoaded else {
            return
        }
        currentURL = canonicalURL
        task?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(url: canonicalURL)
        }
    }

    func reload() {
        guard let currentURL else {
            state = .idle
            return
        }
        task?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(url: currentURL)
        }
    }

    private var isContentLoaded: Bool {
        if case .loaded = state {
            return true
        }
        return false
    }

    private func performLoad(url: URL) async {
        state = .loading

        do {
            async let detail = detailService.fetchDetail(for: url)
            async let commentsPayload = augmentService.loadPayload(for: url, kind: .opus)

            let detailValue = try await detail
            let comments = await Self.extractComments(from: commentsPayload)

            guard !Task.isCancelled else {
                return
            }
            state = .loaded(
                FocusOpusDetailPage(
                    id: detailValue.id,
                    author: detailValue.author,
                    publishTime: detailValue.publishTime,
                    paragraphs: detailValue.paragraphs,
                    comments: comments
                )
            )
        } catch let error as FocusOpusDetailService.ServiceError {
            guard !Task.isCancelled else {
                return
            }
            switch error {
            case .loginRequired:
                state = .loginRequired
            case let .message(message):
                state = .failed(message)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    private static func extractComments(
        from payload: FocusNativePageAugmentPayload?
    ) async -> [FocusNativeCommentPayload] {
        guard let payload else {
            return []
        }
        switch payload {
        case let .opus(data):
            return data.comments
        case .video:
            return []
        }
    }
}

final class FocusOpusDetailService: @unchecked Sendable {
    enum ServiceError: Error {
        case loginRequired
        case message(String)
    }

    private let cookieProvider: WebViewCookieSnapshotProvider
    private let session: URLSession

    init(cookieProvider: WebViewCookieSnapshotProvider) {
        self.cookieProvider = cookieProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 16
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func fetchDetail(for url: URL) async throws -> FocusOpusDetailContent {
        guard let opusID = Self.extractOpusID(from: url) else {
            throw ServiceError.message("图文 ID 无效")
        }

        let features = "onlyfansVote,onlyfansAssetsV2,decorationCard,htmlNewStyle,ugcDelete,editable,opusPrivateVisible"
        let detailURL = "https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail?id=\(opusID)&timezone_offset=-480&features=\(features)"
        let root = try await requestObject(urlString: detailURL, referer: url.absoluteString)
        let code = root.intValue(at: "code") ?? -1
        if code == -101 {
            throw ServiceError.loginRequired
        }
        guard code == 0 else {
            throw ServiceError.message(root.stringValue(at: "message") ?? "图文详情加载失败")
        }

        if let item = root.dictionaryValue(at: "data", "item") {
            let basic = item.dictionaryValue(at: "basic") ?? [:]
            let modules = item.dictionaryValue(at: "modules") ?? [:]
            let authorModule = modules.dictionaryValue(at: "module_author") ?? [:]
            let paragraphs = parseParagraphs(modules: modules)
            if !paragraphs.isEmpty {
                return FocusOpusDetailContent(
                    id: basic.stringValue(at: "comment_id_str") ?? basic.stringValue(at: "rid_str") ?? opusID,
                    author: FocusOpusAuthor(
                        name: authorModule.stringValue(at: "name") ?? "用户",
                        mid: authorModule.int64Value(at: "mid") ?? 0,
                        avatarURL: URL(string: Self.normalizedURLString(authorModule.stringValue(at: "face")) ?? "")
                    ),
                    publishTime: authorModule.stringValue(at: "pub_time")
                        ?? authorModule.stringValue(at: "pub_time_text")
                        ?? "",
                    paragraphs: paragraphs
                )
            }
        }

        if let fallback = try await fetchFromDynamicDetail(opusID: opusID) {
            return fallback
        }

        throw ServiceError.message("未能解析图文内容")
    }

    private func fetchFromDynamicDetail(opusID: String) async throws -> FocusOpusDetailContent? {
        let urlString = "https://api.bilibili.com/x/polymer/web-dynamic/v1/detail?id=\(opusID)&features=itemOpusStyle&timezone_offset=-480"
        let root = try await requestObject(urlString: urlString, referer: "https://www.bilibili.com/opus/\(opusID)")
        let code = root.intValue(at: "code") ?? -1
        if code == -101 {
            throw ServiceError.loginRequired
        }
        guard code == 0 else {
            return nil
        }

        guard let item = root.dictionaryValue(at: "data", "item") else {
            return nil
        }

        let modules = item.dictionaryValue(at: "modules") ?? [:]
        let dynamic = modules.dictionaryValue(at: "module_dynamic")
        let forwardOrigin = item.dictionaryValue(at: "orig")
            ?? item.dictionaryValue(at: "origin")
            ?? dynamic?.dictionaryValue(at: "major", "archive")
        let originModules = forwardOrigin?.dictionaryValue(at: "modules")

        if let originModules,
           let forwarded = parseForwardedDetail(from: originModules, fallbackID: opusID)
        {
            return forwarded
        }

        guard let dynamic else {
            return nil
        }

        let author = modules.dictionaryValue(at: "module_author") ?? [:]
        let major = dynamic.dictionaryValue(at: "major")

        var blocks: [FocusOpusBlock] = []
        let richTextRuns = parseOpusTextNodes(
            dynamic.arrayValue(at: "desc", "rich_text_nodes")
                ?? dynamic.arrayValue(at: "desc", "rich_text_nodes_v2")
                ?? []
        )
        if !richTextRuns.isEmpty {
            blocks.append(.text(richTextRuns))
        } else if let text = dynamic.stringValue(at: "desc", "text") ?? major?.stringValue(at: "opus", "summary", "text"),
           let normalizedText = text.nilIfBlank
        {
            blocks.append(.text([.text(value: normalizedText)]))
        }

        var images: [FocusOpusImage] = []
        func appendPictures(from items: [[String: Any]], keys: [String]) {
            for item in items {
                let rawURL = keys.compactMap { item.stringValue(at: $0) }.first
                guard let rawURL else {
                    continue
                }
                let normalized = Self.normalizedURLString(rawURL)
                images.append(
                    FocusOpusImage(
                        id: normalized ?? UUID().uuidString,
                        url: normalized.flatMap(URL.init(string:)),
                        width: item.intValue(at: "width") ?? 0,
                        height: item.intValue(at: "height") ?? 0
                    )
                )
            }
        }

        if let pics = major?.arrayValue(at: "opus", "pics") {
            appendPictures(from: pics, keys: ["url", "src"])
        }
        if let drawItems = major?.arrayValue(at: "draw", "items") {
            appendPictures(from: drawItems, keys: ["src", "url"])
        }
        if !images.isEmpty {
            blocks.append(.image(images))
        }

        guard !blocks.isEmpty else {
            return nil
        }

        return FocusOpusDetailContent(
            id: opusID,
            author: FocusOpusAuthor(
                name: author.stringValue(at: "name") ?? "用户",
                mid: author.int64Value(at: "mid") ?? 0,
                avatarURL: URL(string: Self.normalizedURLString(author.stringValue(at: "face")) ?? "")
            ),
            publishTime: author.stringValue(at: "pub_time")
                ?? author.stringValue(at: "pub_time_text")
                ?? "",
            paragraphs: [FocusOpusParagraph(blocks: blocks)]
        )
    }

    private func parseForwardedDetail(from modules: [String: Any], fallbackID: String) -> FocusOpusDetailContent? {
        let author = modules.dictionaryValue(at: "module_author") ?? [:]
        let dynamic = modules.dictionaryValue(at: "module_dynamic") ?? [:]
        let major = dynamic.dictionaryValue(at: "major")

        var blocks: [FocusOpusBlock] = []
        let richTextRuns = parseOpusTextNodes(
            dynamic.arrayValue(at: "desc", "rich_text_nodes")
                ?? dynamic.arrayValue(at: "desc", "rich_text_nodes_v2")
                ?? []
        )
        if !richTextRuns.isEmpty {
            blocks.append(.text(richTextRuns))
        } else if let text = dynamic.stringValue(at: "desc", "text") ?? major?.stringValue(at: "opus", "summary", "text"),
           let normalizedText = text.nilIfBlank
        {
            blocks.append(.text([.text(value: normalizedText)]))
        }

        var images: [FocusOpusImage] = []
        func appendPictures(from items: [[String: Any]], keys: [String]) {
            for item in items {
                let rawURL = keys.compactMap { item.stringValue(at: $0) }.first
                guard let rawURL, let normalized = Self.normalizedURLString(rawURL) else {
                    continue
                }
                images.append(
                    FocusOpusImage(
                        id: normalized,
                        url: URL(string: normalized),
                        width: item.intValue(at: "width") ?? 0,
                        height: item.intValue(at: "height") ?? 0
                    )
                )
            }
        }

        if let pics = major?.arrayValue(at: "opus", "pics") {
            appendPictures(from: pics, keys: ["url", "src"])
        }
        if let drawItems = major?.arrayValue(at: "draw", "items") {
            appendPictures(from: drawItems, keys: ["src", "url"])
        }
        if !images.isEmpty {
            blocks.append(.image(images))
        }

        let paragraphs = parseParagraphs(modules: modules)
        let resolvedParagraphs = paragraphs.isEmpty ? (blocks.isEmpty ? [] : [FocusOpusParagraph(blocks: blocks)]) : paragraphs
        guard !resolvedParagraphs.isEmpty else {
            return nil
        }

        return FocusOpusDetailContent(
            id: dynamic.stringValue(at: "id_str") ?? fallbackID,
            author: FocusOpusAuthor(
                name: author.stringValue(at: "name") ?? "用户",
                mid: author.int64Value(at: "mid") ?? 0,
                avatarURL: URL(string: Self.normalizedURLString(author.stringValue(at: "face")) ?? "")
            ),
            publishTime: author.stringValue(at: "pub_time")
                ?? author.stringValue(at: "pub_time_text")
                ?? "",
            paragraphs: resolvedParagraphs
        )
    }

    private func parseParagraphs(modules: [String: Any]) -> [FocusOpusParagraph] {
        let contentModule = modules.dictionaryValue(at: "module_content")
            ?? modules.dictionaryValue(at: "content")
        guard let paragraphs = contentModule?.arrayValue(at: "paragraphs")
            ?? contentModule?.arrayValue(at: "items")
        else {
            return []
        }

        return paragraphs.compactMap { paragraph in
            let paragraphType = paragraph.intValue(at: "para_type")
                ?? paragraph.intValue(at: "type")
            guard let paragraphType else {
                return nil
            }
            let blocks = parseBlocks(paragraph: paragraph, paragraphType: paragraphType)
            guard !blocks.isEmpty else {
                return nil
            }
            return FocusOpusParagraph(blocks: blocks)
        }
    }

    private func parseBlocks(paragraph: [String: Any], paragraphType: Int) -> [FocusOpusBlock] {
        switch paragraphType {
        case 1:
            let nodes = paragraph.arrayValue(at: "text", "nodes")
                ?? paragraph.arrayValue(at: "nodes")
                ?? []
            let textNodes = parseOpusTextNodes(nodes)
            return textNodes.isEmpty ? [] : [.text(textNodes)]

        case 2:
            let pictures = paragraph.arrayValue(at: "pic", "pics")
                ?? paragraph.arrayValue(at: "pics")
                ?? paragraph.arrayValue(at: "images")
                ?? []
            let images = pictures.compactMap { picture -> FocusOpusImage? in
                let rawURL = picture.stringValue(at: "url") ?? picture.stringValue(at: "src")
                guard let normalized = Self.normalizedURLString(rawURL) else {
                    return nil
                }
                return FocusOpusImage(
                    id: normalized,
                    url: URL(string: normalized),
                    width: picture.intValue(at: "width") ?? 0,
                    height: picture.intValue(at: "height") ?? 0
                )
            }
            return images.isEmpty ? [] : [.image(images)]

        case 7:
            let content = paragraph.stringValue(at: "code", "content")
                ?? paragraph.stringValue(at: "content")
                ?? ""
            guard let normalized = content.nilIfBlank else {
                return []
            }
            return [.code(lang: paragraph.stringValue(at: "code", "lang") ?? paragraph.stringValue(at: "lang") ?? "", content: normalized)]

        default:
            return []
        }
    }

    private func parseOpusTextNodes(_ nodes: [[String: Any]]) -> [FocusRichTextRun] {
        nodes.compactMap { node -> FocusRichTextRun? in
            let text = node.stringValue(at: "word", "words")
                ?? node.stringValue(at: "words")
                ?? node.stringValue(at: "text")
                ?? node.stringValue(at: "orig_text")
                ?? ""
            let style = node.dictionaryValue(at: "word", "style") ?? node.dictionaryValue(at: "style") ?? [:]
            let linkURL = URL(string: Self.normalizedURLString(
                node.stringValue(at: "rich", "jump_url")
                    ?? node.stringValue(at: "jump_url")
                    ?? node.stringValue(at: "link")
            ) ?? "")
            let emojiURL = URL(string: Self.normalizedURLString(
                node.stringValue(at: "rich", "emoji", "icon_url")
                    ?? node.stringValue(at: "rich", "emoji", "url")
                    ?? node.stringValue(at: "emoji", "icon_url")
                    ?? node.stringValue(at: "emoji", "url")
                    ?? node.stringValue(at: "icon_url")
            ) ?? "")

            if let emojiURL {
                let path = emojiURL.path.lowercased()
                let size = node.intValue(at: "rich", "emoji", "meta", "size")
                    ?? node.intValue(at: "emoji", "meta", "size")
                    ?? 0
                return .emote(
                    alt: text.isEmpty ? "[表情]" : text,
                    url: emojiURL,
                    width: node.intValue(at: "rich", "emoji", "width") ?? node.intValue(at: "emoji", "width") ?? size,
                    height: node.intValue(at: "rich", "emoji", "height") ?? node.intValue(at: "emoji", "height") ?? size,
                    animated: path.hasSuffix(".gif") || path.hasSuffix(".webp") || path.hasSuffix(".apng")
                )
            }
            guard !text.isEmpty else {
                if let linkURL { return .resource(label: "查看内容", url: linkURL) }
                return nil
            }
            return .text(
                value: text,
                bold: (style.intValue(at: "bold") ?? 0) == 1,
                italic: (style.intValue(at: "italic") ?? 0) == 1,
                underline: (style.intValue(at: "underline") ?? 0) == 1,
                strikethrough: (style.intValue(at: "strikethrough") ?? style.intValue(at: "strike") ?? 0) == 1,
                color: style.stringValue(at: "color"),
                linkURL: linkURL
            )
        }
    }

    private func requestObject(urlString: String, referer: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw ServiceError.message("请求地址无效")
        }
        let data = try await requestData(url: url, referer: referer)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw ServiceError.message("接口返回无效数据")
        }
        return object
    }

    private func requestData(url: URL, referer: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.httpMethod = "GET"
        request.setValue(FocusNativePageAugmentService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")

        let cookies = await cookieProvider.loadCookies()
        request = CookieRequestPolicy.attach(cookies: cookies, to: request)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw ServiceError.message("网络请求失败")
        }
        return data
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

    private static func normalizedURLString(_ raw: String?) -> String? {
        guard let raw = raw?.nilIfBlank else {
            return nil
        }
        if raw.lowercased().hasPrefix("http://") {
            return "https://" + raw.dropFirst("http://".count)
        }
        if raw.hasPrefix("//") {
            return "https:\(raw)"
        }
        return raw
    }

    struct FocusOpusDetailContent {
        let id: String
        let author: FocusOpusAuthor
        let publishTime: String
        let paragraphs: [FocusOpusParagraph]
    }
}

struct FocusMyView: View {
    @ObservedObject var viewModel: FocusMyViewModel
    let onOpenLogin: () -> Void
    let onOpenHistory: () -> Void
    let onOpenFavoriteFolder: (FocusMyFolder) -> Void
    let onOpenVideo: (URL) -> Void

    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
            }
            .alert(
                "稍后再看操作失败",
                isPresented: Binding(
                    get: { viewModel.actionErrorMessage != nil },
                    set: { presented in
                        if !presented {
                            viewModel.dismissActionError()
                        }
                    }
                )
            ) {
                Button("知道了", role: .cancel) {
                    viewModel.dismissActionError()
                }
            } message: {
                Text(viewModel.actionErrorMessage ?? "请稍后重试")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载个人页面…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loginRequired:
            FocusLoginRequiredView(
                title: "需要登录",
                message: "登录后即可查看你的播放历史和收藏夹。",
                reloadTitle: "重新检测登录态",
                reloadAction: viewModel.reload,
                loginAction: onOpenLogin
            )

        case let .failed(message):
            FocusStateView(
                title: "个人页面加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(page):
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FocusMyProfileCard(profile: page.profile)

                    if viewModel.isRefreshing { ProgressView("正在刷新，保留已加载内容…") }
                    if let message = viewModel.refreshErrorMessage {
                        HStack {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Button("重试", action: viewModel.reload)
                        }
                    }
                    ForEach(FocusMyViewModel.Section.allCases, id: \.self) { section in
                        sectionStatus(section)
                    }

                    if !page.watchLater.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("稍后再看")
                                .font(.headline.weight(.semibold))
                                .padding(.horizontal, 2)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(page.watchLater) { item in
                                        FocusWatchLaterCard(
                                            item: item,
                                            isRemoving: viewModel.watchLaterActionsInFlight.contains(
                                                item.aid
                                            ),
                                            onOpen: {
                                                guard let url = item.targetURL else {
                                                    return
                                                }
                                                onOpenVideo(url)
                                            },
                                            onRemove: {
                                                viewModel.removeFromWatchLater(aid: item.aid)
                                            }
                                        )
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    if !page.history.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Text("播放历史")
                                    .font(.headline.weight(.semibold))

                                Spacer(minLength: 0)

                                Button("更多") {
                                    onOpenHistory()
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FocusDesign.primary)
                            }
                            .padding(.horizontal, 2)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(page.history) { item in
                                        Button {
                                            guard let url = item.videoURL else {
                                                return
                                            }
                                            onOpenVideo(url)
                                        } label: {
                                            FocusMyHistoryCard(item: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    if !page.folders.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Text("收藏夹")
                                    .font(.headline.weight(.semibold))

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 2)

                            VStack(spacing: 12) {
                                ForEach(page.folders) { folder in
                                    FocusMyFolderSection(
                                        folder: folder,
                                        onOpenFolder: {
                                            onOpenFavoriteFolder(folder)
                                        },
                                        onOpenVideo: { url in
                                            onOpenVideo(url)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 132)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .task(id: page.history.map(\.id).joined(separator: "|")) {
                await prefetchAssets(for: page)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    @ViewBuilder
    private func sectionStatus(_ section: FocusMyViewModel.Section) -> some View {
        switch viewModel.sectionStates[section] {
        case .loading:
            ProgressView("\(section.title)加载中…").font(.footnote)
        case let .failed(message):
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(section.title)暂不可用").font(.subheadline)
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("重试") { viewModel.retrySection(section) }
            }
        case .loaded, .none: EmptyView()
        }
    }

    private func prefetchAssets(for page: FocusMyPage) async {
        let historyURLs = page.history.compactMap(\.coverURL)
        let watchLaterURLs = page.watchLater.compactMap(\.coverURL)
        if !historyURLs.isEmpty || !watchLaterURLs.isEmpty {
            await FocusRemoteImageLoader.prefetch(
                urls: historyURLs + watchLaterURLs,
                referer: "https://www.bilibili.com/"
            )
        }

        let folderURLs = page.folders.flatMap { folder in
            folder.previews.compactMap(\.coverURL)
        }
        if !folderURLs.isEmpty {
            await FocusRemoteImageLoader.prefetch(urls: folderURLs, referer: "https://www.bilibili.com/")
        }
    }
}

private struct FocusWatchLaterCard: View {
    let item: FocusWatchLaterItem
    let isRemoving: Bool
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FocusRemoteImage(url: item.coverURL, referer: "https://www.bilibili.com/") { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    Color(uiColor: .tertiarySystemFill)
                        .overlay(Image(systemName: "play.rectangle").foregroundStyle(.secondary))
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                        .overlay(ProgressView())
                }
            }
            .frame(width: 220, height: 124)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if item.progressSeconds > 0 {
                    Text("上次看到 \(durationText(item.progressSeconds))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.64), in: Capsule())
                        .padding(7)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 220, alignment: .leading)

            HStack(spacing: 8) {
                Text(item.author.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(role: .destructive, action: onRemove) {
                    if isRemoving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("移除", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                }
                .disabled(isRemoving)
            }
            .frame(width: 220)
        }
        .accessibilityElement(children: .contain)
    }

    private func durationText(_ seconds: Int64) -> String {
        let clamped = max(seconds, 0)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let remainingSeconds = clamped % 60
        if hours > 0 {
            return String(format: "%lld:%02lld:%02lld", hours, minutes, remainingSeconds)
        }
        return String(format: "%02lld:%02lld", minutes, remainingSeconds)
    }
}

private struct FocusMyProfileCard: View {
    let profile: FocusMyProfile

    var body: some View {
        VStack(spacing: 14) {
            FocusRemoteImage(url: profile.avatarURL, referer: "https://space.bilibili.com/\(profile.mid)") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                case .empty:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(Circle())

            VStack(spacing: 6) {
                Text(profile.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text("LV\(profile.level)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FocusDesign.primary)
            }

            HStack(spacing: 24) {
                FocusMyStat(value: formatCount(profile.following), label: "关注")
                FocusMyStat(value: formatCount(profile.followers), label: "粉丝")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func formatCount(_ value: Int64) -> String {
        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }
}

private struct FocusMyStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FocusMyHistoryCard: View {
    let item: FocusMyHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                FocusRemoteImage(url: item.coverURL, referer: item.videoURL?.absoluteString ?? "https://www.bilibili.com/") { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    case .empty:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 176, height: 102)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if item.duration > 0 {
                    Text(FocusHistoryCardFormatter.durationText(progress: item.progress, duration: item.duration))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.62))
                        .clipShape(Capsule())
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(item.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 176, alignment: .leading)
    }
}

private struct FocusMyFolderSection: View {
    let folder: FocusMyFolder
    let onOpenFolder: () -> Void
    let onOpenVideo: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text("\(folder.mediaCount) 个内容")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("更多") {
                    onOpenFolder()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FocusDesign.primary)
            }

            if !folder.previews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(folder.previews) { item in
                            Button {
                                guard let url = item.videoURL else {
                                    return
                                }
                                onOpenVideo(url)
                            } label: {
                                FocusMyFavoriteCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FocusMyFavoriteCard: View {
    let item: FocusMyFavoriteItem

    var body: some View {
        FocusTwoColumnVideoCard(content: .init(favorite: item))
            .frame(width: 176)
    }
}

struct FocusHistoryView: View {
    @ObservedObject var viewModel: FocusHistoryViewModel
    let onOpenVideo: (URL) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载播放历史…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loginRequired:
            FocusStateView(
                title: "需要登录",
                message: "登录后即可查看完整播放历史。",
                buttonTitle: "重新检测登录态",
                action: viewModel.reload
            )

        case let .failed(message):
            FocusStateView(
                title: "播放历史加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(items):
            if items.isEmpty {
                FocusStateView(
                    title: "暂无播放历史",
                    message: "开始播放视频后，这里会显示最近看过的内容。",
                    buttonTitle: "刷新",
                    action: viewModel.reload
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(items) { item in
                            Button {
                                guard let url = item.videoURL else {
                                    return
                                }
                                onOpenVideo(url)
                            } label: {
                                FocusHistoryGridCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentItemID: item.id)
                            }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 6)
                                .gridCellColumns(columns.count)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 132)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .task(id: items.map(\.id).joined(separator: "|")) {
                    await prefetchAssets(items)
                }
                .refreshable {
                    viewModel.reload()
                }
            }
        }
    }

    private func prefetchAssets(_ items: [FocusMyHistoryItem]) async {
        let urls = items.prefix(20).compactMap(\.coverURL)
        guard !urls.isEmpty else {
            return
        }
        await FocusRemoteImageLoader.prefetch(urls: urls, referer: "https://www.bilibili.com/")
    }
}

private struct FocusHistoryGridCard: View {
    let item: FocusMyHistoryItem

    var body: some View {
        FocusTwoColumnVideoCard(content: .init(history: item))
    }
}

struct FocusFavoriteFolderView: View {
    @ObservedObject var viewModel: FocusFavoriteFolderViewModel
    let onOpenVideo: (URL) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载收藏夹…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loginRequired:
            FocusStateView(
                title: "需要登录",
                message: "登录后即可查看收藏夹内容。",
                buttonTitle: "重新检测登录态",
                action: viewModel.reload
            )

        case let .failed(message):
            FocusStateView(
                title: "收藏夹加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(_, items):
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            guard let url = item.videoURL else {
                                return
                            }
                            onOpenVideo(url)
                        } label: {
                            FocusTwoColumnVideoCard(content: .init(favorite: item))
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            viewModel.loadMoreIfNeeded(currentItemID: item.id)
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                            .gridCellColumns(columns.count)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 132)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .task(id: items.map(\.id).joined(separator: "|")) {
                let urls = items.prefix(24).compactMap(\.coverURL)
                guard !urls.isEmpty else {
                    return
                }
                await FocusRemoteImageLoader.prefetch(urls: urls, referer: "https://www.bilibili.com/")
            }
            .refreshable {
                viewModel.reload()
            }
        }
    }
}

struct FocusUserSpaceView: View {
    fileprivate enum ContentSection: String, CaseIterable, Hashable {
        case videos = "视频"
        case collections = "合集"
        case articles = "专栏"
    }

    @ObservedObject var viewModel: FocusUserSpaceViewModel
    let onOpenVideo: (URL) -> Void
    let onOpenCollection: (FocusUserSpaceCollection) -> Void
    let onOpenArticle: (URL) -> Void
    @State private var selectedSection: ContentSection = .videos

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载 UP 空间…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(message):
            FocusStateView(
                title: "UP 主空间加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(page):
            let sections = availableSections(for: page)
            let activeSection = sections.contains(selectedSection) ? selectedSection : (sections.first ?? .videos)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FocusUserSpaceHeaderCard(profile: page.profile)

                    if !sections.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("内容")
                            FocusUserSpaceSectionPicker(sections: sections, selection: $selectedSection)

                            switch activeSection {
                            case .videos:
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(page.videos) { video in
                                        Button {
                                            guard let url = video.targetURL else {
                                                return
                                            }
                                            onOpenVideo(url)
                                        } label: {
                                            FocusUserSpaceVideoCard(video: video)
                                        }
                                        .buttonStyle(.plain)
                                        .onAppear {
                                            viewModel.loadMoreIfNeeded(currentVideoID: video.id)
                                        }
                                    }
                                }

                                if viewModel.isLoadingMoreVideos {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 4)
                                }

                            case .collections:
                                VStack(spacing: 10) {
                                    ForEach(page.collections) { collection in
                                        Button {
                                            onOpenCollection(collection)
                                        } label: {
                                            FocusUserSpaceCollectionCard(collection: collection, fixedWidth: nil)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                            case .articles:
                                VStack(spacing: 10) {
                                    ForEach(page.articles) { article in
                                        Button {
                                            onOpenArticle(article.targetURL)
                                        } label: {
                                            FocusUserSpaceArticleRow(article: article)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if page.videos.isEmpty, page.collections.isEmpty, page.articles.isEmpty {
                        FocusStateView(
                            title: "内容较少",
                            message: "这个 UP 主空间暂时没有可展示的公开视频、合集或专栏。",
                            buttonTitle: "刷新",
                            action: viewModel.reload
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 132)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .task(id: page.profile.mid) {
                await prefetchAssets(for: page)
                if !sections.contains(selectedSection) {
                    selectedSection = sections.first ?? .videos
                }
            }
            .refreshable {
                viewModel.reload()
            }
        }
    }

    private func availableSections(for page: FocusUserSpacePage) -> [ContentSection] {
        var sections: [ContentSection] = []
        if !page.videos.isEmpty {
            sections.append(.videos)
        }
        if !page.collections.isEmpty {
            sections.append(.collections)
        }
        if !page.articles.isEmpty {
            sections.append(.articles)
        }
        return sections
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value)
            .font(.headline.weight(.semibold))
            .padding(.horizontal, 2)
    }

    private func prefetchAssets(for page: FocusUserSpacePage) async {
        let referer = "https://space.bilibili.com/\(page.profile.mid)"
        let urls = (
            [page.profile.avatarURL]
                + page.videos.prefix(8).compactMap(\.coverURL)
                + page.collections.prefix(6).compactMap(\.coverURL)
                + page.articles.prefix(4).compactMap(\.coverURL)
        ).compactMap { $0 }

        guard !urls.isEmpty else {
            return
        }
        await FocusRemoteImageLoader.prefetch(urls: urls, referer: referer)
    }
}

private struct FocusUserSpaceSectionPicker: View {
    let sections: [FocusUserSpaceView.ContentSection]
    @Binding var selection: FocusUserSpaceView.ContentSection

    var body: some View {
        HStack(spacing: 8) {
            ForEach(sections, id: \.self) { section in
                Button {
                    selection = section
                } label: {
                    Text(section.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == section ? Color.white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    selection == section
                                        ? FocusDesign.primary
                                        : Color(uiColor: .secondarySystemGroupedBackground)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FocusUserSpaceHeaderCard: View {
    let profile: FocusUserSpaceProfile

    var body: some View {
        VStack(spacing: 14) {
            FocusRemoteImage(url: profile.avatarURL, referer: "https://space.bilibili.com/\(profile.mid)") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                case .empty:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 82, height: 82)
            .clipShape(Circle())

            VStack(spacing: 6) {
                Text(profile.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("LV\(profile.level)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FocusDesign.primary)

                if !profile.sign.isEmpty {
                    Text(profile.sign)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 18) {
                FocusUserSpaceStat(value: formatCount(profile.following), label: "关注")
                FocusUserSpaceStat(value: formatCount(profile.followers), label: "粉丝")
                FocusUserSpaceStat(value: "\(profile.videoCount)", label: "视频")
                FocusUserSpaceStat(value: "\(profile.articleCount)", label: "专栏")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func formatCount(_ value: Int64) -> String {
        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }
}

private struct FocusUserSpaceStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FocusUserSpaceVideoCard: View {
    let video: FocusUserSpaceVideo

    var body: some View {
        FocusTwoColumnVideoCard(content: .init(video: video))
    }
}

private struct FocusUserSpaceCollectionCard: View {
    let collection: FocusUserSpaceCollection
    var fixedWidth: CGFloat? = 260

    var body: some View {
        HStack(spacing: 12) {
            FocusRemoteImage(url: collection.coverURL, referer: "https://space.bilibili.com/") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                case .empty:
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(collection.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(collection.subtitle)
                    .font(.caption)
                    .foregroundStyle(FocusDesign.primary)

                if !collection.description.isEmpty {
                    Text(collection.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(collection.badgeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(width: fixedWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct FocusUserCollectionView: View {
    @ObservedObject var viewModel: FocusUserCollectionViewModel
    let onOpenVideo: (URL) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载合集…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(message):
            FocusStateView(
                title: "合集加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(page):
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FocusUserCollectionHeroCard(collection: page.collection)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(page.videos) { video in
                            Button {
                                guard let url = video.targetURL else {
                                    return
                                }
                                onOpenVideo(url)
                            } label: {
                                FocusUserSpaceVideoCard(video: video)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentVideoID: video.id)
                            }
                        }
                    }

                    if viewModel.isLoadingMoreVideos {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 132)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable {
                viewModel.reload()
            }
            .task(id: page.collection.id + "-\(page.videos.count)") {
                await prefetchAssets(for: page)
            }
        }
    }

    private func prefetchAssets(for page: FocusUserCollectionPage) async {
        let urls = ([page.collection.coverURL] + page.videos.prefix(10).compactMap(\.coverURL)).compactMap { $0 }
        guard !urls.isEmpty else {
            return
        }
        await FocusRemoteImageLoader.prefetch(urls: urls, referer: "https://space.bilibili.com/\(page.collection.ownerMID)")
    }
}

private struct FocusUserCollectionHeroCard: View {
    let collection: FocusUserSpaceCollection

    var body: some View {
        HStack(spacing: 14) {
            FocusRemoteImage(url: collection.coverURL, referer: "https://space.bilibili.com/\(collection.ownerMID)") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                case .empty:
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 110, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(collection.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(collection.subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FocusDesign.primary)

                if !collection.description.isEmpty {
                    Text(collection.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else {
                    Text(collection.badgeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct FocusArticleView: View {
    @ObservedObject var viewModel: FocusArticleViewModel
    let onOpenUser: (Int64) -> Void
    let onOpenURL: (URL) -> Void
    let onOpenWeb: (URL) -> Void

    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载专栏…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loginRequired:
            FocusStateView(
                title: "需要登录",
                message: "当前专栏需要登录后查看。",
                buttonTitle: "重新加载",
                action: viewModel.reload
            )
            .overlay(alignment: .bottom) { openArticleOnWebButton }

        case let .failed(message):
            FocusStateView(
                title: "专栏加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )
            .overlay(alignment: .bottom) { openArticleOnWebButton }

        case let .loaded(page):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if page.bannerURL != nil {
                        FocusRemoteImage(url: page.bannerURL, referer: "https://www.bilibili.com/read/cv\(page.cvid)") { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemFill))
                            case .empty:
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemFill))
                                    .overlay(ProgressView())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    Text(page.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    FocusArticleAuthorCard(page: page, onOpenUser: onOpenUser)
                    FocusArticleStatsCard(stats: page.stats)

                    if !page.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(page.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(FocusDesign.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(FocusDesign.primary.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    ForEach(Array(page.blocks.enumerated()), id: \.offset) { _, block in
                        FocusArticleBlockView(
                            block: block,
                            referer: page.originalURL.absoluteString,
                            onOpenURL: onOpenURL
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 132)
            }
            .background(FocusScrollBounceDisabler())
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    @ViewBuilder
    private var openArticleOnWebButton: some View {
        if let url = viewModel.originalURL {
            Button {
                onOpenWeb(url)
            } label: {
                Label("在网页中打开", systemImage: "safari")
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 32)
        }
    }
}

private struct FocusArticleBlockView: View {
    let block: FocusArticleBlock
    let referer: String
    let onOpenURL: (URL) -> Void

    var body: some View {
        switch block {
        case let .paragraph(runs, alignment):
            FocusInlineRichText(runs: runs, onOpenURL: onOpenURL)
                .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
        case let .heading(runs, level):
            FocusInlineRichText(
                runs: runs,
                font: level <= 1 ? .title2.weight(.bold) : level == 2 ? .title3.weight(.bold) : .headline,
                onOpenURL: onOpenURL
            )
            .padding(.top, 4)
        case let .image(url, width, height, caption):
            VStack(alignment: .leading, spacing: 6) {
                FocusRemoteImage(url: url, referer: referer) { phase in
                    switch phase {
                    case let .success(image): image.resizable().scaledToFit()
                    case .failure:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    case .empty:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(ProgressView())
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(width > 0 && height > 0 ? CGFloat(width) / CGFloat(height) : 4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !caption.isEmpty {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
        case let .quote(runs):
            FocusInlineRichText(runs: runs, foreground: .secondary, onOpenURL: onOpenURL)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case let .list(ordered, items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, runs in
                    HStack(alignment: .top, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .frame(width: 24, alignment: .trailing)
                        FocusInlineRichText(runs: runs, onOpenURL: onOpenURL)
                    }
                }
            }
        case let .code(language, content):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if !language.isEmpty {
                        Text(language.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(FocusDesign.primary)
                    }
                    Text(content).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case let .resource(title, url):
            Button { onOpenURL(url) } label: {
                HStack {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square").foregroundStyle(FocusDesign.primary)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        case .divider:
            Divider()
        }
    }

    private func frameAlignment(_ alignment: FocusArticleTextAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

private struct FocusArticleAuthorCard: View {
    let page: FocusArticlePage
    let onOpenUser: (Int64) -> Void

    var body: some View {
        Button {
            guard page.author.mid > 0 else {
                return
            }
            onOpenUser(page.author.mid)
        } label: {
            HStack(spacing: 12) {
                FocusRemoteImage(url: page.author.avatarURL, referer: "https://space.bilibili.com/\(page.author.mid)") { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                    case .empty:
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(page.author.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if page.publishTime > 0 {
                        Text(formatDate(page.publishTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ seconds: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
}

private struct FocusArticleStatsCard: View {
    let stats: FocusArticleStats

    var body: some View {
        HStack(spacing: 0) {
            FocusArticleStatItem(value: formatCount(stats.views), label: "阅读")
            FocusArticleStatItem(value: formatCount(stats.likes), label: "点赞")
            FocusArticleStatItem(value: formatCount(stats.coins), label: "硬币")
            FocusArticleStatItem(value: formatCount(stats.favorites), label: "收藏")
            FocusArticleStatItem(value: formatCount(stats.comments), label: "评论")
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func formatCount(_ value: Int64) -> String {
        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }
}

private struct FocusArticleStatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FocusUserSpaceArticleRow: View {
    let article: FocusUserSpaceArticle

    var body: some View {
        HStack(spacing: 12) {
            if article.coverURL != nil {
                FocusRemoteImage(url: article.coverURL, referer: article.targetURL.absoluteString) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    case .empty:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 96, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                let meta = [article.viewText.isEmpty ? nil : "\(article.viewText)阅读", article.publishText]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct FocusOpusDetailView: View {
    @ObservedObject var viewModel: FocusOpusDetailViewModel
    let onOpenURL: (URL) -> Void
    @State private var galleryRequest: FocusImageGalleryRequest?

    var body: some View {
        content
            .fullScreenCover(item: $galleryRequest) { request in
                FocusImageGalleryView(request: request)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载图文详情…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loginRequired:
            FocusStateView(
                title: "需要登录",
                message: "当前图文详情需要登录后才能查看。",
                buttonTitle: "重新加载",
                action: viewModel.reload
            )

        case let .failed(message):
            FocusStateView(
                title: "图文详情加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(page):
            let allImages = page.paragraphs.flatMap { paragraph in
                paragraph.blocks.flatMap { block -> [FocusOpusImage] in
                    guard case let .image(images) = block else { return [] }
                    return images
                }
            }
            let validImages = allImages.filter { $0.url != nil }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FocusOpusAuthorCard(page: page, onOpenURL: onOpenURL)

                    ForEach(page.paragraphs) { paragraph in
                        FocusOpusParagraphCard(
                            paragraph: paragraph,
                            onOpenURL: onOpenURL,
                            onOpenImage: { selected in
                                let urls = validImages.compactMap(\.url)
                                guard !urls.isEmpty else { return }
                                let index = validImages.firstIndex(where: { $0.id == selected.id }) ?? 0
                                galleryRequest = FocusImageGalleryRequest(
                                    urls: urls,
                                    initialIndex: index,
                                    referer: "https://www.bilibili.com/opus/\(page.id)"
                                )
                            }
                        )
                    }

                    if !page.comments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("评论")
                                .font(.headline.weight(.semibold))
                                .padding(.horizontal, 2)

                            ForEach(Array(page.comments.enumerated()), id: \.offset) { item in
                                FocusOpusCommentCard(
                                    comment: item.element,
                                    onOpenURL: onOpenURL,
                                    onOpenImages: { rawURLs, index in
                                        let urls = rawURLs.compactMap(URL.init(string:))
                                        galleryRequest = FocusImageGalleryRequest(
                                            urls: urls,
                                            initialIndex: index,
                                            referer: "https://www.bilibili.com/opus/\(page.id)"
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 132)
            }
            .background(FocusScrollBounceDisabler())
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

private struct FocusOpusAuthorCard: View {
    let page: FocusOpusDetailPage
    let onOpenURL: (URL) -> Void

    var body: some View {
        Button {
            guard page.author.mid > 0,
                  let url = URL(string: "https://space.bilibili.com/\(page.author.mid)")
            else {
                return
            }
            onOpenURL(url)
        } label: {
            HStack(spacing: 12) {
                FocusRemoteImage(url: page.author.avatarURL, referer: "https://space.bilibili.com/\(page.author.mid)") { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                    case .empty:
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(page.author.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !page.publishTime.isEmpty {
                        Text(page.publishTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FocusOpusParagraphCard: View {
    let paragraph: FocusOpusParagraph
    var onOpenURL: (URL) -> Void = { _ in }
    var onOpenImage: (FocusOpusImage) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(paragraph.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .text(nodes):
                    FocusInlineRichText(runs: nodes, onOpenURL: onOpenURL)
                case let .image(images):
                    FocusOpusImageGrid(images: images, onOpenImage: onOpenImage)
                case let .code(lang, content):
                    VStack(alignment: .leading, spacing: 8) {
                        if !lang.isEmpty {
                            Text(lang.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(FocusDesign.primary)
                        }
                        Text(content)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FocusOpusImageGrid: View {
    let images: [FocusOpusImage]
    let onOpenImage: (FocusOpusImage) -> Void

    var body: some View {
        if images.count == 1, let image = images.first {
            FocusOpusImageTile(image: image, onOpenImage: onOpenImage)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(images) { image in
                    FocusOpusImageTile(image: image, onOpenImage: onOpenImage)
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
    }
}

private struct FocusOpusImageTile: View {
    let image: FocusOpusImage
    let onOpenImage: (FocusOpusImage) -> Void

    var body: some View {
        FocusRemoteImage(url: image.url, referer: image.url?.absoluteString ?? "https://www.bilibili.com/") { phase in
            switch phase {
            case let .success(view):
                view
                    .resizable()
                    .scaledToFit()
            case .failure:
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
            case .empty:
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .overlay(ProgressView())
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(image.aspectRatio ?? 1, contentMode: .fit)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onOpenImage(image) }
    }
}

private struct FocusOpusCommentCard: View {
    let comment: FocusNativeCommentPayload
    let onOpenURL: (URL) -> Void
    let onOpenImages: ([String], Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FocusRemoteImage(url: URL(string: comment.avatarURL), referer: "https://www.bilibili.com/") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                case .empty:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(comment.author)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FocusDesign.primary)

                FocusInlineRichText(runs: comment.contentRuns, onOpenURL: onOpenURL)

                FocusCommentImageStrip(
                    urls: comment.imageURLs.compactMap(URL.init(string:)),
                    referer: "https://www.bilibili.com/",
                    onSelect: { onOpenImages(comment.imageURLs, $0) }
                )

                ForEach(Array(comment.previewReplies.prefix(2).enumerated()), id: \.offset) { _, reply in
                    HStack(alignment: .top, spacing: 2) {
                        Text("\(reply.author)：")
                            .font(.caption)
                            .foregroundStyle(FocusDesign.primary)
                        FocusInlineRichText(
                            runs: reply.contentRuns,
                            font: .caption,
                            foreground: .secondary,
                            onOpenURL: onOpenURL
                        )
                    }
                    .padding(.leading, 8)
                    FocusCommentImageStrip(
                        urls: reply.imageURLs.compactMap(URL.init(string:)),
                        referer: "https://www.bilibili.com/",
                        onSelect: { onOpenImages(reply.imageURLs, $0) }
                    )
                    .padding(.leading, 8)
                }

                let meta = [comment.timeText, comment.likeText, comment.replyText]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
#endif
