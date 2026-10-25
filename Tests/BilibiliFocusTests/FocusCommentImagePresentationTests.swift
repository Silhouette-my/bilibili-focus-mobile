import SwiftUI
import UIKit
import XCTest
@testable import BilibiliFocus

@MainActor
final class FocusCommentImagePresentationTests: XCTestCase {
    func testOpusCommentPayloadPreservesPureImagesAndReplyImages() throws {
        let json = #"{"member":{"uname":"图片"},"content":{"message":"","pictures":[{"img_src":"http://i0.hdslb.com/root.png"},{"img_src":"https://"},{"img_src":"file:///tmp/a.png"}]},"replies":[{"member":{"uname":"回复"},"content":{"pictures":[{"img_src":"//i0.hdslb.com/reply.png"}]}}]}"#
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let payload = try XCTUnwrap(FocusNativePageAugmentService.parseComment(from: object))
        XCTAssertEqual(payload.imageURLs, ["https://i0.hdslb.com/root.png"])
        XCTAssertEqual(payload.previewReplies.first?.imageURLs, ["https://i0.hdslb.com/reply.png"])
        XCTAssertEqual(payload.content, "")
    }

    func testCommentImagesLoadAndKeepTheirThumbnailHeight() async throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 35, y: 15, width: 50, height: 50))
        }
        CommentImageURLProtocol.configure(data: data)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommentImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let repository = FocusImageRepository(session: session)
        let runID = UUID().uuidString
        let urls = (0..<3).map { URL(string: "https://comment-image.test/\(runID)/\($0).png")! }
        let controller = UIHostingController(rootView: FocusCommentImageStrip(
            urls: urls, referer: "https://www.bilibili.com/", imageRepository: repository, onSelect: { _ in }
        ))
        if #available(iOS 16.4, *) { controller.safeAreaRegions = [] }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        let initialSize = controller.sizeThatFits(in: CGSize(width: 320, height: 1000))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while CommentImageURLProtocol.requestCount < 3, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(CommentImageURLProtocol.requestCount, 3, "Every attached image must reach the actual image loader")
        try await Task.sleep(for: .milliseconds(100))
        controller.view.layoutIfNeeded()
        let loadedSize = controller.sizeThatFits(in: CGSize(width: 320, height: 1000))
        XCTAssertEqual(initialSize.height, 82, accuracy: 1)
        XCTAssertEqual(loadedSize.height, initialSize.height, accuracy: 1)
        let rendered = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: rendered)
        attachment.name = "Comment image thumbnails"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class CommentImageURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var imageData = Data()
    nonisolated(unsafe) private static var count = 0
    static var requestCount: Int { lock.withLock { count } }
    static func configure(data: Data) { lock.withLock { imageData = data; count = 0 } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "comment-image.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.lock.withLock { Self.count += 1; return Self.imageData }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
