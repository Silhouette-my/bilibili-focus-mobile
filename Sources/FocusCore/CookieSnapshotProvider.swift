import Foundation

public enum CookieRequestPolicy {
    public static func cookies(
        _ cookies: [HTTPCookie],
        matching url: URL,
        now: Date = Date()
    ) -> [HTTPCookie] {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let requestHost = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            !requestHost.isEmpty
        else {
            return []
        }

        let requestPath = url.path.isEmpty ? "/" : url.path
        return cookies.enumerated()
            .filter { _, cookie in
                !cookie.name.isEmpty
                    && (cookie.expiresDate.map { $0 > now } ?? true)
                    && (!cookie.isSecure || scheme == "https")
                    && domainMatches(cookie: cookie, requestHost: requestHost)
                    && pathMatches(cookiePath: cookie.path, requestPath: requestPath)
            }
            .sorted { lhs, rhs in
                let lhsLength = normalizedCookiePath(lhs.element.path).count
                let rhsLength = normalizedCookiePath(rhs.element.path).count
                return lhsLength == rhsLength ? lhs.offset < rhs.offset : lhsLength > rhsLength
            }
            .map(\.element)
    }

    public static func cookieHeader(
        cookies: [HTTPCookie],
        for url: URL,
        now: Date = Date()
    ) -> String? {
        let value = self.cookies(cookies, matching: url, now: now)
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        return value.isEmpty ? nil : value
    }

    public static func headerFields(
        cookies: [HTTPCookie],
        for url: URL,
        now: Date = Date()
    ) -> [String: String] {
        guard let cookieHeader = cookieHeader(cookies: cookies, for: url, now: now) else {
            return [:]
        }
        return ["Cookie": cookieHeader]
    }

    public static func attach(
        cookies: [HTTPCookie],
        to request: URLRequest,
        now: Date = Date()
    ) -> URLRequest {
        var updatedRequest = request
        updatedRequest.setValue(nil, forHTTPHeaderField: "Cookie")
        guard
            let url = request.url,
            let cookieHeader = cookieHeader(cookies: cookies, for: url, now: now)
        else {
            return updatedRequest
        }
        updatedRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        return updatedRequest
    }

    private static func domainMatches(cookie: HTTPCookie, requestHost: String) -> Bool {
        let rawDomain = cookie.domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let domain = rawDomain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !domain.isEmpty else {
            return false
        }
        if requestHost == domain {
            return true
        }
        let isHostOnly = !rawDomain.hasPrefix(".")
        return !isHostOnly && requestHost.hasSuffix(".\(domain)")
    }

    private static func pathMatches(cookiePath rawCookiePath: String, requestPath: String) -> Bool {
        let cookiePath = normalizedCookiePath(rawCookiePath)
        if requestPath == cookiePath {
            return true
        }
        guard requestPath.hasPrefix(cookiePath) else {
            return false
        }
        if cookiePath.hasSuffix("/") {
            return true
        }
        let boundary = requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)
        return boundary < requestPath.endIndex && requestPath[boundary] == "/"
    }

    private static func normalizedCookiePath(_ path: String) -> String {
        path.hasPrefix("/") ? path : "/"
    }
}

public protocol CookieSnapshotProvider: Sendable {
    func loadCookies() async -> [HTTPCookie]
    func attachCookies(to request: URLRequest) -> URLRequest
}

public extension CookieSnapshotProvider {
    func attachCookies(to request: URLRequest) -> URLRequest {
        request
    }
}
