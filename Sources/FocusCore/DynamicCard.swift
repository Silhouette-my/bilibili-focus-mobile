import Foundation

public struct DynamicCard: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case text
        case image
        case video
        case articleLike
    }

    public struct Author: Equatable, Sendable {
        public let mid: Int64
        public let name: String
        public let avatarURL: URL?

        public init(mid: Int64 = 0, name: String, avatarURL: URL?) {
            self.mid = mid
            self.name = name
            self.avatarURL = avatarURL
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

    public init(
        id: String,
        kind: Kind,
        author: Author,
        publishTime: String,
        text: String,
        coverURLs: [URL],
        targetURL: URL,
        videoURL: URL?
    ) {
        self.id = id
        self.kind = kind
        self.author = author
        self.publishTime = publishTime
        self.text = text
        self.coverURLs = coverURLs
        self.targetURL = targetURL
        self.videoURL = videoURL
    }
}
