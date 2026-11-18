import Foundation

public struct DynamicFeedService: Sendable {
    private struct FeedCacheKey: Hashable, Sendable {
        let sessionFingerprint: Int
        let sessionVersion: UInt64
        let timezoneOffsetMinutes: Int
        let offset: String
    }

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
    private let pageCache: AsyncExpiringCache<FeedCacheKey, FeedPage>
    private let snapshotStore: DynamicFeedSnapshotStore

    public init(
        cookieProvider: any CookieSnapshotProvider,
        timezoneOffsetMinutes: Int = -(TimeZone.current.secondsFromGMT() / 60),
        snapshotStore: DynamicFeedSnapshotStore = .shared,
        requestLoader: @escaping RequestLoader = { request in
            try await BiliAPINetwork.data(for: request)
        }
    ) {
        self.cookieProvider = cookieProvider
        self.timezoneOffsetMinutes = timezoneOffsetMinutes
        self.requestLoader = requestLoader
        self.snapshotStore = snapshotStore
        pageCache = AsyncExpiringCache(maximumEntries: 32)
    }

    public var sessionVersion: UInt64 { cookieProvider.sessionVersion }
    public var sessionReadiness: CookieSessionReadiness { cookieProvider.sessionReadiness }
    public func prepareSessionVersion() async -> UInt64 { await cookieProvider.loadSnapshot().version }
    public func clearCache() async { await pageCache.clear() }
    public func clearPersistentCache() async throws {
        await pageCache.clear()
        try await snapshotStore.clear()
    }
    public func snapshotWriteRevision() async -> UInt64 { await snapshotStore.writeRevision() }
    public func cachedSnapshot() async -> DynamicFeedSnapshotStore.Snapshot? {
        let snapshot = await cookieProvider.loadSnapshot()
        guard snapshot.version == cookieProvider.sessionVersion, snapshot.readiness == .authenticated else { return nil }
        let cached = await snapshotStore.load(scope: .resolve(cookies: snapshot.cookies))
        guard snapshot.version == cookieProvider.sessionVersion else { return nil }
        return cached
    }
    public func saveSnapshot(cards: [DynamicCard], nextOffset: String?, version: UInt64, revision: UInt64) async throws {
        // Keep the last complete page boundary below the cap; dropping rows
        // while keeping a later cursor would create an invisible pagination gap.
        guard cards.count <= 300 else { return }
        let snapshot = await cookieProvider.loadSnapshot()
        try Task.checkCancellation()
        guard version == snapshot.version, version == cookieProvider.sessionVersion,
              snapshot.readiness == .authenticated else { return }
        try await snapshotStore.save(cards: cards, nextOffset: nextOffset,
                                     scope: .resolve(cookies: snapshot.cookies), revision: revision)
    }

    public func fetchFollowingFeed() async throws -> [DynamicCard] {
        try await fetchFollowingFeedPage().cards
    }

    public func fetchFollowingFeedPage(offset: String? = nil) async throws -> FeedPage {
        try await fetchFollowingFeedPage(offset: offset, forceRefresh: false)
    }

    public func refreshFollowingFeedPage(offset: String? = nil) async throws -> FeedPage {
        try await fetchFollowingFeedPage(offset: offset, forceRefresh: true)
    }

    private func fetchFollowingFeedPage(
        offset: String?,
        forceRefresh: Bool
    ) async throws -> FeedPage {
        let snapshot = await cookieProvider.loadSnapshot()
        let version = snapshot.version
        guard version == cookieProvider.sessionVersion else { throw CancellationError() }
        if snapshot.readiness == .expired { throw ServiceError.loginRequired }
        guard !snapshot.cookies.isEmpty else {
            if snapshot.readiness == .unconfirmed || snapshot.readiness == .restoring {
                throw URLError(.resourceUnavailable)
            }
            throw ServiceError.loginRequired
        }
        let key = FeedCacheKey(
            sessionFingerprint: Self.sessionFingerprint(for: snapshot.cookies), sessionVersion: version,
            timezoneOffsetMinutes: timezoneOffsetMinutes, offset: offset ?? ""
        )
        do {
            let page = try await pageCache.value(
                for: key, policy: FocusCachePolicy(freshFor: 20, staleIfErrorFor: 180),
                forceRefresh: forceRefresh,
                returnsStaleOnError: !forceRefresh,
                canUseStaleOnError: { error in
                    guard let network = error as? URLError else { return false }
                    return network.code != .cancelled && network.code != .userAuthenticationRequired
                }
            ) {
                let page = try await Self.loadFollowingFeedPage(
                    offset: offset, timezoneOffsetMinutes: timezoneOffsetMinutes,
                    cookies: snapshot.cookies, requestLoader: requestLoader
                )
                guard version == cookieProvider.sessionVersion else { throw CancellationError() }
                return page
            }
            guard version == cookieProvider.sessionVersion else { throw CancellationError() }
            return page
        } catch let error as ServiceError where error == .loginRequired {
            cookieProvider.noteServerSessionExpired(version: version)
            throw error
        }
    }

    private static func loadFollowingFeedPage(
        offset: String?,
        timezoneOffsetMinutes: Int,
        cookies: [HTTPCookie],
        requestLoader: RequestLoader
    ) async throws -> FeedPage {
        var request = URLRequest(url: Self.endpoint(timezoneOffsetMinutes: timezoneOffsetMinutes, offset: offset))
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("https://t.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request = Self.attach(cookies: cookies, to: request)

        let (data, response) = try await requestLoader(request)
        try Task.checkCancellation()
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw ServiceError.loginRequired }
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw ServiceError.invalidResponse
        }

        return try Self.decodeFeedPage(from: data)
    }

    private static func sessionFingerprint(for cookies: [HTTPCookie]) -> Int {
        let identityNames = Set(["SESSDATA", "DedeUserID", "DedeUserID__ckMd5"])
        let identityCookies = cookies.filter { identityNames.contains($0.name) }
        let scopedCookies = identityCookies.isEmpty ? cookies : identityCookies
        var hasher = Hasher()
        for cookie in scopedCookies.sorted(by: {
            ($0.domain, $0.path, $0.name, $0.value)
                < ($1.domain, $1.path, $1.name, $1.value)
        }) {
            hasher.combine(cookie.domain)
            hasher.combine(cookie.path)
            hasher.combine(cookie.name)
            hasher.combine(cookie.value)
        }
        return hasher.finalize()
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
        // The API can return the last cursor even when pagination is finished.
        // Missing has_more remains compatible with older responses/fixtures.
        let hasMore = payload.intValue(at: ["data", "has_more"])
        return FeedPage(cards: cards, nextOffset: hasMore == 0 || nextOffset?.isEmpty == true ? nil : nextOffset)
    }

    public static func attach(cookies: [HTTPCookie], to request: URLRequest) -> URLRequest {
        CookieRequestPolicy.attach(cookies: cookies, to: request)
    }

    private static func endpoint(timezoneOffsetMinutes: Int, offset: String?) -> URL {
        var components = URLComponents(
            url: BiliAPIContractCatalog.require(
                "dynamic.info.dynamic_page_info"
            ).url,
            resolvingAgainstBaseURL: false
        )!
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

    private static func makeCard(from item: [String: Any], allowMissingID: Bool = false) -> DynamicCard? {
        let modules = item.dictionaryValue(at: ["modules"]) ?? [:]
        let author = modules.dictionaryValue(at: ["module_author"]) ?? [:]
        let dynamic = modules.dictionaryValue(at: ["module_dynamic"]) ?? [:]
        let major = dynamic.dictionaryValue(at: ["major"]) ?? [:]
        let basic = item.dictionaryValue(at: ["basic"]) ?? [:]

        let resolvedID = item.stringValue(at: ["id_str"])
            ?? basic.stringValue(at: ["comment_id_str"])
            ?? basic.stringValue(at: ["rid_str"])
            ?? basic.intValue(at: ["comment_id"]).map(String.init)
        if resolvedID == nil && !allowMissingID {
            return nil
        }
        let id = resolvedID ?? ""

        let authorName = author.stringValue(at: ["name"]) ?? "Bilibili"
        let authorMID = author.intValue(at: ["mid"]).map(Int64.init) ?? 0
        let authorAvatar = normalizedURL(author.stringValue(at: ["face"]))
        let publishTime = author.stringValue(at: ["pub_time"])
            ?? author.stringValue(at: ["pub_action"])
            ?? author.stringValue(at: ["pub_time_label"])
            ?? ""

        let itemType = item.stringValue(at: ["type"]) ?? ""
        let isForwardItem = itemType == "DYNAMIC_TYPE_FORWARD"
        let majorType = major.stringValue(at: ["type"]) ?? ""
        let archiveBVID = major.stringValue(at: ["archive", "bvid"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryJumpCandidates = [
            basic.stringValue(at: ["jump_url"]),
            major.stringValue(at: ["archive", "jump_url"]),
            archiveBVID.flatMap { $0.isEmpty ? nil : "https://www.bilibili.com/video/\($0)/" },
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
        let detectedVideoURL = jumpCandidates.first(where: isVideoLikeURL(_:))
        let videoURL = isForwardItem ? nil : detectedVideoURL
        let kind = makeKind(
            majorType: majorType,
            itemType: itemType,
            videoURL: videoURL,
            coverURLs: coverURLs
        )
        let articleIDFromString: Int64? = major.stringValue(at: ["article", "id"]).flatMap { Int64($0) }
            ?? major.stringValue(at: ["article", "id_str"]).flatMap { Int64($0) }
            ?? major.stringValue(at: ["article", "cvid"]).flatMap { Int64($0) }
        let articleCVID: Int64? = articleIDFromString
            ?? major.intValue(at: ["article", "id"]).map { Int64($0) }
            ?? jumpCandidates.compactMap(extractArticleCVID(from:)).first
        let articleURL: URL? = if !isForwardItem && kind == .articleLike {
            jumpCandidates.first(where: { extractArticleCVID(from: $0) != nil })
                .flatMap { extractArticleCVID(from: $0) }
                .flatMap { URL(string: "https://www.bilibili.com/read/cv\($0)") }
                ?? articleCVID.flatMap { URL(string: "https://www.bilibili.com/read/cv\($0)") }
        } else {
            nil
        }
        let opusDetailURL = primaryJumpCandidates.first(where: isOpusLikeURL(_:))
        let targetURL: URL
        if isForwardItem {
            targetURL = opusDetailURL ?? fallbackTargetURL(for: id, kind: kind)
        } else {
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
        }

        let quotedCard: DynamicCard.QuotedCard? = if !allowMissingID {
            (item.dictionaryValue(at: ["orig"]) ?? item.dictionaryValue(at: ["origin"]))
                .flatMap(makeQuotedCard(from:))
                ?? dynamic.dictionaryValue(at: ["additional"]).flatMap(makeAdditionalQuotedCard(from:))
        } else {
            nil
        }

        return DynamicCard(
            id: id,
            kind: kind,
            author: .init(mid: authorMID, name: authorName, avatarURL: authorAvatar),
            publishTime: publishTime,
            text: text,
            coverURLs: coverURLs,
            targetURL: targetURL,
            videoURL: videoURL,
            quotedCard: quotedCard
        )
    }

    private static func makeQuotedCard(from orig: [String: Any]) -> DynamicCard.QuotedCard? {
        let origType = orig.stringValue(at: ["type"]) ?? ""
        let origModules = orig.dictionaryValue(at: ["modules"]) ?? [:]
        let origDynamic = origModules.dictionaryValue(at: ["module_dynamic"]) ?? [:]
        let origMajor = origDynamic.dictionaryValue(at: ["major"]) ?? [:]
        let origMajorType = origMajor.stringValue(at: ["type"]) ?? ""

        if origType == "DYNAMIC_TYPE_NONE" || origMajorType == "MAJOR_TYPE_NONE" {
            let tip = [
                origMajor.stringValue(at: ["none", "tips"]),
                origDynamic.stringValue(at: ["desc", "text"]),
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "源动态已被作者删除"
            return DynamicCard.QuotedCard(
                id: orig.stringValue(at: ["id_str"]) ?? "",
                unavailableTip: tip
            )
        }

        guard let card = makeCard(from: orig, allowMissingID: true) else {
            return nil
        }

        let title = extractMajorTitle(from: origMajor)
        let explicitDesc = extractExplicitBodyText(dynamic: origDynamic, major: origMajor)
        let archiveDesc = origMajor.stringValue(at: ["archive", "desc"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let articleDesc = origMajor.stringValue(at: ["article", "desc"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyText: String
        if !explicitDesc.isEmpty, explicitDesc != title {
            bodyText = explicitDesc
        } else if !card.text.isEmpty, card.text != title {
            bodyText = card.text
        } else if let archiveDesc, !archiveDesc.isEmpty, archiveDesc != title {
            bodyText = archiveDesc
        } else if let articleDesc, !articleDesc.isEmpty, articleDesc != title {
            bodyText = articleDesc
        } else {
            bodyText = ""
        }

        let resolvedTarget: URL? = (!card.id.isEmpty || card.targetURL != fallbackTargetURL(for: "", kind: card.kind))
            ? card.targetURL
            : nil

        if title.isEmpty, bodyText.isEmpty, card.coverURLs.isEmpty, resolvedTarget == nil {
            return nil
        }

        return DynamicCard.QuotedCard(
            id: card.id,
            kind: card.kind,
            author: card.author,
            publishTime: card.publishTime,
            title: title,
            text: bodyText,
            coverURLs: card.coverURLs,
            targetURL: resolvedTarget,
            videoURL: card.videoURL
        )
    }

    private static func makeAdditionalQuotedCard(from additional: [String: Any]) -> DynamicCard.QuotedCard? {
        let type = additional.stringValue(at: ["type"]) ?? ""
        if type == "ADDITIONAL_TYPE_UGC" || additional.dictionaryValue(at: ["ugc"]) != nil,
           let ugc = additional.dictionaryValue(at: ["ugc"])
        {
            let title = ugc.stringValue(at: ["title"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = ugc.stringValue(at: ["desc_second"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cover = normalizedURL(ugc.stringValue(at: ["cover"]))
            let jumpURL = normalizedURL(ugc.stringValue(at: ["jump_url"]))
            let videoURL = jumpURL.flatMap { isVideoLikeURL($0) ? $0 : nil }
            if title.isEmpty, text.isEmpty, cover == nil, jumpURL == nil { return nil }
            return DynamicCard.QuotedCard(
                id: ugc.stringValue(at: ["id_str"]) ?? "",
                kind: .video,
                title: title,
                text: text,
                coverURLs: cover.map { [$0] } ?? [],
                targetURL: jumpURL,
                videoURL: videoURL
            )
        }
        if type == "ADDITIONAL_TYPE_OPUS" || additional.dictionaryValue(at: ["opus"]) != nil,
           let opus = additional.dictionaryValue(at: ["opus"])
        {
            let title = opus.stringValue(at: ["title"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = (
                richTextPlainText(opus.arrayValue(at: ["summary", "rich_text_nodes"]))
                    ?? opus.stringValue(at: ["summary", "text"])
                    ?? opus.stringValue(at: ["desc"])
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var covers: [URL] = []
            if let cover = normalizedURL(opus.stringValue(at: ["cover"])) {
                covers.append(cover)
            }
            for rawPic in opus.arrayValue(at: ["pics"]) ?? [] {
                guard let pic = rawPic as? [String: Any],
                      let url = normalizedURL(pic.stringValue(at: ["url"]) ?? pic.stringValue(at: ["src"]))
                else { continue }
                if !covers.contains(url) { covers.append(url) }
            }
            let jumpURL = normalizedURL(opus.stringValue(at: ["jump_url"]))
            if title.isEmpty, text.isEmpty, covers.isEmpty, jumpURL == nil { return nil }
            return DynamicCard.QuotedCard(
                kind: covers.isEmpty ? .text : .image,
                title: title,
                text: text,
                coverURLs: covers,
                targetURL: jumpURL
            )
        }
        if type == "ADDITIONAL_TYPE_COMMON" || additional.dictionaryValue(at: ["common"]) != nil,
           let common = additional.dictionaryValue(at: ["common"])
        {
            let title = (common.stringValue(at: ["title"]) ?? common.stringValue(at: ["head_text"]))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = [common.stringValue(at: ["desc1"]), common.stringValue(at: ["desc2"])]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let cover = normalizedURL(common.stringValue(at: ["cover"]))
            let jumpURL = normalizedURL(common.stringValue(at: ["jump_url"]))
            if title.isEmpty, text.isEmpty, cover == nil, jumpURL == nil { return nil }
            return DynamicCard.QuotedCard(
                kind: .text,
                title: title,
                text: text,
                coverURLs: cover.map { [$0] } ?? [],
                targetURL: jumpURL
            )
        }
        return nil
    }

    private static func extractExplicitBodyText(dynamic: [String: Any], major: [String: Any]) -> String {
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

        return bodyCandidates.max(by: { $0.count < $1.count }) ?? ""
    }

    private static func extractMajorTitle(from major: [String: Any]) -> String {
        [
            major.stringValue(at: ["archive", "title"]),
            major.stringValue(at: ["article", "title"]),
            major.stringValue(at: ["pgc", "title"]),
            major.stringValue(at: ["opus", "title"]),
            major.stringValue(at: ["courses", "title"]),
            major.stringValue(at: ["music", "title"]),
            major.stringValue(at: ["medialist", "title"]),
            major.stringValue(at: ["live", "title"]),
            major.stringValue(at: ["common", "title"]),
            major.stringValue(at: ["ugc_season", "title"]),
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? ""
    }

    private static func makeText(dynamic: [String: Any], major: [String: Any]) -> String {
        let body = extractExplicitBodyText(dynamic: dynamic, major: major)
        if !body.isEmpty {
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

        if let canonicalURL = canonicalSchemeURL(rawValue) {
            return canonicalURL
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

    private static func canonicalSchemeURL(_ rawValue: String) -> URL? {
        guard
            let url = URL(string: rawValue),
            url.scheme?.lowercased() == "bilibili",
            let host = url.host?.lowercased()
        else {
            return nil
        }
        let pathComponents = url.path.split(separator: "/").map(String.init)
        switch host {
        case "following", "opus":
            guard pathComponents.count == 2,
                  pathComponents[0].lowercased() == "detail",
                  !pathComponents[1].isEmpty,
                  pathComponents[1].allSatisfy(\.isNumber)
            else { return nil }
            return URL(string: "https://www.bilibili.com/opus/\(pathComponents[1])")
        case "dynamic":
            guard pathComponents.count == 1,
                  !pathComponents[0].isEmpty,
                  pathComponents[0].allSatisfy(\.isNumber)
            else { return nil }
            return URL(string: "https://www.bilibili.com/opus/\(pathComponents[0])")
        case "video":
            guard pathComponents.count == 1,
                  pathComponents[0].uppercased().hasPrefix("BV")
            else { return nil }
            return URL(string: "https://www.bilibili.com/video/\(pathComponents[0])/")
        default:
            return nil
        }
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
