import FocusCore
import Foundation
import Testing

struct CookieRequestPolicyTests {
    @Test
    func domainCookiesMatchSubdomainsWithoutMatchingDeceptiveSuffixes() throws {
        let cookies = [
            makeCookie(name: "session", value: "domain", domain: ".bilibili.com"),
            makeCookie(name: "host", value: "only", domain: "api.bilibili.com"),
        ].compactMap { $0 }
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(
            CookieRequestPolicy.cookieHeader(
                cookies: cookies,
                for: URL(string: "https://api.bilibili.com/x/player/playurl")!,
                now: now
            ) == "session=domain; host=only"
        )
        #expect(
            CookieRequestPolicy.cookieHeader(
                cookies: cookies,
                for: URL(string: "https://www.bilibili.com/video/BV1")!,
                now: now
            ) == "session=domain"
        )
        #expect(
            CookieRequestPolicy.cookieHeader(
                cookies: cookies,
                for: URL(string: "https://bilibili.com.attacker.example/video")!,
                now: now
            ) == nil
        )
        #expect(
            CookieRequestPolicy.cookieHeader(
                cookies: cookies,
                for: URL(string: "https://evilbilibili.com/video")!,
                now: now
            ) == nil
        )
    }

    @Test
    func pathMatchingHonorsSegmentBoundariesAndOrdersLongestPathFirst() throws {
        let cookies = [
            makeCookie(name: "root", value: "1", domain: ".bilibili.com", path: "/"),
            makeCookie(name: "video", value: "2", domain: ".bilibili.com", path: "/video"),
            makeCookie(name: "episode", value: "3", domain: ".bilibili.com", path: "/video/episode"),
        ].compactMap { $0 }
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(
            CookieRequestPolicy.cookieHeader(
                cookies: cookies,
                for: URL(string: "https://www.bilibili.com/video/episode/1")!,
                now: now
            ) == "episode=3; video=2; root=1"
        )
        #expect(
            CookieRequestPolicy.cookieHeader(
                cookies: cookies,
                for: URL(string: "https://www.bilibili.com/videotest")!,
                now: now
            ) == "root=1"
        )
    }

    @Test
    func secureAndExpiredCookiesAreExcluded() throws {
        let cookies = [
            makeCookie(name: "secure", value: "1", domain: ".bilibili.com", secure: true),
            makeCookie(
                name: "expired",
                value: "2",
                domain: ".bilibili.com",
                expires: Date(timeIntervalSince1970: 999)
            ),
            makeCookie(
                name: "valid",
                value: "3",
                domain: ".bilibili.com",
                expires: Date(timeIntervalSince1970: 1_001)
            ),
        ].compactMap { $0 }
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(
            CookieRequestPolicy.cookieHeader(
                cookies: cookies,
                for: URL(string: "http://www.bilibili.com/video")!,
                now: now
            ) == "valid=3"
        )
        #expect(
            CookieRequestPolicy.cookieHeader(
                cookies: cookies,
                for: URL(string: "https://www.bilibili.com/video")!,
                now: now
            ) == "secure=1; valid=3"
        )
    }

    @Test
    func attachReplacesStaleCookieHeadersAndClearsThemForCrossOriginTargets() throws {
        let cookie = try #require(
            makeCookie(name: "session", value: "domain", domain: ".bilibili.com")
        )
        var request = URLRequest(url: URL(string: "https://media.example/video.m4s")!)
        request.setValue("stale=credential", forHTTPHeaderField: "Cookie")

        let updatedRequest = CookieRequestPolicy.attach(
            cookies: [cookie],
            to: request,
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(updatedRequest.value(forHTTPHeaderField: "Cookie") == nil)
    }

    private func makeCookie(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        secure: Bool = false,
        expires: Date? = nil
    ) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: path,
            .name: name,
            .value: value,
        ]
        if secure {
            properties[.secure] = "TRUE"
        }
        if let expires {
            properties[.expires] = expires
        }
        return HTTPCookie(properties: properties)
    }
}
