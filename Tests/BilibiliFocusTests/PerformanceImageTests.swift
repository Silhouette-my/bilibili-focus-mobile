import Foundation
import UIKit
import ImageIO
import XCTest
@testable import BilibiliFocus

@MainActor
final class PerformanceImageTests: XCTestCase {
    func testPixelBucketsAreStableAndDecodeCacheIncludesSize() async throws {
        XCTAssertEqual(FocusImagePixelSize.bucket(for: CGSize(width: 42, height: 42), scale: 3), 128)
        XCTAssertEqual(FocusImagePixelSize.bucket(for: CGSize(width: 149, height: 84), scale: 3), 512)
        XCTAssertEqual(FocusImagePixelSize.bucket(for: CGSize(width: 150, height: 85), scale: 3), 512)
        let (repository, session) = makeRepository(size: CGSize(width: 1_024, height: 1_024))
        defer { session.invalidateAndCancel() }
        let url = imageURL("buckets")
        let first = try await repository.image(for: url, preferredReferer: "", pixelSize: 130)
        let sameBucket = try await repository.image(for: url, preferredReferer: "", pixelSize: 131)
        XCTAssertTrue(first === sameBucket)
        XCTAssertEqual(first.cgImage?.width, 256)
        let larger = try await repository.image(for: url, preferredReferer: "", pixelSize: 500)
        XCTAssertEqual(larger.cgImage?.width, 512)
        XCTAssertEqual(PerformanceImageProtocol.requestCount, 2)
    }

    func testCancellingOneSharedConsumerDoesNotCancelVisiblePeer() async throws {
        let (repository, session) = makeRepository(held: true)
        defer { session.invalidateAndCancel() }
        let url = imageURL("shared")
        let first = Task { try await repository.image(for: url, preferredReferer: "", pixelSize: 256) }
        await eventually { PerformanceImageProtocol.activeCount == 1 }
        let second = Task { try await repository.image(for: url, preferredReferer: "", pixelSize: 256) }
        await eventuallyAsync { await repository.activeConsumerCount == 2 }
        first.cancel()
        await eventuallyAsync { await repository.activeConsumerCount == 1 }
        XCTAssertEqual(PerformanceImageProtocol.activeCount, 1)
        PerformanceImageProtocol.releaseAll()
        let image = try await second.value
        XCTAssertNotNil(image.cgImage)
        do { _ = try await first.value; XCTFail("Cancelled consumer must not succeed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(PerformanceImageProtocol.requestCount, 1)
    }

    func testPrefetchHasRealBoundAndVisibleWorkBypassesPendingQueue() async throws {
        let (repository, session) = makeRepository(held: true)
        defer { session.invalidateAndCancel() }
        let limiter = FocusImagePrefetchLimiter(limit: 2)
        let urls = (0..<30).map { imageURL("prefetch-\($0)") }
        let task = Task {
            await FocusRemoteImageLoader.prefetch(urls: urls + urls, referer: "", repository: repository, limiter: limiter)
        }
        await eventually { PerformanceImageProtocol.activeCount == 2 }
        let visible = Task { try await repository.image(for: imageURL("visible"), preferredReferer: "", pixelSize: 256) }
        await eventually { PerformanceImageProtocol.activeCount == 3 }
        let activePrefetch = await limiter.activeCount
        XCTAssertEqual(activePrefetch, 2)
        PerformanceImageProtocol.releaseAll()
        _ = try await visible.value
        await task.value
        XCTAssertEqual(PerformanceImageProtocol.requestCount, 25, "24 unique prefetches plus the visible request")
        XCTAssertLessThanOrEqual(PerformanceImageProtocol.peakActiveCount, 3)
        let remaining = await limiter.activeCount
        XCTAssertEqual(remaining, 0)
    }

    func testOfflineStopsWholePrefetchBatchWithoutRefererStorm() async {
        let (repository, session) = makeRepository(offline: true)
        defer { session.invalidateAndCancel() }
        await FocusRemoteImageLoader.prefetch(
            urls: (0..<30).map { imageURL("offline-\($0).png@100w") }, referer: "https://example.test/",
            repository: repository, limiter: FocusImagePrefetchLimiter(limit: 2)
        )
        XCTAssertGreaterThanOrEqual(PerformanceImageProtocol.requestCount, 1)
        XCTAssertLessThanOrEqual(PerformanceImageProtocol.requestCount, 2)
    }

    func testLongGalleryPreservesWidthAndAspectRatherThanUsingThumbnailDecode() async throws {
        let (repository, session) = makeRepository(size: CGSize(width: 256, height: 5_000))
        defer { session.invalidateAndCancel() }
        let url = imageURL("long")
        let thumbnail = try await repository.image(for: url, preferredReferer: "", pixelSize: 256)
        let gallery = try await repository.image(for: url, preferredReferer: "", quality: .gallery)
        XCTAssertEqual(gallery.cgImage?.width, 256)
        XCTAssertEqual(gallery.cgImage?.height, 5_000)
        XCTAssertLessThan(thumbnail.cgImage!.width, gallery.cgImage!.width)
        XCTAssertEqual(Double(gallery.cgImage!.height) / Double(gallery.cgImage!.width), 5_000.0 / 256, accuracy: 0.01)
    }

    func testAnimatedEmotesAreDownsampledCachedAndShared() async throws {
        let (repository, session) = makeRepository(data: animatedGIF(size: CGSize(width: 2_048, height: 2_048)), held: true)
        defer { session.invalidateAndCancel() }
        let url = imageURL("animated-emote")
        let first = Task {
            try await repository.image(for: url, preferredReferer: "", quality: .emote, pixelSize: 128)
        }
        await eventually { PerformanceImageProtocol.activeCount == 1 }
        let second = Task {
            try await repository.image(for: url, preferredReferer: "", quality: .emote, pixelSize: 128)
        }
        await eventuallyAsync { await repository.activeConsumerCount == 2 }
        XCTAssertEqual(PerformanceImageProtocol.requestCount, 1)
        PerformanceImageProtocol.releaseAll()

        let firstImage = try await first.value
        let secondImage = try await second.value
        XCTAssertTrue(firstImage === secondImage)
        XCTAssertEqual(firstImage.images?.count, 2)
        XCTAssertLessThanOrEqual(firstImage.images?.first?.cgImage?.width ?? .max, 128)
        XCTAssertLessThanOrEqual(firstImage.images?.first?.cgImage?.height ?? .max, 128)
        let cached = try await repository.image(for: url, preferredReferer: "", quality: .emote, pixelSize: 128)
        XCTAssertTrue(firstImage === cached)
        XCTAssertEqual(PerformanceImageProtocol.requestCount, 1)
        let reduceMotionImage = try await repository.image(
            for: url,
            preferredReferer: "",
            quality: .emote,
            pixelSize: 128,
            animated: false
        )
        XCTAssertNil(reduceMotionImage.images)
        XCTAssertLessThanOrEqual(reduceMotionImage.cgImage?.width ?? .max, 128)
        XCTAssertEqual(PerformanceImageProtocol.requestCount, 2)
    }

    func testCancelledPrefetchWaiterDoesNotLeakItsSlot() async throws {
        let limiter = FocusImagePrefetchLimiter(limit: 1)
        let first = UUID(), second = UUID()
        try await limiter.acquire(first)
        let waiting = Task {
            do { try await limiter.acquire(second) }
            catch { }
            await limiter.release(second)
        }
        await eventuallyAsync { await limiter.waitingCount == 1 }
        waiting.cancel()
        await waiting.value
        await limiter.release(first)
        let active = await limiter.activeCount
        let queued = await limiter.waitingCount
        XCTAssertEqual(active, 0)
        XCTAssertEqual(queued, 0)
    }

    private func imageURL(_ name: String) -> URL { URL(string: "https://focus-image.test/\(name)")! }
    private func makeRepository(
        size: CGSize = CGSize(width: 512, height: 512), held: Bool = false, offline: Bool = false
    ) -> (FocusImageRepository, URLSession) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
        return makeRepository(data: data, held: held, offline: offline)
    }
    private func makeRepository(
        data: Data, held: Bool = false, offline: Bool = false
    ) -> (FocusImageRepository, URLSession) {
        PerformanceImageProtocol.configure(data: data, held: held, offline: offline)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.protocolClasses = [PerformanceImageProtocol.self]
        let session = URLSession(configuration: configuration)
        return (FocusImageRepository(session: session), session)
    }
    private func animatedGIF(size: CGSize) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let frames = [UIColor.systemBlue, UIColor.systemOrange].map { color in
            renderer.image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }.cgImage!
        }
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, frames.count, nil)!
        let properties: [CFString: Any] = [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: 0.08
        ]]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, properties as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }
    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(predicate(), "Controlled image event did not arrive", file: file, line: line)
    }
    private func eventuallyAsync(_ predicate: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !(await predicate()), ContinuousClock.now < deadline { await Task.yield() }
        let reached = await predicate()
        XCTAssertTrue(reached, "Controlled image state did not arrive", file: file, line: line)
    }
}

private final class PerformanceImageProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var data = Data()
    nonisolated(unsafe) private static var held = false
    nonisolated(unsafe) private static var offline = false
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var peak = 0
    nonisolated(unsafe) private static var active: [ObjectIdentifier: PerformanceImageProtocol] = [:]
    static var requestCount: Int { lock.withLock { count } }
    static var activeCount: Int { lock.withLock { active.count } }
    static var peakActiveCount: Int { lock.withLock { peak } }
    static func configure(data: Data, held: Bool, offline: Bool) {
        lock.withLock { self.data = data; self.held = held; self.offline = offline; count = 0; peak = 0; active.removeAll() }
    }
    static func releaseAll() {
        let requests = lock.withLock { held = false; return Array(active.values) }
        requests.forEach { $0.finish() }
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "focus-image.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let shouldFinish = Self.lock.withLock {
            Self.count += 1; Self.active[ObjectIdentifier(self)] = self
            Self.peak = max(Self.peak, Self.active.count)
            return !Self.held
        }
        if shouldFinish { finish() }
    }
    private func finish() {
        let result: (Data, Bool)? = Self.lock.withLock {
            guard Self.active.removeValue(forKey: ObjectIdentifier(self)) != nil else { return nil }
            return (Self.data, Self.offline)
        }
        guard let (data, offline) = result else { return }
        if offline { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { Self.lock.withLock { _ = Self.active.removeValue(forKey: ObjectIdentifier(self)) } }
}
