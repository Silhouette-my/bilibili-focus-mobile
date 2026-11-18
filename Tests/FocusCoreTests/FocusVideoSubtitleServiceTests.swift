@testable import FocusCore
import Foundation
import Testing

struct FocusVideoSubtitleServiceTests {
    @Test
    func decodesTracksWithProtocolRelativeURLAndInt64Identifier() throws {
        let tracks = try FocusVideoSubtitleService.decodeTracksResponse(
            subtitleFixture(named: "video-subtitle-tracks")
        )

        #expect(tracks.count == 2)
        #expect(tracks[0].id == 9_223_372_036_854_775_000)
        #expect(tracks[0].languageCode == "ai-zh")
        #expect(tracks[0].displayName == "中文（自动生成）")
        #expect(
            tracks[0].subtitleURL.absoluteString
                == "https://aisubtitle.hdslb.com/bfs/ai_subtitle/fixture-ai.json"
        )
        #expect(tracks[0].type == 1)
        #expect(tracks[0].aiStatus == 2)
        #expect(!tracks[0].isLocked)

        #expect(tracks[1].id == 42)
        #expect(tracks[1].languageCode == "en-US")
        #expect(tracks[1].aiType == 1)
        #expect(tracks[1].isLocked)
    }

    @Test
    func emptySubtitleListDecodesAsEmptyTracks() throws {
        let payload = Data(
            #"{"code":0,"data":{"subtitle":{"subtitles":[]}}}"#.utf8
        )

        #expect(
            try FocusVideoSubtitleService.decodeTracksResponse(payload).isEmpty
        )
    }

    @Test
    func decoderPreservesAPIErrorsAndRejectsMalformedPayloads() {
        #expect(
            throws: FocusVideoSubtitleService.ServiceError.api(
                code: -101,
                message: "账号未登录"
            )
        ) {
            try FocusVideoSubtitleService.decodeTracksResponse(
                Data(#"{"code":-101,"message":"账号未登录"}"#.utf8)
            )
        }

        #expect(throws: FocusVideoSubtitleService.ServiceError.invalidResponse) {
            try FocusVideoSubtitleService.decodeTracksResponse(
                Data(#"{"code":0,"data":{"subtitle":{}}}"#.utf8)
            )
        }
    }

    @Test
    func decodesBCCIntoSortedInt64MillisecondsAndFiltersInvalidCues() throws {
        let document = try FocusVideoSubtitleService.decodeBCC(
            subtitleFixture(named: "video-subtitle-bcc")
        )

        #expect(document.cues.count == 2)
        #expect(document.cues.map(\.id) == [0, 1])
        #expect(document.cues.map(\.startMilliseconds) == [125, 2_860])
        #expect(document.cues.map(\.endMilliseconds) == [2_860, 4_000])
        #expect(document.cues[0].location == 1)
        #expect(document.cues[0].content == "你好，字幕 🌏")
        #expect(document.cues[1].content == "第二行\n保留换行")
    }

    @Test
    func malformedBCCBodyIsRejected() {
        #expect(throws: FocusVideoSubtitleService.ServiceError.invalidResponse) {
            try FocusVideoSubtitleService.decodeBCC(
                Data(#"{"body":{"from":0,"to":1}}"#.utf8)
            )
        }
    }

    @Test
    func fetchesSignedTracksWithCookiesThenDownloadsBCCWithoutCookies() async throws {
        let recorder = SubtitleRequestRecorder(
            tracksData: try subtitleFixture(named: "video-subtitle-tracks"),
            bccData: try subtitleFixture(named: "video-subtitle-bcc")
        )
        let service = FocusVideoSubtitleService(
            cookieProvider: SubtitleCookieProvider(),
            wbiSigner: WBISigner(
                now: { Date(timeIntervalSince1970: 1_700_000_000) }
            ),
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        let tracks = try await service.fetchTracks(aid: 4_294_967_296, cid: 8_589_934_592)
        let document = try await service.fetchDocument(for: tracks[0])
        let requests = await recorder.requests
        let navigationRequest = try #require(
            requests.first(where: { $0.url?.path == "/x/web-interface/nav" })
        )
        let playerRequest = try #require(
            requests.first(where: { $0.url?.path == "/x/player/wbi/v2" })
        )
        let subtitleRequest = try #require(
            requests.first(where: {
                $0.url?.path == "/bfs/ai_subtitle/fixture-ai.json"
            })
        )
        let queryItems = try #require(
            URLComponents(
                url: playerRequest.url!,
                resolvingAgainstBaseURL: false
            )?.queryItems
        )
        let query = Dictionary(
            uniqueKeysWithValues: queryItems.compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )

        #expect(tracks.count == 2)
        #expect(document.cues.count == 2)
        #expect(query["aid"] == "4294967296")
        #expect(query["cid"] == "8589934592")
        #expect(query["isGaiaAvoided"] == "false")
        #expect(query["web_location"] == "1315873")
        #expect(query["wts"] == "1700000000")
        #expect(query["w_rid"]?.count == 32)
        #expect(
            navigationRequest.value(forHTTPHeaderField: "Cookie")?
                .contains("SESSDATA=fixture-session") == true
        )
        #expect(
            playerRequest.value(forHTTPHeaderField: "Cookie")?
                .contains("SESSDATA=fixture-session") == true
        )
        #expect(
            playerRequest.value(forHTTPHeaderField: "Referer")
                == "https://www.bilibili.com/video/av4294967296/"
        )
        #expect(subtitleRequest.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(subtitleRequest.value(forHTTPHeaderField: "Referer") == nil)
        #expect(!subtitleRequest.httpShouldHandleCookies)
    }

    @Test
    func rejectsUnsafeSubtitleURLsBeforeDownload() async {
        let service = FocusVideoSubtitleService(
            cookieProvider: EmptySubtitleCookieProvider(),
            requestLoader: { _ in
                Issue.record("unsafe subtitle URL must fail before network")
                throw FocusVideoSubtitleService.ServiceError.invalidResponse
            }
        )
        let maliciousTrack = FocusVideoSubtitleTrack(
            id: 1,
            languageCode: "zh-CN",
            displayName: "中文",
            subtitleURL: URL(
                string: "https://aisubtitle.hdslb.com.evil.example/subtitle.json"
            )!,
            isLocked: false,
            type: 0,
            aiType: 0,
            aiStatus: 0
        )

        await #expect(
            throws: FocusVideoSubtitleService.ServiceError.unsafeSubtitleURL
        ) {
            try await service.fetchDocument(for: maliciousTrack)
        }

        #expect(throws: FocusVideoSubtitleService.ServiceError.unsafeSubtitleURL) {
            try FocusVideoSubtitleService.decodeTracksResponse(
                Data(
                    #"""
                    {"code":0,"data":{"subtitle":{"subtitles":[{
                      "id_str":"1",
                      "subtitle_url":"http://aisubtitle.hdslb.com/subtitle.json"
                    }]}}}
                    """#.utf8
                )
            )
        }
    }

    @Test
    func preservesPlayerAndBCCHTTPStatusCodes() async throws {
        let recorder = SubtitleHTTPFailureRecorder()
        let service = FocusVideoSubtitleService(
            cookieProvider: EmptySubtitleCookieProvider(),
            wbiSigner: WBISigner(
                now: { Date(timeIntervalSince1970: 1_700_000_000) }
            ),
            requestLoader: { request in
                try await recorder.response(for: request)
            }
        )

        await #expect(
            throws: FocusVideoSubtitleService.ServiceError.httpStatus(code: 429)
        ) {
            try await service.fetchTracks(aid: 42, cid: 4201)
        }

        let track = FocusVideoSubtitleTrack(
            id: 1,
            languageCode: "zh-CN",
            displayName: "中文",
            subtitleURL: URL(
                string: "https://aisubtitle.hdslb.com/bfs/subtitle/rate-limited.json"
            )!,
            isLocked: false,
            type: 0,
            aiType: 0,
            aiStatus: 0
        )
        await #expect(
            throws: FocusVideoSubtitleService.ServiceError.httpStatus(code: 503)
        ) {
            try await service.fetchDocument(for: track)
        }
    }

    @Test
    func invalidVideoIdentifiersFailBeforeNetwork() async {
        let service = FocusVideoSubtitleService(
            cookieProvider: EmptySubtitleCookieProvider(),
            requestLoader: { _ in
                Issue.record("invalid identifiers must fail before network")
                throw FocusVideoSubtitleService.ServiceError.invalidResponse
            }
        )

        await #expect(
            throws: FocusVideoSubtitleService.ServiceError.invalidParameters
        ) {
            try await service.fetchTracks(aid: 0, cid: -1)
        }
    }
}

private struct SubtitleCookieProvider: CookieSnapshotProvider {
    func loadCookies() async -> [HTTPCookie] {
        [
            makeCookie(
                domain: ".bilibili.com",
                name: "SESSDATA",
                value: "fixture-session"
            ),
            makeCookie(
                domain: ".bilibili.com",
                name: "bili_jct",
                value: "fixture-csrf"
            ),
            makeCookie(
                domain: ".example.com",
                name: "SESSDATA",
                value: "wrong-domain"
            ),
        ].compactMap { $0 }
    }

    private func makeCookie(
        domain: String,
        name: String,
        value: String
    ) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
        ])
    }
}

private struct EmptySubtitleCookieProvider: CookieSnapshotProvider {
    func loadCookies() async -> [HTTPCookie] {
        []
    }
}

private actor SubtitleRequestRecorder {
    private let tracksData: Data
    private let bccData: Data
    private(set) var requests: [URLRequest] = []

    init(tracksData: Data, bccData: Data) {
        self.tracksData = tracksData
        self.bccData = bccData
    }

    func response(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let data: Data
        switch request.url?.path {
        case "/x/web-interface/nav":
            data = Data(subtitleNavigationPayload.utf8)
        case "/x/player/wbi/v2":
            data = tracksData
        case "/bfs/ai_subtitle/fixture-ai.json":
            data = bccData
        default:
            data = Data(#"{"code":-404,"message":"unexpected"}"#.utf8)
        }
        return (data, subtitleHTTPResponse(for: request, statusCode: 200))
    }
}

private actor SubtitleHTTPFailureRecorder {
    func response(for request: URLRequest) throws -> (Data, URLResponse) {
        let statusCode: Int
        let data: Data
        switch request.url?.path {
        case "/x/web-interface/nav":
            statusCode = 200
            data = Data(subtitleNavigationPayload.utf8)
        case "/x/player/wbi/v2":
            statusCode = 429
            data = Data(#"{"code":-412,"message":"rate limited"}"#.utf8)
        default:
            statusCode = 503
            data = Data()
        }
        return (
            data,
            subtitleHTTPResponse(for: request, statusCode: statusCode)
        )
    }
}

private let subtitleNavigationPayload =
    #"{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png","sub_url":"https://i0.hdslb.com/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png"}}}"#

private func subtitleHTTPResponse(
    for request: URLRequest,
    statusCode: Int
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url ?? URL(string: "https://api.bilibili.com/")!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
}

private func subtitleFixture(named name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json")
    )
    return try Data(contentsOf: url)
}
