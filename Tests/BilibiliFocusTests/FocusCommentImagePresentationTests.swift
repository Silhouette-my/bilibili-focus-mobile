import FocusCore
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
    }

    @MainActor
    func testSelectableRichTextCopyWritesPlainTextAndEmoteAltToPasteboard() {
        let view = FocusCopyableRichTextView()
        let emoteURL = URL(string: "https://i0.hdslb.com/bfs/emote/doge.png")!
        let profileURL = URL(string: "https://space.bilibili.com/123")!
        view.configure(
            runs: [
                .text(value: "看看这个 "),
                .emote(alt: "[doge]", url: emoteURL),
                .resource(label: " @测试UP", url: profileURL),
            ],
            textStyle: .body,
            baseColor: .label,
            linkColor: .systemBlue,
            scale: 2.0,
            onOpenURL: { _ in }
        )

        view.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        view.layoutIfNeeded()

        let fullLength = view.attributedText.length
        XCTAssertGreaterThan(fullLength, 0)
        XCTAssertEqual(view.plainText(in: NSRange(location: 4, length: 2)), " [doge]")

        UIPasteboard.general.string = ""
        view.selectedRange = NSRange(location: 0, length: fullLength)
        view.copy(nil)
        XCTAssertEqual(UIPasteboard.general.string, "看看这个 [doge] @测试UP")
    }

    func testOpusDetailServiceParsesLinkCardAndFallsBackToDynamicForward() async throws {
        let service = FocusOpusDetailService(
            cookieProvider: OpusTestCookieProvider(),
            requestHandler: { request in
                let url = request.url!
                let path = url.path
                let query = url.query ?? ""
                let json: String
                if path.contains("/opus/detail"), query.contains("id=7788") {
                    json = """
                    {
                      "code": 0,
                      "data": {
                        "item": {
                          "id_str": "7788",
                          "basic": { "comment_id_str": "7788", "comment_type": 11 },
                          "modules": [
                            {
                              "module_type": "MODULE_TYPE_AUTHOR",
                              "module_author": { "name": "专栏作者", "mid": 1001, "pub_time": "今天" }
                            },
                            {
                              "module_type": "MODULE_TYPE_CONTENT",
                              "module_content": {
                                "paragraphs": [
                                  {
                                    "para_type": 4,
                                    "blockquote": {
                                      "children": [
                                        {
                                          "text": {
                                            "nodes": [
                                              { "type": "TEXT_NODE_TYPE_WORD", "word": { "words": "引用段落" } }
                                            ]
                                          }
                                        }
                                      ]
                                    }
                                  },
                                  {
                                    "para_type": 6,
                                    "link_card": {
                                      "card": {
                                        "card_type": "LINK_CARD_TYPE_OPUS",
                                        "jump_url": "//www.bilibili.com/opus/8801",
                                        "opus": {
                                          "title": "关联动态标题",
                                          "author": { "name": "原作者", "mid": 42 },
                                          "summary": { "text": "关联动态摘要" },
                                          "jump_url": "//www.bilibili.com/opus/8801"
                                        }
                                      }
                                    }
                                  },
                                  {
                                    "para_type": 6,
                                    "link_card": {
                                      "card": {
                                        "card_type": "LINK_CARD_TYPE_UGC",
                                        "ugc": {
                                          "title": "关联视频标题",
                                          "bvid": "BV1zz411c7xy",
                                          "desc_second": "05:20",
                                          "cover": "//i0.hdslb.com/v.jpg",
                                          "jump_url": "//www.bilibili.com/video/BV1zz411c7xy"
                                        }
                                      }
                                    }
                                  }
                                ]
                              }
                            }
                          ]
                        }
                      }
                    }
                    """
                } else if path.contains("/opus/detail"), query.contains("id=9001") {
                    json = #"{"code":-404,"message":"nothing found"}"#
                } else if path.contains("/x/web-interface/nav") {
                    json = #"{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/abcdefghijklmnopqrstuvwxyz012345.png","sub_url":"https://i0.hdslb.com/ABCDEFGHIJKLMNOPQRSTUVWXYZ012345.png"}}}"#
                } else {
                    json = """
                    {
                      "code": 0,
                      "data": {
                        "item": {
                          "id_str": "9001",
                          "type": "DYNAMIC_TYPE_FORWARD",
                          "basic": { "comment_id_str": "9001", "comment_type": 17 },
                          "modules": {
                            "module_author": { "name": "外层转发作者", "mid": 11, "pub_time": "10分钟前" },
                            "module_dynamic": { "desc": { "text": "转发附言" } }
                          },
                          "orig": {
                            "id_str": "8001",
                            "type": "DYNAMIC_TYPE_AV",
                            "modules": {
                              "module_author": { "name": "原动态作者", "mid": 22, "pub_time": "1小时前" },
                              "module_dynamic": {
                                "major": {
                                  "type": "MAJOR_TYPE_ARCHIVE",
                                  "archive": {
                                    "bvid": "BV1ab411c7cd",
                                    "title": "原视频",
                                    "desc": "视频简介",
                                    "cover": "//i0.hdslb.com/bfs/archive/orig.jpg",
                                    "jump_url": "//www.bilibili.com/video/BV1ab411c7cd"
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                    """
                }
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(json.utf8), response)
            }
        )

        let opusContent = try await service.fetchDetail(for: URL(string: "https://www.bilibili.com/opus/7788")!)
        let opusBlocks = opusContent.paragraphs.flatMap(\.blocks)
        let quotes = opusBlocks.compactMap { block -> [FocusRichTextRun]? in
            if case let .quote(runs) = block { return runs }
            return nil
        }
        XCTAssertEqual(quotes.count, 1)
        XCTAssertEqual(quotes.first?.map(\.plainText).joined(), "引用段落")

        let opusRefs = opusBlocks.compactMap { block -> FocusOpusReference? in
            if case let .reference(ref) = block { return ref }
            return nil
        }
        XCTAssertEqual(opusRefs.count, 2)
        XCTAssertEqual(opusRefs[0].authorName, "原作者")
        XCTAssertEqual(opusRefs[0].title, "关联动态标题")
        XCTAssertEqual(opusRefs[0].targetURL?.absoluteString, "https://www.bilibili.com/opus/8801")
        XCTAssertEqual(opusRefs[1].title, "关联视频标题")
        XCTAssertEqual(opusRefs[1].targetURL?.absoluteString, "https://www.bilibili.com/video/BV1zz411c7xy/")

        let forwardContent = try await service.fetchDetail(for: URL(string: "https://www.bilibili.com/opus/9001")!)
        XCTAssertEqual(forwardContent.author.name, "外层转发作者")
        let forwardBlocks = forwardContent.paragraphs.flatMap(\.blocks)
        let forwardText = forwardBlocks.compactMap { block -> String? in
            if case let .text(runs) = block { return runs.map(\.plainText).joined() }
            return nil
        }.joined()
        XCTAssertTrue(forwardText.contains("转发附言"))

        let forwardRefs = forwardBlocks.compactMap { block -> FocusOpusReference? in
            if case let .reference(ref) = block { return ref }
            return nil
        }
        XCTAssertEqual(forwardRefs.count, 1)
        XCTAssertEqual(forwardRefs[0].authorName, "原动态作者")
        XCTAssertEqual(forwardRefs[0].title, "原视频")
        XCTAssertEqual(forwardRefs[0].targetURL?.absoluteString, "https://www.bilibili.com/video/BV1ab411c7cd/")
    }
}

private struct OpusTestCookieProvider: CookieSnapshotProvider {
    func loadCookies() async -> [HTTPCookie] { [] }
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
