@testable import FocusCore
import Foundation
import Testing

struct FocusVideoDetailServiceTests {
    @Test
    func extractsOnlySupportedNativeVideoIdentifiersAndPageNumber() {
        let bvidURL = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/?p=3")!
        let aidURL = URL(string: "https://m.bilibili.com/video/av123456/")!
        let bangumiURL = URL(string: "https://www.bilibili.com/bangumi/play/ep123")!
        let unrelatedURL = URL(string: "https://example.com/video/BV1xx411c7mD/")!

        #expect(FocusVideoIdentifier.extract(from: bvidURL) == .bvid("BV1xx411c7mD"))
        #expect(FocusVideoIdentifier.extract(from: aidURL) == .aid(123_456))
        #expect(FocusVideoIdentifier.extract(from: bangumiURL) == nil)
        #expect(FocusVideoIdentifier.extract(from: unrelatedURL) == nil)
        #expect(FocusVideoDetailService.requestedPageNumber(from: bvidURL) == 3)
    }

    @Test
    func decodesNativeDetailPagesStatisticsAndEpisodeGroups() throws {
        let detail = try FocusVideoDetailService.decodeDetailResponse(Data(detailPayload.utf8))

        #expect(detail.bvid == "BV1xx411c7mD")
        #expect(detail.aid == 42)
        #expect(detail.owner.mid == 1001)
        #expect(detail.owner.avatarURL?.scheme == "https")
        #expect(detail.statistics.likes == 321)
        #expect(detail.pages.map(\.cid) == [4201, 4202])
        #expect(detail.pages[1].title == "第二集")
        #expect(detail.episodeGroups.count == 1)
        #expect(detail.episodeGroups[0].episodes.first?.bvid == "BV1zz411c7mE")
        #expect(abs(detail.aspectRatio - (16.0 / 9.0)) < 0.001)
    }

    @Test
    func commentsPreserveRichNodesFallbackEmotesLinksAndPreviewReplies() throws {
        let payload = #"""
        {"code":0,"data":{"replies":[{
          "rpid":1,"mid":10,"like":2,"rcount":1,"ctime":1700000000,
          "member":{"uname":"一级","avatar":"//i0.hdslb.com/a.jpg"},
          "content":{"message":"开始[doge]链接","rich_text_nodes":[
            {"text":"开始"},
            {"orig_text":"[doge]","emoji":{"icon_url":"//i0.hdslb.com/doge.webp","meta":{"size":2}}},
            {"text":"链接","jump_url":"https://www.bilibili.com/read/cv1"}
          ]},
          "replies":[{
            "rpid":2,"mid":11,"like":0,"rcount":0,"ctime":1700000001,
            "member":{"uname":"回复","avatar":"//i0.hdslb.com/b.jpg"},
            "content":{"message":"连续[大doge][doge]\n未知[猫]","emote":{
              "[doge]":{"url":"//i0.hdslb.com/doge.webp","meta":{"size":2}},
              "[大doge]":{"url":"//i0.hdslb.com/big.gif","meta":{"size":3}}
            }}
          }]
        }]}}
        """#

        let comments = try FocusVideoDetailService.decodeCommentsResponse(Data(payload.utf8))
        let comment = try #require(comments.first)
        #expect(comment.contentRuns.count == 3)
        guard case let .emote(alt, url, width, height, animated) = comment.contentRuns[1] else {
            Issue.record("Expected rich node emote")
            return
        }
        #expect(alt == "[doge]")
        #expect(url.absoluteString == "https://i0.hdslb.com/doge.webp")
        #expect(width == 2)
        #expect(height == 2)
        #expect(animated)
        guard case let .text(_, _, _, _, _, _, link) = comment.contentRuns[2] else {
            Issue.record("Expected linked text")
            return
        }
        #expect(link?.absoluteString == "https://www.bilibili.com/read/cv1")
        let reply = try #require(comment.previewReplies.first)
        #expect(reply.contentRuns.compactMap { run in
            if case let .emote(alt, _, _, _, _) = run { return alt }
            return nil
        } == ["[大doge]", "[doge]"])
        #expect(reply.contentRuns.map(\.plainText).joined() == reply.message)
    }

    @Test
    func commentPageDecoderKeepsOpaqueNextOffsetAndTotalCount() throws {
        let payload = #"""
        {"code":0,"data":{
          "cursor":{
            "all_count":9223372036854775000,
            "pagination_reply":{"next_offset":"opaque:next/42?session=abc"}
          },
          "replies":[]
        }}
        """#

        let page = try FocusVideoDetailService.decodeCommentsPageResponse(
            Data(payload.utf8)
        )

        #expect(page.comments.isEmpty)
        #expect(page.totalCount == 9_223_372_036_854_775_000)
        #expect(page.nextCursor?.nextOffset == "opaque:next/42?session=abc")
    }

    @Test
    func commentPagingSendsReturnedOpaqueOffsetAndNeverNumericPageParameters() async throws {
        let recorder = CommentPageRequestRecorder()
        let service = FocusVideoDetailService(
            cookieProvider: VideoActionCookieProvider(),
            wbiSigner: WBISigner(),
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        let firstPage = try await service.fetchCommentsPage(aid: 42)
        let cursor = try #require(firstPage.nextCursor)
        let secondPage = try await service.fetchCommentsPage(aid: 42, cursor: cursor)
        let requests = await recorder.requests.filter {
            $0.url?.path == "/x/v2/reply/wbi/main"
        }

        #expect(firstPage.totalCount == 21)
        #expect(cursor.nextOffset == "opaque:next/42?session=abc")
        #expect(secondPage.nextCursor == nil)
        #expect(requests.count == 2)

        let firstURL = try #require(requests.first?.url)
        let secondURL = try #require(requests.last?.url)
        let firstQuery = try #require(URLComponents(
            url: firstURL,
            resolvingAgainstBaseURL: false
        )?.queryItems)
        let secondQuery = try #require(URLComponents(
            url: secondURL,
            resolvingAgainstBaseURL: false
        )?.queryItems)
        let firstPagination = try #require(
            firstQuery.first(where: { $0.name == "pagination_str" })?.value
        )
        let secondPagination = try #require(
            secondQuery.first(where: { $0.name == "pagination_str" })?.value
        )
        let firstObject = try #require(
            JSONSerialization.jsonObject(with: Data(firstPagination.utf8))
                as? [String: String]
        )
        let secondObject = try #require(
            JSONSerialization.jsonObject(with: Data(secondPagination.utf8))
                as? [String: String]
        )

        #expect(firstObject["offset"] == "")
        #expect(secondObject["offset"] == cursor.nextOffset)
        #expect(secondQuery.first(where: { $0.name == "mode" })?.value == "3")
        #expect(
            secondQuery.first(where: { $0.name == "web_location" })?.value
                == "1315875"
        )
        #expect(requests.allSatisfy { request in
            let names = Set(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .map(\.name) ?? []
            )
            return names.isDisjoint(with: ["pn", "ps", "sort", "next"])
        })
    }

    @Test
    func playbackDecoderPrefersProgressiveNonPCDNBackup() throws {
        let source = try FocusVideoDetailService.decodePlaybackResponse(
            Data(progressivePayload.utf8),
            headers: ["Referer": "https://www.bilibili.com/"]
        )

        guard case let .progressive(urls) = source.stream else {
            Issue.record("Expected progressive playback source")
            return
        }
        #expect(urls.count == 1)
        #expect(urls[0].host == "upos-sz-mirrorcos.bilivideo.com")
        #expect(source.headers["Referer"] == "https://www.bilibili.com/")
    }

    @Test
    func playbackDecoderSelectsH264VideoAndHighestAudio() throws {
        let source = try FocusVideoDetailService.decodePlaybackResponse(
            Data(dashPayload.utf8),
            headers: [:]
        )

        guard case let .dash(videoURL, audioURL) = source.stream else {
            Issue.record("Expected DASH playback source")
            return
        }
        #expect(videoURL.absoluteString.contains("avc-high.m4s"))
        #expect(audioURL?.absoluteString.contains("audio-high.m4s") == true)
    }

    @Test
    func playbackResumeDecoderKeepsServerMilliseconds() throws {
        let progress = try FocusVideoDetailService.decodePlaybackResumeResponse(
            Data(#"{"code":0,"data":{"last_play_cid":4203,"last_play_time":87000}}"#.utf8)
        )

        #expect(progress.cid == 4203)
        #expect(progress.positionMilliseconds == 87_000)
    }

    @Test
    func playbackResumePolicyRequiresMatchingCIDAndSkipsTheTail() {
        let resumable = FocusVideoPlaybackResume(
            cid: 4203,
            positionMilliseconds: 87_000
        )

        #expect(
            FocusVideoPlaybackResumePolicy.initialPositionMilliseconds(
                resume: resumable,
                selectedCID: 4203,
                durationSeconds: 120
            ) == 87_000
        )
        #expect(
            FocusVideoPlaybackResumePolicy.initialPositionMilliseconds(
                resume: resumable,
                selectedCID: 4202,
                durationSeconds: 120
            ) == 0
        )
        #expect(
            FocusVideoPlaybackResumePolicy.initialPositionMilliseconds(
                resume: FocusVideoPlaybackResume(
                    cid: 4203,
                    positionMilliseconds: 4_999
                ),
                selectedCID: 4203,
                durationSeconds: 120
            ) == 0
        )
        #expect(
            FocusVideoPlaybackResumePolicy.initialPositionMilliseconds(
                resume: FocusVideoPlaybackResume(
                    cid: 4203,
                    positionMilliseconds: 119_000
                ),
                selectedCID: 4203,
                durationSeconds: 120
            ) == 0
        )
    }

    @Test
    func playbackResumeRequestUsesAidAndSelectedCID() async throws {
        let recorder = PlaybackResumeRequestRecorder()
        let signer = WBISigner()
        let service = FocusVideoDetailService(
            cookieProvider: VideoActionCookieProvider(),
            wbiSigner: signer,
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        let progress = try await service.fetchPlaybackResume(aid: 42, cid: 4203)
        let requests = await recorder.requests
        let request = try #require(
            requests.first(where: { $0.url?.path == "/x/player/wbi/v2" })
        )
        let queryItems = URLComponents(
            url: try #require(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []

        #expect(progress == FocusVideoPlaybackResume(cid: 4203, positionMilliseconds: 87_000))
        #expect(requests.filter { $0.url?.path == "/x/web-interface/nav" }.count == 1)
        #expect(queryItems.first(where: { $0.name == "aid" })?.value == "42")
        #expect(queryItems.first(where: { $0.name == "cid" })?.value == "4203")
        #expect(queryItems.first(where: { $0.name == "isGaiaAvoided" })?.value == "false")
        #expect(queryItems.first(where: { $0.name == "web_location" })?.value == "1315873")
        #expect(queryItems.first(where: { $0.name == "wts" }) != nil)
        #expect(queryItems.first(where: { $0.name == "w_rid" })?.value?.count == 32)
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("SESSDATA=session-token") == true)
    }

    @Test
    func playbackDoesNotForwardBilibiliSessionCookiesToCrossOriginMedia() async throws {
        let recorder = PlaybackMediaRequestRecorder(payload: progressivePayload)
        let service = FocusVideoDetailService(
            cookieProvider: VideoActionCookieProvider(),
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        let source = try await service.fetchPlayback(bvid: "BV1xx411c7mD", cid: 4201)
        let apiRequest = try #require(await recorder.requests.first)

        guard case let .progressive(urls) = source.stream else {
            Issue.record("Expected progressive playback source")
            return
        }
        #expect(urls.first?.host == "upos-sz-mirrorcos.bilivideo.com")
        #expect(source.headers["Cookie"] == nil)
        #expect(source.headers["Referer"] == "https://www.bilibili.com/video/BV1xx411c7mD/")
        #expect(apiRequest.url?.host == "api.bilibili.com")
        #expect(apiRequest.value(forHTTPHeaderField: "Cookie")?.contains("SESSDATA=session-token") == true)
    }

    @Test
    func playbackOmitsLoginCookiesEvenForSameDomainMediaToCloseRedirectInheritance() async throws {
        let sameDomainPayload = progressivePayload.replacingOccurrences(
            of: "https://upos-sz-mirrorcos.bilivideo.com/progressive.mp4",
            with: "https://api.bilibili.com/media/progressive.mp4"
        )
        let service = FocusVideoDetailService(
            cookieProvider: VideoActionCookieProvider(),
            requestLoader: { request in
                let url = try #require(request.url)
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (Data(sameDomainPayload.utf8), response)
            }
        )

        let source = try await service.fetchPlayback(bvid: "BV1xx411c7mD", cid: 4201)

        guard case let .progressive(urls) = source.stream else {
            Issue.record("Expected progressive playback source")
            return
        }
        #expect(urls.first?.host == "api.bilibili.com")
        #expect(source.headers["Cookie"] == nil)
    }

    @Test
    func actionServiceSendsAuthenticatedLikeCoinAndFavoriteForms() async throws {
        let recorder = VideoActionRequestRecorder()
        let service = FocusVideoActionService(
            cookieProvider: VideoActionCookieProvider(),
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        try await service.setLiked(aid: 42, liked: true)
        try await service.addCoin(aid: 42)
        try await service.reportWatchHistory(aid: 42, cid: 4201, progressSeconds: 87)
        let folderID = try await service.setFavorited(aid: 42, favorited: true, folderID: nil)
        let requests = await recorder.requests

        #expect(folderID == 9001)
        let likeRequest = try #require(requests.first(where: { $0.url?.path.hasSuffix("/archive/like") == true }))
        let coinRequest = try #require(requests.first(where: { $0.url?.path.hasSuffix("/coin/add") == true }))
        let historyRequest = try #require(requests.first(where: { $0.url?.path == "/x/v2/history/report" }))
        let favoriteRequest = try #require(requests.first(where: { $0.url?.path.hasSuffix("/fav/resource/deal") == true }))
        let likeBody = String(data: try #require(likeRequest.httpBody), encoding: .utf8) ?? ""
        let coinBody = String(data: try #require(coinRequest.httpBody), encoding: .utf8) ?? ""
        let historyBody = String(data: try #require(historyRequest.httpBody), encoding: .utf8) ?? ""
        let favoriteBody = String(data: try #require(favoriteRequest.httpBody), encoding: .utf8) ?? ""

        #expect(likeRequest.value(forHTTPHeaderField: "Cookie")?.contains("bili_jct=csrf-token") == true)
        #expect(likeBody.contains("aid=42"))
        #expect(likeBody.contains("like=1"))
        #expect(likeBody.contains("csrf=csrf-token"))
        #expect(coinBody.contains("multiply=1"))
        #expect(historyBody.contains("aid=42"))
        #expect(historyBody.contains("cid=4201"))
        #expect(historyBody.contains("progress=87"))
        #expect(historyBody.contains("csrf=csrf-token"))
        #expect(favoriteBody.contains("add_media_ids=9001"))
        #expect(favoriteBody.contains("rid=42"))
    }

    @Test
    func danmakuDecodersSupportThreeModesAndClosedMarker() throws {
        let view = try FocusVideoDetailService.decodeDanmakuView(danmakuViewFixture())
        let segment = try FocusVideoDetailService.decodeDanmakuSegment(danmakuSegmentFixture())
        let closed = try FocusVideoDetailService.decodeDanmakuSegment(Data([0x10, 0x01]))

        #expect(view.segmentDurationMilliseconds == 360_000)
        #expect(view.totalSegments == 2)
        #expect(view.count == 3)
        #expect(segment.danmakus.map(\.mode) == [.scrolling, .top, .bottom])
        #expect(segment.danmakus.first?.content == "第一条弹幕")
        #expect(segment.danmakus.first?.colorRGB == 0xff3366)
        #expect(segment.danmakus[1].colorRGB == nil)
        #expect(closed.isClosed)
    }

    @Test
    func danmakuViewKeepsPositiveServerSegmentDurationBelowFallback() throws {
        let view = try FocusVideoDetailService.decodeDanmakuView(
            danmakuViewFixture(segmentDurationMilliseconds: 60_000)
        )

        #expect(view.segmentDurationMilliseconds == 60_000)
    }

    @Test
    func danmakuServiceSignsSegmentsAndRefreshesRejectedWBI() async throws {
        let recorder = DanmakuRequestRecorder()
        let signer = WBISigner()
        let service = FocusVideoDetailService(
            cookieProvider: VideoActionCookieProvider(),
            wbiSigner: signer,
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        _ = try await service.fetchDanmakuView(aid: 42, cid: 4201)
        let segment = try await service.fetchDanmakuSegment(aid: 42, cid: 4201, segmentIndex: 2)
        let requests = await recorder.requests

        #expect(segment.danmakus.count == 3)
        #expect(requests.filter { $0.url?.path == "/x/web-interface/nav" }.count == 2)
        #expect(requests.filter { $0.url?.path == "/x/v2/dm/wbi/web/seg.so" }.count == 2)
        let segmentRequest = try #require(requests.last(where: { $0.url?.path.hasSuffix("/seg.so") == true }))
        let query = segmentRequest.url?.query ?? ""
        #expect(query.contains("oid=4201"))
        #expect(query.contains("pid=42"))
        #expect(query.contains("segment_index=2"))
        #expect(query.contains("web_location=1550101"))
        #expect(query.contains("wts="))
        #expect(query.contains("w_rid="))
        #expect(segmentRequest.value(forHTTPHeaderField: "Cookie")?.contains("SESSDATA=session-token") == true)
        #expect(segmentRequest.value(forHTTPHeaderField: "Referer") == "https://www.bilibili.com/video/av42/")
    }
}

private struct VideoActionCookieProvider: CookieSnapshotProvider {
    func loadCookies() async -> [HTTPCookie] {
        [
            makeCookie(name: "SESSDATA", value: "session-token"),
            makeCookie(name: "bili_jct", value: "csrf-token"),
        ].compactMap { $0 }
    }

    private func makeCookie(name: String, value: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: ".bilibili.com",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
        ])
    }
}

private actor VideoActionRequestRecorder {
    private(set) var requests: [URLRequest] = []

    func response(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        let payload: String
        switch path {
        case "/x/web-interface/nav":
            payload = #"{"code":0,"data":{"isLogin":true,"mid":1001}}"#
        case "/x/v3/fav/folder/created/list-all":
            payload = #"{"code":0,"data":{"list":[{"id":9001,"title":"默认收藏夹"}]}}"#
        default:
            payload = #"{"code":0,"data":{}}"#
        }

        let url = request.url ?? URL(string: "https://api.bilibili.com/")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(payload.utf8), response)
    }
}

private actor PlaybackResumeRequestRecorder {
    private(set) var requests: [URLRequest] = []

    func response(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let payload: String
        switch request.url?.path {
        case "/x/web-interface/nav":
            payload = wbiNavigationPayload
        case "/x/player/wbi/v2":
            payload = #"{"code":0,"data":{"last_play_cid":4203,"last_play_time":87000}}"#
        default:
            payload = #"{"code":-404,"message":"unexpected"}"#
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.bilibili.com/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(payload.utf8), response)
    }
}

private actor CommentPageRequestRecorder {
    private(set) var requests: [URLRequest] = []
    private var commentRequestCount = 0

    func response(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let payload: String
        switch request.url?.path {
        case "/x/web-interface/nav":
            payload = wbiNavigationPayload
        case "/x/v2/reply/wbi/main":
            commentRequestCount += 1
            if commentRequestCount == 1 {
                payload = #"""
                {"code":0,"data":{
                  "cursor":{
                    "all_count":21,
                    "pagination_reply":{"next_offset":"opaque:next/42?session=abc"}
                  },
                  "replies":[]
                }}
                """#
            } else {
                payload = #"""
                {"code":0,"data":{
                  "cursor":{"all_count":21,"pagination_reply":{"next_offset":""}},
                  "replies":[]
                }}
                """#
            }
        default:
            payload = #"{"code":-404,"message":"unexpected"}"#
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.bilibili.com/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(payload.utf8), response)
    }
}

private actor PlaybackMediaRequestRecorder {
    private let payload: String
    private(set) var requests: [URLRequest] = []

    init(payload: String) {
        self.payload = payload
    }

    func response(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.bilibili.com/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(payload.utf8), response)
    }
}

private let wbiNavigationPayload =
    #"{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png","sub_url":"https://i0.hdslb.com/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png"}}}"#

private actor DanmakuRequestRecorder {
    private(set) var requests: [URLRequest] = []
    private var segmentRequestCount = 0

    func response(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        let data: Data
        let contentType: String
        switch path {
        case "/x/web-interface/nav":
            data = Data(wbiNavigationPayload.utf8)
            contentType = "application/json"
        case "/x/v2/dm/web/view":
            data = danmakuViewFixture()
            contentType = "application/octet-stream"
        case "/x/v2/dm/wbi/web/seg.so":
            segmentRequestCount += 1
            data = segmentRequestCount == 1
                ? Data(" \n {\"code\":-403,\"message\":\"expired\"}".utf8)
                : danmakuSegmentFixture()
            contentType = segmentRequestCount == 1 ? "application/json" : "application/octet-stream"
        default:
            data = Data(#"{"code":-404,"message":"unexpected"}"#.utf8)
            contentType = "application/json"
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.bilibili.com/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
        return (data, response)
    }
}

private func danmakuViewFixture(segmentDurationMilliseconds: UInt64 = 360_000) -> Data {
    let segment = protobufVarintField(1, segmentDurationMilliseconds) + protobufVarintField(2, 2)
    return protobufVarintField(1, 0)
        + protobufBytesField(4, segment)
        + protobufVarintField(8, 3)
        + protobufBytesField(99, Data([1, 2, 3]))
        + protobufFixed32Field(98, 0x12345678)
        + protobufFixed64Field(97, 0x123456789abcdef0)
}

private func danmakuSegmentFixture() -> Data {
    protobufBytesField(1, danmakuElement(id: 1, progress: 1_000, mode: 1, fontSize: 25, color: 0xff3366, content: "第一条弹幕", weight: 20))
        + protobufBytesField(1, danmakuElement(id: 2, progress: 2_000, mode: 5, fontSize: 36, color: 60_001, content: "顶部", weight: 10))
        + protobufBytesField(1, danmakuElement(id: 3, progress: 3_000, mode: 4, fontSize: 18, color: 0xffffff, content: "底部", weight: 1))
        + protobufBytesField(1, danmakuElement(id: 4, progress: 4_000, mode: 7, fontSize: 25, color: 0xffffff, content: "高级弹幕", weight: 99))
}

private func danmakuElement(
    id: UInt64,
    progress: UInt64,
    mode: UInt64,
    fontSize: UInt64,
    color: UInt64,
    content: String,
    weight: UInt64
) -> Data {
    protobufVarintField(1, id)
        + protobufVarintField(2, progress)
        + protobufVarintField(3, mode)
        + protobufVarintField(4, fontSize)
        + protobufVarintField(5, color)
        + protobufBytesField(7, Data(content.utf8))
        + protobufVarintField(9, weight)
        + protobufVarintField(11, 0)
        + protobufBytesField(30, Data([9, 8, 7]))
}

private func protobufVarintField(_ field: UInt64, _ value: UInt64) -> Data {
    protobufVarint(field << 3) + protobufVarint(value)
}

private func protobufBytesField(_ field: UInt64, _ value: Data) -> Data {
    protobufVarint((field << 3) | 2) + protobufVarint(UInt64(value.count)) + value
}

private func protobufFixed32Field(_ field: UInt64, _ value: UInt32) -> Data {
    protobufVarint((field << 3) | 5) + withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

private func protobufFixed64Field(_ field: UInt64, _ value: UInt64) -> Data {
    protobufVarint((field << 3) | 1) + withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

private func protobufVarint(_ rawValue: UInt64) -> Data {
    var value = rawValue
    var result = Data()
    while true {
        if value < 0x80 {
            result.append(UInt8(value))
            return result
        }
        result.append(UInt8(value & 0x7f) | 0x80)
        value >>= 7
    }
}

private let detailPayload = #"""
{
  "code": 0,
  "message": "0",
  "data": {
    "bvid": "BV1xx411c7mD",
    "aid": 42,
    "cid": 4201,
    "title": "原生详情测试视频",
    "desc": "测试简介",
    "pic": "//i0.hdslb.com/bfs/archive/cover.jpg",
    "duration": 240,
    "pubdate": 1710000000,
    "dimension": {"width": 1920, "height": 1080},
    "owner": {
      "mid": 1001,
      "name": "测试 UP 主",
      "face": "http://i0.hdslb.com/bfs/face/avatar.jpg"
    },
    "stat": {
      "view": 10000,
      "danmaku": 20,
      "reply": 30,
      "favorite": 40,
      "coin": 50,
      "share": 60,
      "like": 321
    },
    "pages": [
      {"page": 1, "cid": 4201, "part": "第一集", "duration": 120},
      {"page": 2, "cid": 4202, "part": "第二集", "duration": 120}
    ],
    "ugc_season": {
      "title": "测试合集",
      "sections": [
        {
          "title": "第一季",
          "episodes": [
            {
              "bvid": "BV1zz411c7mE",
              "aid": 43,
              "cid": 4301,
              "title": "合集下一集",
              "cover": "https://i0.hdslb.com/bfs/archive/next.jpg",
              "badge": "更新"
            }
          ]
        }
      ]
    }
  }
}
"""#

private let progressivePayload = #"""
{
  "code": 0,
  "data": {
    "quality": 80,
    "durl": [
      {
        "url": "https://example.mcdn.bilivideo.com/progressive.mp4",
        "backup_url": ["https://upos-sz-mirrorcos.bilivideo.com/progressive.mp4"]
      }
    ]
  }
}
"""#

private let dashPayload = #"""
{
  "code": 0,
  "data": {
    "quality": 80,
    "dash": {
      "video": [
        {"id": 80, "codecid": 12, "bandwidth": 9000, "baseUrl": "https://cdn.example/hevc.m4s"},
        {"id": 64, "codecid": 7, "bandwidth": 4000, "baseUrl": "https://cdn.example/avc-low.m4s"},
        {"id": 80, "codecid": 7, "bandwidth": 8000, "baseUrl": "https://cdn.example/avc-high.m4s"}
      ],
      "audio": [
        {"id": 30216, "bandwidth": 64000, "baseUrl": "https://cdn.example/audio-low.m4s"},
        {"id": 30280, "bandwidth": 192000, "baseUrl": "https://cdn.example/audio-high.m4s"}
      ]
    }
  }
}
"""#
