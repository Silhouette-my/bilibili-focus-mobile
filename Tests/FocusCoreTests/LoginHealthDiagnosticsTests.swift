import Foundation
import Testing
@testable import FocusCore

@Suite("Login health and diagnostics")
struct LoginHealthDiagnosticsTests {
    @Test("cookie presence distinguishes logged out from expired session")
    func localCookieClassification() async {
        let loggedOut = LoginHealthService(
            cookieProvider: LoginHealthCookieProvider(cookies: []),
            requestLoader: successfulLoginResponse
        )
        #expect(await loggedOut.check(now: Self.now) == .notLoggedIn)

        let expired = LoginHealthService(
            cookieProvider: LoginHealthCookieProvider(
                cookies: [
                    healthCookie(
                        name: "SESSDATA",
                        value: "expired-secret",
                        expires: Self.now.addingTimeInterval(-1)
                    ),
                ]
            ),
            requestLoader: successfulLoginResponse
        )
        #expect(await expired.check(now: Self.now) == .sessionExpired)
    }

    @Test("valid login distinguishes healthy from missing CSRF")
    func healthyAndMissingCsrf() async {
        let missingCsrf = LoginHealthService(
            cookieProvider: LoginHealthCookieProvider(
                cookies: [healthCookie(name: "SESSDATA", value: "session-secret")]
            ),
            requestLoader: successfulLoginResponse
        )
        #expect(await missingCsrf.check(now: Self.now) == .missingCSRF)

        let healthy = LoginHealthService(
            cookieProvider: LoginHealthCookieProvider(
                cookies: authenticatedHealthCookies()
            ),
            requestLoader: successfulLoginResponse
        )
        #expect(await healthy.check(now: Self.now) == .healthy)
    }

    @Test("server invalidation and risk-control responses are classified")
    func serverClassification() async {
        let provider = LoginHealthCookieProvider(cookies: authenticatedHealthCookies())
        let expired = LoginHealthService(
            cookieProvider: provider,
            requestLoader: loader(status: 200, body: #"{"code":-101}"#)
        )
        #expect(await expired.check(now: Self.now) == .sessionExpired)

        let apiRisk = LoginHealthService(
            cookieProvider: provider,
            requestLoader: loader(status: 200, body: #"{"code":-352}"#)
        )
        #expect(await apiRisk.check(now: Self.now) == .wbiRiskControlled)

        let httpRisk = LoginHealthService(
            cookieProvider: provider,
            requestLoader: loader(status: 403, body: "blocked")
        )
        #expect(await httpRisk.check(now: Self.now) == .wbiRiskControlled)
    }

    @Test("transport failure and malformed payload do not expose raw errors")
    func unavailableAndUnknown() async {
        let provider = LoginHealthCookieProvider(cookies: authenticatedHealthCookies())
        let unavailable = LoginHealthService(
            cookieProvider: provider,
            requestLoader: { _ in throw URLError(.notConnectedToInternet) }
        )
        #expect(await unavailable.check(now: Self.now) == .networkUnavailable)

        let malformed = LoginHealthService(
            cookieProvider: provider,
            requestLoader: loader(status: 200, body: "not-json secret-body")
        )
        #expect(await malformed.check(now: Self.now) == .unknown)
    }

    @Test("diagnostic export strips user-info query fragment and raw failures")
    func diagnosticSnapshotIsStrictlyRedacted() async throws {
        let store = BiliNetworkEventStore(capacity: 2)
        await store.record(
            BiliNetworkEvent(
                method: "custom secret-method",
                target: "https://SESSDATA:cookie-secret@api.bilibili.com/private/path?keyword=search-secret#body-secret",
                statusCode: 999,
                durationMilliseconds: -1,
                responseBytes: -20,
                failureType: "SecretTransportError_cookie-secret"
            )
        )

        let snapshot = await BiliDiagnostics.snapshot(
            loginHealth: .networkUnavailable,
            eventStore: store
        )
        #expect(snapshot.events == [
            BiliDiagnosticEvent(
                method: "OTHER",
                target: "https://api.bilibili.com/private/path",
                statusCode: nil,
                durationMilliseconds: 0,
                responseBytes: 0,
                failureType: "transport_error"
            ),
        ])

        let encoded = String(decoding: try snapshot.jsonData(), as: UTF8.self)
        for secret in [
            "SESSDATA",
            "cookie-secret",
            "keyword",
            "search-secret",
            "body-secret",
            "SecretTransportError",
        ] {
            #expect(!encoded.contains(secret))
        }
        #expect(encoded.contains(#""loginHealth":"network_unavailable""#))
    }

    private static let now = Date(timeIntervalSince1970: 2_000_000_000)
}

private struct LoginHealthCookieProvider: CookieSnapshotProvider {
    let cookies: [HTTPCookie]
    // This fixture is a completed authoritative read, not an initializing store.
    var sessionReadiness: CookieSessionReadiness { cookies.isEmpty ? .anonymous : .authenticated }

    func loadCookies() async -> [HTTPCookie] {
        cookies
    }
}

private func authenticatedHealthCookies() -> [HTTPCookie] {
    [
        healthCookie(name: "SESSDATA", value: "session-secret"),
        healthCookie(name: "bili_jct", value: "csrf-secret"),
    ]
}

private func healthCookie(
    name: String,
    value: String,
    expires: Date? = nil
) -> HTTPCookie {
    var properties: [HTTPCookiePropertyKey: Any] = [
        .name: name,
        .value: value,
        .domain: ".bilibili.com",
        .path: "/",
        .secure: true,
    ]
    if let expires {
        properties[.expires] = expires
    }
    return HTTPCookie(properties: properties)!
}

private let successfulLoginResponse: BiliAPITransport.RequestLoader = loader(
    status: 200,
    body: #"{"code":0,"data":{"isLogin":true}}"#
)

private func loader(
    status: Int,
    body: String
) -> BiliAPITransport.RequestLoader {
    { request in
        (
            Data(body.utf8),
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
