import Foundation

/// A privacy-safe summary of the current Bilibili authentication state.
///
/// The raw values are shared with the KMP implementation so diagnostic
/// snapshots can be compared without platform-specific translation.
public enum LoginHealth: String, Codable, CaseIterable, Sendable {
    case notLoggedIn = "not_logged_in"
    case sessionExpired = "session_expired"
    case missingCSRF = "missing_csrf"
    case wbiRiskControlled = "wbi_risk_controlled"
    case networkUnavailable = "network_unavailable"
    case healthy
    case unknown
}

/// Performs a single, read-only login health probe against the endpoint
/// catalogued as `credential.info.valid`.
public struct LoginHealthService: Sendable {
    public typealias RequestLoader = BiliAPITransport.RequestLoader

    private let cookieProvider: any CookieSnapshotProvider
    private let requestLoader: RequestLoader
    private let userAgent: String

    public init(
        cookieProvider: any CookieSnapshotProvider,
        requestLoader: @escaping RequestLoader = { request in
            try await BiliAPINetwork.data(for: request)
        },
        userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15"
    ) {
        self.cookieProvider = cookieProvider
        self.requestLoader = requestLoader
        self.userAgent = userAgent
    }

    /// Returns a state instead of surfacing transport or decoding details. This
    /// keeps callers from accidentally exposing raw errors or response bodies
    /// in user-facing diagnostics.
    public func check(now: Date = Date()) async -> LoginHealth {
        let endpoint = BiliAPIContractCatalog.require("credential.info.valid")
        let cookies = await cookieProvider.loadCookies()
        let matchingCookies = CookieRequestPolicy.cookies(
            cookies,
            matching: endpoint.url,
            now: now
        )
        let validSession = matchingCookies.contains {
            $0.name.caseInsensitiveCompare("SESSDATA") == .orderedSame &&
                !$0.value.isEmpty
        }

        guard validSession else {
            let scopedCookiesIncludingExpired = CookieRequestPolicy.cookies(
                cookies,
                matching: endpoint.url,
                now: .distantPast
            )
            let hasExpiredSession = scopedCookiesIncludingExpired.contains {
                $0.name.caseInsensitiveCompare("SESSDATA") == .orderedSame &&
                    !$0.value.isEmpty &&
                    ($0.expiresDate.map { $0 <= now } ?? false)
            }
            return hasExpiredSession ? .sessionExpired : .notLoggedIn
        }

        let hasCSRF = matchingCookies.contains {
            $0.name.caseInsensitiveCompare("bili_jct") == .orderedSame &&
                !$0.value.isEmpty
        }

        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request = CookieRequestPolicy.attach(cookies: cookies, to: request, now: now)

        let data: Data
        let response: HTTPURLResponse
        do {
            let result = try await requestLoader(request)
            data = result.0
            guard let httpResponse = result.1 as? HTTPURLResponse else {
                return .unknown
            }
            response = httpResponse
        } catch is CancellationError {
            return .unknown
        } catch is URLError {
            return .networkUnavailable
        } catch {
            // RequestLoader errors occur before response decoding, so the
            // conservative actionable classification is transport failure.
            return .networkUnavailable
        }

        if response.statusCode == 401 {
            return .sessionExpired
        }
        if response.statusCode == 403 {
            return .wbiRiskControlled
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            return .unknown
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let code = Self.integer(root["code"])
        else {
            return .unknown
        }

        if code == -403 || code == -352 {
            return .wbiRiskControlled
        }
        if code == -101 {
            return .sessionExpired
        }
        guard
            code == 0,
            let data = root["data"] as? [String: Any],
            let isLogin = Self.boolean(data["isLogin"])
        else {
            return .unknown
        }
        guard isLogin else {
            return .sessionExpired
        }
        return hasCSRF ? .healthy : .missingCSRF
    }

    private static func integer(_ value: Any?) -> Int? {
        if let integer = value as? Int {
            return integer
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let boolean = value as? Bool {
            return boolean
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
}
