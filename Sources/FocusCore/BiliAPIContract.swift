import Foundation

public struct BiliAPIContract: Codable, Equatable, Sendable {
    public let url: URL
    public let method: String
    public let requiresAuthentication: Bool
    public let usesWBI: Bool
    public let skipsCSRF: Bool

    private enum CodingKeys: String, CodingKey {
        case url
        case method
        case requiresAuthentication = "verify"
        case usesWBI = "wbi"
        case skipsCSRF = "noCsrf"
    }
}

public struct BiliAPIContractSource: Codable, Equatable, Sendable {
    public let repository: URL
    public let validatedCommit: String
    public let strategy: String
}

public struct BiliAPIContractSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let source: BiliAPIContractSource
    public let endpoints: [String: BiliAPIContract]
}

public enum BiliAPIContractCatalog {
    public static let snapshot: BiliAPIContractSnapshot = loadSnapshot()

    public static func endpoint(_ key: String) -> BiliAPIContract? {
        snapshot.endpoints[key]
    }

    public static func require(_ key: String) -> BiliAPIContract {
        guard let endpoint = endpoint(key) else {
            preconditionFailure("Missing bilibili-api contract: \(key)")
        }
        return endpoint
    }

    private static func loadSnapshot() -> BiliAPIContractSnapshot {
        guard let url = FocusBundle.module.url(
            forResource: "bilibili-api-contracts",
            withExtension: "json"
        ) else {
            preconditionFailure("Missing bilibili-api-contracts.json")
        }

        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(BiliAPIContractSnapshot.self, from: data)
            precondition(snapshot.schemaVersion == 1, "Unsupported bilibili-api contract schema")
            return snapshot
        } catch {
            preconditionFailure("Invalid bilibili-api contract snapshot: \(error)")
        }
    }
}
