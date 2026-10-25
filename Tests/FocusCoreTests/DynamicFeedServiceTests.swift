import FocusCore
import Foundation
import Testing

struct DynamicFeedServiceTests {
    @Test func cancelledSnapshotWriterCannotOverwriteTheAcceptedFeed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DynamicFeedSnapshotStore(fileURL: directory.appendingPathComponent("feed.json"))
        let cookies = DynamicSnapshotSaveCookies()
        let service = DynamicFeedService(cookieProvider: cookies, snapshotStore: store)
        let cards = try DynamicFeedService.decodeCards(from: Data(samplePayload.utf8))
        let oldSave = Task { try await service.saveSnapshot(cards: [cards[0]], nextOffset: "old", version: 0, revision: 0) }
        await cookies.waitUntilReading()
        oldSave.cancel()
        try await store.save(cards: [cards[1]], nextOffset: "accepted", scope: .accountID(42), revision: 0)
        await cookies.release()
        await #expect(throws: CancellationError.self) { try await oldSave.value }
        #expect(await store.load(scope: .accountID(42))?.nextOffset == "accepted")

        // Also exercise cancellation at the actor boundary, independently of
        // the service's post-cookie suspension check.
        let queuedSave = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.save(cards: [cards[0]], nextOffset: "queued-old", scope: .accountID(42), revision: 0)
        }
        await #expect(throws: CancellationError.self) { try await queuedSave.value }
        #expect(await store.load(scope: .accountID(42))?.nextOffset == "accepted")
    }

    @Test func persistentSnapshotSurvivesReopenAndExpiresWithoutCrossingAccounts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("feed.json")
        let store = DynamicFeedSnapshotStore(fileURL: file)
        let cards = try DynamicFeedService.decodeCards(from: Data(samplePayload.utf8))
        let account = FocusPlaybackAccountScope.accountID(42)
        let now = Date(timeIntervalSince1970: 1_000_000)
        try await store.save(cards: cards, nextOffset: "next", scope: account, revision: 0, now: now)
        let reopened = DynamicFeedSnapshotStore(fileURL: file)
        #expect(await reopened.load(scope: account, now: now)?.cards == cards)
        #expect(await reopened.load(scope: .accountID(43), now: now) == nil)
        #expect(await reopened.load(scope: account, now: now.addingTimeInterval(8 * 24 * 3600)) == nil)
        let bytes = try String(contentsOf: file, encoding: .utf8)
        #expect(!bytes.contains("SESSDATA"))
        #expect(!bytes.contains("DedeUserID"))
    }

    @Test func clearingSnapshotsFencesLateWritesAndCapacityKeepsCompletePages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("feed.json")
        let store = DynamicFeedSnapshotStore(fileURL: file)
        let cards = try DynamicFeedService.decodeCards(from: Data(samplePayload.utf8))
        let account = FocusPlaybackAccountScope.accountID(42)
        let oldRevision = await store.writeRevision()
        try await store.save(cards: cards, nextOffset: "valid", scope: account, revision: oldRevision)
        try await store.save(cards: Array(repeating: cards[0], count: 301), nextOffset: "gap", scope: account, revision: oldRevision)
        #expect(await store.load(scope: account)?.nextOffset == "valid")
        try await store.clear()
        try await store.save(cards: cards, nextOffset: "late", scope: account, revision: oldRevision)
        #expect(await store.load(scope: account) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        for id in 1...4 {
            try await store.save(cards: cards, nextOffset: nil, scope: .accountID(Int64(id)), revision: await store.writeRevision(),
                                 now: Date().addingTimeInterval(Double(id)))
        }
        #expect(await store.load(scope: .accountID(1)) == nil)
        #expect(await store.load(scope: .accountID(4)) != nil)
    }

    @Test func terminalHasMoreWinsOverAnEchoedCursor() throws {
        for flag in ["false", "0"] {
            let data = Data("{\"code\":0,\"data\":{\"items\":[],\"offset\":\"last\",\"has_more\":\(flag)}}".utf8)
            #expect(try DynamicFeedService.decodeFeedPage(from: data).nextOffset == nil)
        }
        let continuing = Data(#"{"code":0,"data":{"items":[],"offset":"next","has_more":true}}"#.utf8)
        #expect(try DynamicFeedService.decodeFeedPage(from: continuing).nextOffset == "next")
    }

    @Test
    func decodeCardsMapsVideoAndImageDynamics() throws {
        let data = Data(samplePayload.utf8)
        let cards = try DynamicFeedService.decodeCards(from: data)

        #expect(cards.count == 2)

        let videoCard = try #require(cards.first)
        #expect(videoCard.kind == .video)
        #expect(videoCard.author.name == "Tech UP")
        #expect(videoCard.publishTime == "5分钟前")
        #expect(videoCard.text == "视频动态正文")
        #expect(videoCard.coverURLs.count == 1)
        #expect(videoCard.targetURL.absoluteString == "https://www.bilibili.com/video/BV1xx411c7mD/")
        #expect(videoCard.videoURL?.absoluteString == "https://www.bilibili.com/video/BV1xx411c7mD/")

        let imageCard = cards[1]
        #expect(imageCard.kind == .image)
        #expect(imageCard.author.avatarURL?.absoluteString == "https://i0.hdslb.com/bfs/face/draw.jpg")
        #expect(imageCard.coverURLs.count == 2)
        #expect(imageCard.targetURL.absoluteString == "https://www.bilibili.com/opus/456")
        #expect(imageCard.videoURL == nil)
    }

    @Test
    func attachCookiesAddsCookieHeader() {
        let properties: [HTTPCookiePropertyKey: Any] = [
            .domain: ".bilibili.com",
            .path: "/",
            .name: "SESSDATA",
            .value: "focus-cookie",
            .secure: "TRUE",
        ]
        let cookie = HTTPCookie(properties: properties)
        let request = URLRequest(url: URL(string: "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all")!)
        let updatedRequest = DynamicFeedService.attach(cookies: [cookie].compactMap { $0 }, to: request)

        #expect(updatedRequest.value(forHTTPHeaderField: "Cookie")?.contains("SESSDATA=focus-cookie") == true)
    }

    @Test
    func fetchFollowingFeedFailsFastWithoutCookies() async {
        let service = DynamicFeedService(
            cookieProvider: EmptyCookieProvider(),
            requestLoader: { _ in
                Issue.record("request loader should not run when cookies are missing")
                return (
                    Data(),
                    URLResponse(
                        url: URL(string: "https://api.bilibili.com")!,
                        mimeType: "application/json",
                        expectedContentLength: 0,
                        textEncodingName: nil
                    )
                )
            }
        )

        await #expect(throws: DynamicFeedService.ServiceError.loginRequired) {
            try await service.fetchFollowingFeed()
        }
    }

    @Test
    func feedRequestEnablesOpusStyleSoImageTextIsReturned() async throws {
        let recorder = DynamicFeedRequestRecorder()
        let responseData = Data(#"{"code":0,"data":{"items":[]}}"#.utf8)
        let service = DynamicFeedService(
            cookieProvider: LoggedInCookieProvider(),
            requestLoader: { request in
                await recorder.record(request.url)
                let url = request.url ?? URL(string: "https://api.bilibili.com")!
                return (
                    responseData,
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        _ = try await service.fetchFollowingFeedPage()

        let requestedURL = try #require(await recorder.requestedURL())
        let components = try #require(URLComponents(url: requestedURL, resolvingAgainstBaseURL: false))
        let features = components.queryItems?.first(where: { $0.name == "features" })?.value
        #expect(features == "itemOpusStyle")
    }

    @Test
    func feedChainCachesIdenticalPagesAndExplicitRefreshBypassesCache() async throws {
        let recorder = DynamicFeedRequestRecorder()
        let responseData = Data(
            #"{"code":0,"data":{"items":[],"offset":"opaque-next"}}"#.utf8
        )
        let service = DynamicFeedService(
            cookieProvider: LoggedInCookieProvider(),
            requestLoader: { request in
                await recorder.record(request.url)
                let url = request.url ?? URL(string: "https://api.bilibili.com")!
                return (
                    responseData,
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        let first = try await service.fetchFollowingFeedPage()
        let cached = try await service.fetchFollowingFeedPage()
        #expect(first == cached)
        #expect(await recorder.requestCount() == 1)

        let refreshed = try await service.refreshFollowingFeedPage()
        #expect(refreshed == first)
        #expect(await recorder.requestCount() == 2)
    }

    @Test
    func decodeCardsFallsBackToGenericMajorExtraction() throws {
        let data = Data(genericMajorPayload.utf8)
        let cards = try DynamicFeedService.decodeCards(from: data)

        #expect(cards.count == 1)

        let card = try #require(cards.first)
        #expect(card.kind == .video)
        #expect(card.text == "合集标题")
        #expect(card.coverURLs.first?.absoluteString == "https://i0.hdslb.com/bfs/archive/ugc-season-cover.jpg")
        #expect(card.targetURL.absoluteString == "https://www.bilibili.com/video/BV1zz411c7mE/")
        #expect(card.videoURL?.absoluteString == "https://www.bilibili.com/video/BV1zz411c7mE/")
    }

    @Test
    func articleDynamicsPreferCVIDOverOpusFallbackAndCanonicalizeTarget() throws {
        let payload = #"""
        {"code":0,"data":{"items":[{
          "id_str":"999","type":"DYNAMIC_TYPE_ARTICLE",
          "basic":{"jump_url":"https://www.bilibili.com/opus/999"},
          "modules":{"module_author":{"name":"作者"},"module_dynamic":{"major":{
            "type":"MAJOR_TYPE_ARTICLE",
            "article":{"id":"123","title":"专栏","jump_url":"https://www.bilibili.com/opus/999"}
          }}}
        }]}}
        """#

        let card = try #require(DynamicFeedService.decodeCards(from: Data(payload.utf8)).first)
        #expect(card.kind == .articleLike)
        #expect(card.targetURL.absoluteString == "https://www.bilibili.com/read/cv123")
    }

    @Test
    func imageDynamicInlineLinkDoesNotReplaceItsOwnDetailTarget() throws {
        let payload = #"""
        {"code":0,"data":{"items":[{
          "id_str":"777","type":"DYNAMIC_TYPE_DRAW",
          "modules":{"module_author":{"name":"作者"},"module_dynamic":{"major":{
            "type":"MAJOR_TYPE_OPUS",
            "opus":{
              "summary":{"text":"带话题的图文","rich_text_nodes":[
                {"text":"#话题#","jump_url":"https://search.bilibili.com/all?keyword=topic"}
              ]},
              "pics":[{"url":"https://i0.hdslb.com/bfs/new_dyn/pic.jpg"}]
            }
          }}}
        }]}}
        """#

        let card = try #require(DynamicFeedService.decodeCards(from: Data(payload.utf8)).first)
        #expect(card.kind == .image)
        #expect(card.targetURL.absoluteString == "https://www.bilibili.com/opus/777")
    }

    @Test
    func imageDynamicCanonicalizesNativeDetailScheme() throws {
        let payload = #"""
        {"code":0,"data":{"items":[{
          "id_str":"888","type":"DYNAMIC_TYPE_DRAW",
          "basic":{"jump_url":"bilibili://following/detail/888"},
          "modules":{"module_author":{"name":"作者"},"module_dynamic":{"major":{
            "type":"MAJOR_TYPE_DRAW",
            "draw":{"items":[{"src":"https://i0.hdslb.com/bfs/new_dyn/pic.jpg"}]}
          }}}
        }]}}
        """#

        let card = try #require(DynamicFeedService.decodeCards(from: Data(payload.utf8)).first)
        #expect(card.targetURL.absoluteString == "https://www.bilibili.com/opus/888")
    }

    @Test
    func imageDynamicBuildsCompleteTextFromOpusRichTextNodes() throws {
        let payload = #"""
        {"code":0,"data":{"items":[{
          "id_str":"889","type":"DYNAMIC_TYPE_DRAW",
          "modules":{"module_author":{"name":"作者"},"module_dynamic":{"major":{
            "type":"MAJOR_TYPE_OPUS",
            "opus":{
              "summary":{"rich_text_nodes":[
                {"text":"第一段"},
                {"text":"[doge]","emoji":{"icon_url":"https://i0.hdslb.com/bfs/emote/doge.png"}},
                {"text":"\n第二段完整文本"}
              ]},
              "pics":[{"url":"https://i0.hdslb.com/bfs/new_dyn/pic.jpg"}]
            }
          }}}
        }]}}
        """#

        let card = try #require(DynamicFeedService.decodeCards(from: Data(payload.utf8)).first)
        #expect(card.text == "第一段[doge]\n第二段完整文本")
        #expect(card.coverURLs.count == 1)
    }
}

private struct EmptyCookieProvider: CookieSnapshotProvider {
    // A completed authoritative empty read, not an uncertain initialization.
    var sessionReadiness: CookieSessionReadiness { .anonymous }
    func loadCookies() async -> [HTTPCookie] {
        []
    }

    func attachCookies(to request: URLRequest) -> URLRequest {
        request
    }
}

private struct LoggedInCookieProvider: CookieSnapshotProvider {
    func loadCookies() async -> [HTTPCookie] {
        [
            HTTPCookie(properties: [
                .domain: ".bilibili.com",
                .path: "/",
                .name: "SESSDATA",
                .value: "fixture-session",
                .secure: "TRUE",
            ]),
        ].compactMap { $0 }
    }
}

private actor DynamicFeedRequestRecorder {
    private var url: URL?
    private var count = 0

    func record(_ url: URL?) {
        self.url = url
        count += 1
    }

    func requestedURL() -> URL? {
        url
    }

    func requestCount() -> Int {
        count
    }
}

private let samplePayload = """
{
  "code": 0,
  "message": "0",
  "data": {
    "items": [
      {
        "id_str": "123",
        "type": "DYNAMIC_TYPE_AV",
        "basic": {
          "comment_id_str": "123",
          "jump_url": "//www.bilibili.com/video/BV1xx411c7mD"
        },
        "modules": {
          "module_author": {
            "name": "Tech UP",
            "face": "https://i0.hdslb.com/bfs/face/video.jpg",
            "pub_time": "5分钟前"
          },
          "module_dynamic": {
            "desc": {
              "text": "视频动态正文"
            },
            "major": {
              "type": "MAJOR_TYPE_ARCHIVE",
              "archive": {
                "title": "视频标题",
                "cover": "https://i0.hdslb.com/bfs/archive/cover.jpg",
                "jump_url": "https://www.bilibili.com/video/BV1xx411c7mD"
              }
            }
          }
        }
      },
      {
        "id_str": "456",
        "type": "DYNAMIC_TYPE_DRAW",
        "basic": {
          "comment_id_str": "456"
        },
        "modules": {
          "module_author": {
            "name": "Drawer",
            "face": "//i0.hdslb.com/bfs/face/draw.jpg",
            "pub_time": "昨天"
          },
          "module_dynamic": {
            "desc": {
              "text": "图文动态正文"
            },
            "major": {
              "type": "MAJOR_TYPE_OPUS",
              "opus": {
                "summary": {
                  "text": "图文动态正文"
                },
                "pics": [
                  {
                    "url": "https://i0.hdslb.com/bfs/new_dyn/pic1.jpg"
                  },
                  {
                    "url": "https://i0.hdslb.com/bfs/new_dyn/pic2.jpg"
                  }
                ]
              }
            }
          }
        }
      }
    ]
  }
}
"""

private actor DynamicSnapshotSaveCookies: CookieSnapshotProvider {
    nonisolated var sessionReadiness: CookieSessionReadiness { .authenticated }
    private var continuation: CheckedContinuation<[HTTPCookie], Never>?
    private var readerWaiters: [CheckedContinuation<Void, Never>] = []
    func loadCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            readerWaiters.forEach { $0.resume() }
            readerWaiters.removeAll()
        }
    }
    func waitUntilReading() async {
        if continuation != nil { return }
        await withCheckedContinuation { readerWaiters.append($0) }
    }
    func release() {
        continuation?.resume(returning: [HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: "DedeUserID", .value: "42"])!])
        continuation = nil
    }
}

private let genericMajorPayload = """
{
  "code": 0,
  "message": "0",
  "data": {
    "items": [
      {
        "id_str": "789",
        "type": "DYNAMIC_TYPE_UGC_SEASON",
        "modules": {
          "module_author": {
            "name": "Season UP",
            "face": "https://i0.hdslb.com/bfs/face/season.jpg",
            "pub_time": "刚刚"
          },
          "module_dynamic": {
            "major": {
              "type": "MAJOR_TYPE_UGC_SEASON",
              "ugc_season": {
                "title": "合集标题",
                "cover": "https://i0.hdslb.com/bfs/archive/ugc-season-cover.jpg",
                "jump_url": "https://www.bilibili.com/video/BV1zz411c7mE"
              }
            }
          }
        }
      }
    ]
  }
}
"""
