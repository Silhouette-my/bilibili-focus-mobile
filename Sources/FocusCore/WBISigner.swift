import CryptoKit
import Foundation

/// Process-wide WBI signing coordinator.
///
/// The mixin key is shared by every service using `shared`. Key discovery is
/// coalesced so concurrent callers issue a single `/x/web-interface/nav`
/// request. A rejected key is invalidated by revision, which prevents a late
/// `-403` response from discarding a key that another request already refreshed.
actor WBISigner {
    typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias RequestBuilder = @Sendable (String) throws -> URLRequest

    enum SigningError: Error, Equatable, Sendable {
        case invalidKeyResponse
        case invalidRequest
    }

    struct HTTPResponse: @unchecked Sendable {
        let data: Data
        let response: HTTPURLResponse
    }

    struct SignedQuery: Equatable, Sendable {
        let percentEncodedQuery: String
        fileprivate let keyRevision: UInt64
    }

    static let shared = WBISigner()

    private struct KeyMaterial: Sendable {
        let mixinKey: String
        let revision: UInt64
    }

    private struct CacheEntry: Sendable {
        let material: KeyMaterial
        let expiresAt: Date
    }

    private struct PendingKey: Sendable {
        let id: UUID
        let revision: UInt64
        let task: Task<String, Swift.Error>
    }

    private static let mixinTable = [
        46, 47, 18, 2, 53, 8, 23, 32,
        15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19,
        29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61,
        26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63,
        57, 62, 11, 36, 20, 52, 34, 44,
    ]

    private let cacheLifetime: TimeInterval
    private let now: @Sendable () -> Date
    private var revision: UInt64 = 0
    private var cacheEntry: CacheEntry?
    private var pendingKey: PendingKey?

    init(
        cacheLifetime: TimeInterval = 30 * 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.cacheLifetime = max(cacheLifetime, 0)
        self.now = now
    }

    /// Signs and executes a WBI request, refreshing the process-wide key once
    /// when either the HTTP status or the Bilibili JSON code is `-403`.
    nonisolated func execute(
        parameters: [String: String],
        navigationRequest: URLRequest,
        requestLoader: @escaping RequestLoader,
        requestBuilder: @escaping RequestBuilder
    ) async throws -> HTTPResponse {
        for attempt in 0 ..< 2 {
            let signedQuery = try await signedQuery(
                parameters: parameters,
                navigationRequest: navigationRequest,
                requestLoader: requestLoader
            )
            let request = try requestBuilder(signedQuery.percentEncodedQuery)
            let (data, response) = try await requestLoader(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SigningError.invalidRequest
            }

            if attempt == 0, Self.isRejectedWBIResponse(data: data, response: httpResponse) {
                await invalidate(rejectedRevision: signedQuery.keyRevision)
                continue
            }
            return HTTPResponse(data: data, response: httpResponse)
        }

        throw SigningError.invalidRequest
    }

    func signedQuery(
        parameters: [String: String],
        navigationRequest: URLRequest,
        requestLoader: @escaping RequestLoader
    ) async throws -> SignedQuery {
        let material = try await keyMaterial(
            navigationRequest: navigationRequest,
            requestLoader: requestLoader
        )
        let timestamp = Int64(now().timeIntervalSince1970.rounded(.down))
        return SignedQuery(
            percentEncodedQuery: try Self.makeSignedQuery(
                parameters: parameters,
                mixinKey: material.mixinKey,
                timestamp: timestamp
            ),
            keyRevision: material.revision
        )
    }

    func invalidate() {
        advanceRevision()
    }

    nonisolated static func makeSignedQuery(
        parameters: [String: String],
        mixinKey: String,
        timestamp: Int64
    ) throws -> String {
        guard !mixinKey.isEmpty else {
            throw SigningError.invalidKeyResponse
        }

        var normalized = parameters
        normalized.removeValue(forKey: "w_rid")
        normalized["wts"] = String(timestamp)
        if normalized["web_location"]?.isEmpty != false {
            normalized["web_location"] = "1550101"
        }

        let encodedQuery = normalized
            .sorted { lhs, rhs in
                lhs.key < rhs.key
            }
            .map { key, value in
                let cleanedValue = value.filter { !"!'()*".contains($0) }
                return (
                    Self.rfc3986Encode(key),
                    Self.rfc3986Encode(cleanedValue)
                )
            }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")

        let signature = Insecure.MD5.hash(data: Data((encodedQuery + mixinKey).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(encodedQuery)&w_rid=\(signature)"
    }

    nonisolated static func makeMixinKey(imgKey: String, subKey: String) throws -> String {
        let characters = Array(imgKey + subKey)
        let mixed = mixinTable.compactMap { index in
            characters.indices.contains(index) ? characters[index] : nil
        }
        let result = String(mixed.prefix(32))
        guard result.count == 32 else {
            throw SigningError.invalidKeyResponse
        }
        return result
    }

    private func keyMaterial(
        navigationRequest: URLRequest,
        requestLoader: @escaping RequestLoader
    ) async throws -> KeyMaterial {
        while true {
            let currentTime = now()
            if let cacheEntry, cacheEntry.expiresAt > currentTime {
                return cacheEntry.material
            }
            if cacheEntry != nil {
                advanceRevision()
            }

            let pending: PendingKey
            if let pendingKey, pendingKey.revision == revision {
                pending = pendingKey
            } else {
                let id = UUID()
                let requestRevision = revision
                let task = Task<String, Swift.Error> {
                    try await Self.fetchMixinKey(
                        navigationRequest: navigationRequest,
                        requestLoader: requestLoader
                    )
                }
                let created = PendingKey(
                    id: id,
                    revision: requestRevision,
                    task: task
                )
                pendingKey = created
                pending = created
            }

            do {
                let mixinKey = try await pending.task.value
                guard pending.revision == revision else {
                    continue
                }

                let material = KeyMaterial(
                    mixinKey: mixinKey,
                    revision: pending.revision
                )
                if pendingKey?.id == pending.id {
                    pendingKey = nil
                    cacheEntry = CacheEntry(
                        material: material,
                        expiresAt: now().addingTimeInterval(cacheLifetime)
                    )
                }
                try Task.checkCancellation()
                return material
            } catch {
                if pending.revision != revision {
                    continue
                }
                if pendingKey?.id == pending.id {
                    pendingKey = nil
                }
                throw error
            }
        }
    }

    private func invalidate(rejectedRevision: UInt64) {
        guard rejectedRevision == revision else {
            return
        }
        advanceRevision()
    }

    private func advanceRevision() {
        revision &+= 1
        cacheEntry = nil
        pendingKey?.task.cancel()
        pendingKey = nil
    }

    private nonisolated static func fetchMixinKey(
        navigationRequest: URLRequest,
        requestLoader: @escaping RequestLoader
    ) async throws -> String {
        let (data, response) = try await requestLoader(navigationRequest)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200 ..< 300).contains(httpResponse.statusCode),
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            integer(in: root, path: ["code"]) == 0,
            let imgURL = string(in: root, path: ["data", "wbi_img", "img_url"]),
            let subURL = string(in: root, path: ["data", "wbi_img", "sub_url"])
        else {
            throw SigningError.invalidKeyResponse
        }

        let imgKey = URL(string: imgURL)?.deletingPathExtension().lastPathComponent ?? ""
        let subKey = URL(string: subURL)?.deletingPathExtension().lastPathComponent ?? ""
        return try makeMixinKey(imgKey: imgKey, subKey: subKey)
    }

    private nonisolated static func isRejectedWBIResponse(
        data: Data,
        response: HTTPURLResponse
    ) -> Bool {
        if response.statusCode == 403 {
            return true
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return integer(in: root, path: ["code"]) == -403
    }

    private nonisolated static func rfc3986Encode(_ value: String) -> String {
        value.utf8.map { byte -> String in
            switch byte {
            case 0x41 ... 0x5a, 0x61 ... 0x7a, 0x30 ... 0x39, 0x2d, 0x2e, 0x5f, 0x7e:
                return String(UnicodeScalar(byte))
            default:
                return String(format: "%%%02X", byte)
            }
        }.joined()
    }

    private nonisolated static func integer(
        in dictionary: [String: Any],
        path: [String]
    ) -> Int? {
        guard let value = value(in: dictionary, path: path) else {
            return nil
        }
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private nonisolated static func string(
        in dictionary: [String: Any],
        path: [String]
    ) -> String? {
        value(in: dictionary, path: path) as? String
    }

    private nonisolated static func value(
        in dictionary: [String: Any],
        path: [String]
    ) -> Any? {
        var current: Any = dictionary
        for key in path {
            guard let nested = current as? [String: Any], let next = nested[key] else {
                return nil
            }
            current = next
        }
        return current
    }
}
