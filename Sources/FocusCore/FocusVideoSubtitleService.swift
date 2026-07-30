import Foundation

public struct FocusVideoSubtitleTrack: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let languageCode: String
    public let displayName: String
    public let subtitleURL: URL
    public let isLocked: Bool
    public let type: Int
    public let aiType: Int
    public let aiStatus: Int

    public init(
        id: Int64,
        languageCode: String,
        displayName: String,
        subtitleURL: URL,
        isLocked: Bool,
        type: Int,
        aiType: Int,
        aiStatus: Int
    ) {
        self.id = id
        self.languageCode = languageCode
        self.displayName = displayName
        self.subtitleURL = subtitleURL
        self.isLocked = isLocked
        self.type = type
        self.aiType = aiType
        self.aiStatus = aiStatus
    }
}

public struct FocusVideoSubtitleCue: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let startMilliseconds: Int64
    public let endMilliseconds: Int64
    public let location: Int
    public let content: String

    public init(
        id: Int64,
        startMilliseconds: Int64,
        endMilliseconds: Int64,
        location: Int,
        content: String
    ) {
        self.id = id
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.location = location
        self.content = content
    }
}

public struct FocusVideoSubtitleDocument: Codable, Equatable, Sendable {
    public let cues: [FocusVideoSubtitleCue]

    public init(cues: [FocusVideoSubtitleCue]) {
        self.cues = cues
    }
}

/// Discovers subtitle tracks through bilibili's WBI player endpoint and loads
/// the selected BCC document without forwarding account cookies to CDN hosts.
public actor FocusVideoSubtitleService {
    public enum ServiceError: Error, Equatable, Sendable, LocalizedError {
        case invalidParameters
        case invalidResponse
        case httpStatus(code: Int)
        case api(code: Int, message: String)
        case unsafeSubtitleURL

        public var errorDescription: String? {
            switch self {
            case .invalidParameters:
                return "字幕请求缺少有效的视频标识"
            case .invalidResponse:
                return "字幕接口返回了无效数据"
            case let .httpStatus(code):
                return "字幕请求失败（HTTP \(code)）"
            case let .api(code, message):
                return "字幕接口失败（\(code)）：\(message)"
            case .unsafeSubtitleURL:
                return "字幕下载地址不受信任"
            }
        }
    }

    public typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let trustedSubtitleDomains = [
        "hdslb.com",
        "bilibili.com",
        "bilivideo.com",
    ]

    private let cookieProvider: any CookieSnapshotProvider
    private let requestLoader: RequestLoader
    private let wbiSigner: WBISigner

    public init(
        cookieProvider: any CookieSnapshotProvider,
        requestLoader: @escaping RequestLoader = { request in
            try await BiliAPINetwork.data(for: request)
        }
    ) {
        self.cookieProvider = cookieProvider
        self.requestLoader = requestLoader
        wbiSigner = .shared
    }

    init(
        cookieProvider: any CookieSnapshotProvider,
        wbiSigner: WBISigner,
        requestLoader: @escaping RequestLoader
    ) {
        self.cookieProvider = cookieProvider
        self.requestLoader = requestLoader
        self.wbiSigner = wbiSigner
    }

    public func fetchTracks(aid: Int64, cid: Int64) async throws -> [FocusVideoSubtitleTrack] {
        guard aid > 0, cid > 0 else {
            throw ServiceError.invalidParameters
        }

        let cookies = await cookieProvider.loadCookies()
        let referer = "https://www.bilibili.com/video/av\(aid)/"
        let navigationRequest = Self.makeAPIRequest(
            url: BiliAPIContractCatalog.require("credential.info.valid").url,
            referer: referer,
            cookies: cookies
        )

        let response: WBISigner.HTTPResponse
        do {
            response = try await wbiSigner.execute(
                parameters: [
                    "aid": String(aid),
                    "cid": String(cid),
                    "isGaiaAvoided": "false",
                    "web_location": "1315873",
                ],
                navigationRequest: navigationRequest,
                requestLoader: requestLoader
            ) { signedQuery in
                guard var components = URLComponents(
                    url: BiliAPIContractCatalog.require("video.info.get_player_info").url,
                    resolvingAgainstBaseURL: false
                ) else {
                    throw WBISigner.SigningError.invalidRequest
                }
                components.percentEncodedQuery = signedQuery
                guard let url = components.url else {
                    throw WBISigner.SigningError.invalidRequest
                }
                return Self.makeAPIRequest(
                    url: url,
                    referer: referer,
                    cookies: cookies
                )
            }
        } catch is WBISigner.SigningError {
            throw ServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(response.response.statusCode) else {
            throw ServiceError.httpStatus(code: response.response.statusCode)
        }
        return try Self.decodeTracksResponse(response.data)
    }

    public func fetchDocument(
        for track: FocusVideoSubtitleTrack
    ) async throws -> FocusVideoSubtitleDocument {
        let subtitleURL = try Self.validatedSubtitleURL(track.subtitleURL.absoluteString)
        var request = URLRequest(url: subtitleURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        request.setValue(FocusVideoDetailService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await requestLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw ServiceError.httpStatus(code: httpResponse.statusCode)
        }
        return try Self.decodeBCC(data)
    }

    public nonisolated static func decodeTracksResponse(
        _ data: Data
    ) throws -> [FocusVideoSubtitleTrack] {
        let root = try decodedJSONObject(data)
        guard let code = int64Value(root["code"]) else {
            throw ServiceError.invalidResponse
        }
        guard code == 0 else {
            throw ServiceError.api(
                code: Int(clamping: code),
                message: stringValue(root["message"]) ?? "未知错误"
            )
        }
        guard
            let payload = root["data"] as? [String: Any],
            let subtitle = payload["subtitle"] as? [String: Any],
            let rawTracks = subtitle["subtitles"] as? [Any]
        else {
            throw ServiceError.invalidResponse
        }

        return try rawTracks.compactMap { rawTrack in
            guard let dictionary = rawTrack as? [String: Any] else {
                return nil
            }
            return try decodeTrack(dictionary)
        }
    }

    public nonisolated static func decodeBCC(
        _ data: Data
    ) throws -> FocusVideoSubtitleDocument {
        let root = try decodedJSONObject(data)
        guard let body = root["body"] as? [Any] else {
            throw ServiceError.invalidResponse
        }

        var decodedCues: [(sourceIndex: Int, cue: FocusVideoSubtitleCue)] = []
        decodedCues.reserveCapacity(body.count)
        for (sourceIndex, rawCue) in body.enumerated() {
            guard
                let dictionary = rawCue as? [String: Any],
                let startSeconds = doubleValue(dictionary["from"]),
                let endSeconds = doubleValue(dictionary["to"]),
                let startMilliseconds = milliseconds(from: startSeconds),
                let endMilliseconds = milliseconds(from: endSeconds),
                endMilliseconds > startMilliseconds,
                let content = dictionary["content"] as? String,
                !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }

            let location = int64Value(dictionary["location"])
                .map { Int(clamping: $0) } ?? 2
            decodedCues.append((
                sourceIndex: sourceIndex,
                cue: FocusVideoSubtitleCue(
                    id: 0,
                    startMilliseconds: startMilliseconds,
                    endMilliseconds: endMilliseconds,
                    location: location,
                    content: content
                )
            ))
        }

        decodedCues.sort { lhs, rhs in
            if lhs.cue.startMilliseconds != rhs.cue.startMilliseconds {
                return lhs.cue.startMilliseconds < rhs.cue.startMilliseconds
            }
            return lhs.sourceIndex < rhs.sourceIndex
        }

        let cues = decodedCues.enumerated().map { index, value in
            FocusVideoSubtitleCue(
                id: Int64(index),
                startMilliseconds: value.cue.startMilliseconds,
                endMilliseconds: value.cue.endMilliseconds,
                location: value.cue.location,
                content: value.cue.content
            )
        }
        return FocusVideoSubtitleDocument(cues: cues)
    }

    private nonisolated static func makeAPIRequest(
        url: URL,
        referer: String,
        cookies: [HTTPCookie]
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(FocusVideoDetailService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        return CookieRequestPolicy.attach(cookies: cookies, to: request)
    }

    private nonisolated static func decodeTrack(
        _ dictionary: [String: Any]
    ) throws -> FocusVideoSubtitleTrack? {
        guard
            let id = int64Value(dictionary["id_str"]) ?? int64Value(dictionary["id"]),
            let rawURL = stringValue(dictionary["subtitle_url"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawURL.isEmpty
        else {
            return nil
        }

        let languageCode = stringValue(dictionary["lan"]) ?? ""
        let displayName = stringValue(dictionary["lan_doc"]) ?? languageCode
        return FocusVideoSubtitleTrack(
            id: id,
            languageCode: languageCode,
            displayName: displayName,
            subtitleURL: try validatedSubtitleURL(rawURL),
            isLocked: boolValue(dictionary["is_lock"]) ?? false,
            type: int64Value(dictionary["type"]).map { Int(clamping: $0) } ?? 0,
            aiType: int64Value(dictionary["ai_type"]).map { Int(clamping: $0) } ?? 0,
            aiStatus: int64Value(dictionary["ai_status"]).map { Int(clamping: $0) } ?? 0
        )
    }

    private nonisolated static func validatedSubtitleURL(_ rawValue: String) throws -> URL {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = trimmedValue.hasPrefix("//")
            ? "https:\(trimmedValue)"
            : trimmedValue
        guard
            var components = URLComponents(string: normalizedValue),
            components.scheme?.lowercased() == "https",
            components.user == nil,
            components.password == nil,
            components.fragment == nil,
            components.port == nil || components.port == 443,
            let rawHost = components.host?.lowercased(),
            !rawHost.isEmpty
        else {
            throw ServiceError.unsafeSubtitleURL
        }

        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard trustedSubtitleDomains.contains(where: { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }) else {
            throw ServiceError.unsafeSubtitleURL
        }

        components.scheme = "https"
        guard let url = components.url else {
            throw ServiceError.unsafeSubtitleURL
        }
        return url
    }

    private nonisolated static func decodedJSONObject(_ data: Data) throws -> [String: Any] {
        do {
            guard
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw ServiceError.invalidResponse
            }
            return object
        } catch let error as ServiceError {
            throw error
        } catch {
            throw ServiceError.invalidResponse
        }
    }

    private nonisolated static func int64Value(_ value: Any?) -> Int64? {
        if let string = value as? String {
            return Int64(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let number = value as? NSNumber {
            return Int64(number.stringValue)
        }
        return nil
    }

    private nonisolated static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private nonisolated static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private nonisolated static func milliseconds(from seconds: Double) -> Int64? {
        guard seconds.isFinite, seconds >= 0 else {
            return nil
        }
        let milliseconds = (seconds * 1_000).rounded()
        guard
            milliseconds.isFinite,
            milliseconds >= 0,
            milliseconds < Double(Int64.max)
        else {
            return nil
        }
        return Int64(milliseconds)
    }
}
