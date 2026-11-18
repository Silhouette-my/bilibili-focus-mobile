import Foundation

public struct DynamicCard: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Hashable, Codable, Sendable {
        case text
        case image
        case video
        case articleLike
    }

    public struct Author: Hashable, Codable, Sendable {
        public let mid: Int64
        public let name: String
        public let avatarURL: URL?

        public init(mid: Int64 = 0, name: String, avatarURL: URL?) {
            self.mid = mid
            self.name = name
            self.avatarURL = avatarURL
        }
    }

    public struct QuotedCard: Hashable, Codable, Sendable {
        public let id: String
        public let kind: Kind
        public let author: Author
        public let publishTime: String
        public let title: String
        public let text: String
        public let coverURLs: [URL]
        public let targetURL: URL?
        public let videoURL: URL?
        public let unavailableTip: String?

        public init(
            id: String = "",
            kind: Kind = .text,
            author: Author = Author(name: "", avatarURL: nil),
            publishTime: String = "",
            title: String = "",
            text: String = "",
            coverURLs: [URL] = [],
            targetURL: URL? = nil,
            videoURL: URL? = nil,
            unavailableTip: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.author = author
            self.publishTime = publishTime
            self.title = title
            self.text = text
            self.coverURLs = coverURLs
            self.targetURL = targetURL
            self.videoURL = videoURL
            self.unavailableTip = unavailableTip
        }
    }

    public let id: String
    public let kind: Kind
    public let author: Author
    public let publishTime: String
    public let text: String
    public let coverURLs: [URL]
    public let targetURL: URL
    public let videoURL: URL?
    public let quotedCard: QuotedCard?

    public init(
        id: String,
        kind: Kind,
        author: Author,
        publishTime: String,
        text: String,
        coverURLs: [URL],
        targetURL: URL,
        videoURL: URL?,
        quotedCard: QuotedCard? = nil
    ) {
        self.id = id
        self.kind = kind
        self.author = author
        self.publishTime = publishTime
        self.text = text
        self.coverURLs = coverURLs
        self.targetURL = targetURL
        self.videoURL = videoURL
        self.quotedCard = quotedCard
    }
}
