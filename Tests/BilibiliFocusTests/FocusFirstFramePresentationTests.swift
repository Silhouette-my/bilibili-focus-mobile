import AVFoundation
import AVKit
import Combine
import FocusCore
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import BilibiliFocus

@MainActor
final class FocusFirstFramePresentationTests: XCTestCase {
    func testControlTimeLabelsAndRenderedLayouts() async throws {
        XCTAssertEqual(FocusNativePlaybackControls.timestamp(0), "00:00")
        XCTAssertEqual(FocusNativePlaybackControls.timestamp(125_000), "02:05")
        XCTAssertEqual(FocusNativePlaybackControls.timestamp(3_661_000), "1:01:01")
        let interactive = ProcessInfo.processInfo.environment["FOCUS_INTERACTIVE_PLAYER_PREVIEW"] == "1"
        let movie = try makeLocalMovie(color: (0.10, 0.16, 0.20), frameCount: interactive ? 900 : 30)
        defer { try? FileManager.default.removeItem(at: movie) }
        let cookieProvider = PlayerControlsTestCookies()
        let model = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(cookieProvider: cookieProvider, requestLoader: PlayerControlsTestAPI.response),
            actionService: FocusVideoActionService(cookieProvider: cookieProvider, requestLoader: PlayerControlsTestAPI.response),
            playbackProgressStore: FocusPlaybackProgressStore(persistence: PlayerControlsTestPersistence()),
            nativeDanmakuEnabled: false, nativeSubtitleEnabled: false,
            playbackItemFactory: { _ in [AVPlayerItem(url: movie)] }
        )
        model.activate(url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!)
        defer { model.suspend() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !model.hasPreparedPlayer && ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(model.hasPreparedPlayer, model.playerErrorMessage ?? "Player did not prepare")
        model.player.pause()
        for (name, size, fullscreen) in [
            ("player-controls-inline", CGSize(width: 393, height: 222), false),
            ("player-controls-fullscreen", CGSize(width: 852, height: 393), true),
            ("player-controls-compact", CGSize(width: 320, height: 180), false),
        ] {
            let host = UIHostingController(rootView: PlayerControlsRenderHarness(model: model, fullscreen: fullscreen))
            if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            window.layoutIfNeeded()
            await Task.yield()
            try await Task.sleep(nanoseconds: 100_000_000)
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(host.view.bounds.size, size)
            window.isHidden = true
            window.rootViewController = nil
        }
        // Render the actual fullscreen root with device insets. The component
        // previews above deliberately remove safe areas and cannot catch a
        // second inset introduced by the presented phone layout.
        let fullscreenSize = CGSize(width: 874, height: 402)
        let fullscreenHost = UIHostingController(rootView: FocusNativeVideoFullscreenView(viewModel: model, accentColor: .pink))
        fullscreenHost.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62)
        let fullscreenWindow = UIWindow(frame: CGRect(origin: .zero, size: fullscreenSize))
        fullscreenWindow.rootViewController = fullscreenHost
        fullscreenWindow.makeKeyAndVisible()
        fullscreenHost.view.frame = fullscreenWindow.bounds
        fullscreenWindow.layoutIfNeeded()
        await Task.yield()
        try await Task.sleep(nanoseconds: 100_000_000)
        fullscreenHost.view.layoutIfNeeded()
        let playerController = try XCTUnwrap(Self.playerController(in: fullscreenHost))
        let surfaceFrame = playerController.view.convert(playerController.view.bounds, to: fullscreenWindow)
        XCTAssertEqual(surfaceFrame.minX, 0, accuracy: 1)
        XCTAssertEqual(surfaceFrame.minY, 0, accuracy: 1)
        XCTAssertEqual(surfaceFrame.width, fullscreenSize.width, accuracy: 1)
        XCTAssertEqual(surfaceFrame.height, fullscreenSize.height, accuracy: 1)
        let fullscreenImage = UIGraphicsImageRenderer(size: fullscreenSize).image { _ in
            fullscreenHost.view.drawHierarchy(in: fullscreenHost.view.bounds, afterScreenUpdates: true)
        }
        let fullscreenAttachment = XCTAttachment(image: fullscreenImage)
        fullscreenAttachment.name = "player-fullscreen-phone-safeareas"
        fullscreenAttachment.lifetime = .keepAlways
        add(fullscreenAttachment)
        fullscreenWindow.isHidden = true
        fullscreenWindow.rootViewController = nil
        // Explicit opt-in for manual simulator gestures against the real detail
        // view. All APIs and media remain the same isolated fixtures as above.
        if interactive {
            var events: [String] = []
            let rateObservation = model.$playbackRate.sink { events.append("rate=\($0)") }
            let playObservation = model.$isPlaying.sink { events.append("playing=\($0)") }
            let qualityObservation = model.$selectedQuality.sink { events.append("quality=\($0)") }
            defer {
                rateObservation.cancel(); playObservation.cancel(); qualityObservation.cancel()
                let trace = XCTAttachment(string: events.joined(separator: "\n"))
                trace.name = "interactive-player-state-events"
                trace.lifetime = .keepAlways
                add(trace)
            }
            let host = UIHostingController(rootView: FocusNativeVideoDetailView(
                viewModel: model, onOpenUser: { _ in }, onOpenVideo: { _ in },
                onOpenURL: { _ in }, onOpenWeb: { _ in }, accentColor: .pink
            ).accentColor(.pink))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = UIScreen.main.bounds
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(nanoseconds: 300_000_000_000)
        }
    }

    private static func playerController(in controller: UIViewController) -> AVPlayerViewController? {
        if let player = controller as? AVPlayerViewController { return player }
        return controller.children.lazy.compactMap { playerController(in: $0) }.first
    }

    func testFullscreenControlsConsumeDeviceInsetsOnlyOnce() {
        let insets = FocusNativePlaybackControls.contentInsets(
            isFullscreen: true, safeArea: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)
        )
        XCTAssertEqual(insets.leading, 62)
        XCTAssertEqual(insets.trailing, 62)
        XCTAssertEqual(insets.bottom, 21)
        XCTAssertEqual(insets.top, 6)
        let noCutout = FocusNativePlaybackControls.contentInsets(isFullscreen: true, safeArea: EdgeInsets())
        XCTAssertEqual(noCutout.leading, 12)
        XCTAssertEqual(noCutout.bottom, 6)
    }

    func testDanmakuRendererSamplesActualPlayerClockAtTripleSpeed() async throws {
        let movie = try makeLocalMovie(color: (0.10, 0.16, 0.20), frameCount: 900)
        defer { try? FileManager.default.removeItem(at: movie) }
        let cookies = PlayerControlsTestCookies()
        let model = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(cookieProvider: cookies, requestLoader: PlayerControlsTestAPI.response),
            actionService: FocusVideoActionService(cookieProvider: cookies, requestLoader: PlayerControlsTestAPI.response),
            playbackProgressStore: FocusPlaybackProgressStore(persistence: PlayerControlsTestPersistence()),
            nativeDanmakuEnabled: false, nativeSubtitleEnabled: false,
            playbackItemFactory: { _ in [AVPlayerItem(url: movie)] }
        )
        model.activate(url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!)
        defer { model.suspend() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !model.hasPreparedPlayer && ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(model.hasPreparedPlayer)
        model.installFixtureDanmakus((0..<100).map { index in
            FocusVideoDanmaku(id: Int64(index), progressMilliseconds: Int64(index * 200), mode: .scrolling,
                             fontSize: 25, colorRGB: nil, content: "3 倍速弹幕 · 连续移动测试 \(index)", weight: 0, pool: 0)
        })
        var samples: [(wallTime: CFTimeInterval, mediaTime: Int64)] = []
        let host = UIHostingController(rootView: ZStack {
            Color.black
            FocusNativePlayerSurface(surfaceID: UUID(), player: model.player, showsPlaybackControls: false,
                                     onReadyForDisplayChange: { _, _, _ in })
            FocusNativeDanmakuOverlay(viewModel: model, onFixtureFrame: { samples.append(($0, $1)) })
        })
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        model.setPlaybackRate(3)
        model.player.playImmediately(atRate: 3)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let moving = samples.filter { $0.mediaTime > 0 }
        let state = XCTAttachment(string: "samples=\(samples)\nplayerTime=\(model.player.currentTime().seconds)\nrate=\(model.player.rate)\nisPlaying=\(model.isPlaying)\nstatus=\(model.player.timeControlStatus.rawValue)\ncomments=\(model.danmakus.count)")
        state.name = "danmaku-render-clock-state"
        state.lifetime = .keepAlways
        add(state)
        guard moving.count > 2 else { return XCTFail("The renderer did not emit moving frames") }
        let first = try XCTUnwrap(moving.first), last = try XCTUnwrap(moving.last)
        let speed = Double(last.mediaTime - first.mediaTime) / 1_000 / (last.wallTime - first.wallTime)
        XCTAssertEqual(speed, 3, accuracy: 0.2, "Renderer must sample AVPlayer's 3x clock, not UI progress ticks")
        let intervals = zip(moving, moving.dropFirst()).map { $1.wallTime - $0.wallTime }.sorted()
        let measured = XCTAttachment(string: "samples=\(moving.count)\nmediaRate=\(speed)\nmedianFrameIntervalMs=\(intervals[intervals.count / 2] * 1000)\nmaximumFramesPerSecond=\(UIScreen.main.maximumFramesPerSecond)")
        measured.name = "danmaku-render-cadence-simulator"
        measured.lifetime = .keepAlways
        add(measured)
        let image = XCTAttachment(image: UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        })
        image.name = "danmaku-triple-speed-render"
        image.lifetime = .keepAlways
        add(image)
        model.player.pause()
        try await Task.sleep(nanoseconds: 100_000_000)
        let pausedTime = model.danmakuPlaybackPositionMilliseconds
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.danmakuPlaybackPositionMilliseconds, pausedTime)
    }

    func testScrubberCommitsOnceOnReleaseAndSupportsAccessibilityAdjustment() {
        var position: Double = 20
        var phases: [Bool] = []
        let control = FocusPlaybackSeekSlider(value: Binding(get: { position }, set: { position = $0 }),
                                             maximum: 100, tint: .pink,
                                             onEditingChanged: { phases.append($0) })
        let coordinator = control.makeCoordinator()
        let slider = UISlider()
        slider.maximumValue = 100
        coordinator.begin(slider)
        slider.value = 60
        coordinator.change(slider)
        XCTAssertEqual(position, Double(slider.value), "Forward UIKit's actual Float value without a second quantization")
        XCTAssertEqual(phases, [true], "Dragging must not commit a seek for every movement")
        coordinator.end(slider)
        XCTAssertEqual(phases, [true, false])
        slider.value = 70
        coordinator.change(slider)
        XCTAssertEqual(position, Double(slider.value))
        XCTAssertEqual(phases, [true, false, true, false])
    }

    func testReadyEventArrivingBeforeItemEventIsNotLost() async {
        let first = AVPlayerItem(asset: AVMutableComposition())
        let second = AVPlayerItem(asset: AVMutableComposition())
        let player = AVQueuePlayer(items: [first])
        let controller = FirstFrameReadyController()
        controller.player = player
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        let ready = expectation(description: "early ready event is preserved")
        var didReport = false
        var acceptsEvents = true
        let coordinator = FocusNativePlayerSurface.Coordinator(surfaceID: UUID()) { _, itemID, isReady in
            if acceptsEvents, isReady, itemID == ObjectIdentifier(second), !didReport {
                didReport = true
                ready.fulfill()
            }
        }
        coordinator.attach(controller: controller, player: player)
        defer {
            acceptsEvents = false
            coordinator.detach(controller: controller)
            player.removeAllItems()
            window.isHidden = true
            window.rootViewController = nil
        }
        player.replaceCurrentItem(with: second)
        // Deliver readiness before the queued currentItem KVO task gets to run.
        coordinator.handleReadiness(true, for: second)
        await fulfillment(of: [ready], timeout: 2)
    }

    func testMountedSurfaceStateKeepsCoverUntilFirstFrameForInsertedAndReplacedItems() async throws {
        let firstMovieURL = try makeLocalMovie(color: (0.9, 0.1, 0.1))
        let secondMovieURL = try makeLocalMovie(color: (0.1, 0.8, 0.2))
        defer {
            try? FileManager.default.removeItem(at: firstMovieURL)
            try? FileManager.default.removeItem(at: secondMovieURL)
        }

        let player = AVQueuePlayer()
        player.pause()

        let initialCover = expectation(description: "empty player starts with the cover")
        let firstFramePresented = expectation(description: "first current item removes the cover")
        let coverRestoredForReplacement = expectation(description: "replacement restores the cover")
        let replacementFramePresented = expectation(description: "replacement first frame removes the cover")
        var active = true
        var initialCoverSeen = false
        var firstFrameSeen = false
        var replacementCoverSeen = false
        var replacementFrameSeen = false
        let host = UIHostingController(
            rootView: FirstFramePresentationHarness(
                player: player,
                onCoverVisibilityChange: { isVisible in
                    guard active else { return }
                    if isVisible {
                        if firstFrameSeen, !replacementCoverSeen {
                            replacementCoverSeen = true
                            coverRestoredForReplacement.fulfill()
                        } else if !initialCoverSeen {
                            initialCoverSeen = true
                            initialCover.fulfill()
                        }
                    } else if !firstFrameSeen {
                        firstFrameSeen = true
                        firstFramePresented.fulfill()
                    } else if replacementCoverSeen, !replacementFrameSeen {
                        replacementFrameSeen = true
                        replacementFramePresented.fulfill()
                    }
                }
            )
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        defer {
            active = false
            player.pause()
            player.removeAllItems()
            window.isHidden = true
            window.rootViewController = nil
        }

        await fulfillment(of: [initialCover], timeout: 3)
        player.insert(AVPlayerItem(url: firstMovieURL), after: nil)
        player.play()
        await fulfillment(of: [firstFramePresented], timeout: 8)
        XCTAssertTrue(player.currentItem?.status == .readyToPlay)

        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: secondMovieURL))
        await fulfillment(of: [coverRestoredForReplacement], timeout: 3)
        player.play()
        await fulfillment(of: [replacementFramePresented], timeout: 8)
        XCTAssertTrue(player.currentItem?.status == .readyToPlay)
    }

    private func makeLocalMovie(color: (red: CGFloat, green: CGFloat, blue: CGFloat), frameCount: Int = 30) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-first-frame-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64,
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ]
        )
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw FirstFrameTestError.cannotAddWriterInput }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? FirstFrameTestError.cannotStartWriter
        }
        writer.startSession(atSourceTime: .zero)

        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else {
                    throw writer.error ?? FirstFrameTestError.writerDidNotFinish
                }
                guard ContinuousClock.now < deadline else {
                    writer.cancelWriting()
                    throw FirstFrameTestError.writerDidNotFinish
                }
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw FirstFrameTestError.missingPixelBufferPool
            }
            var optionalBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
            guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
                throw FirstFrameTestError.cannotAllocatePixelBuffer(status)
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let pixel = base.assumingMemoryBound(to: UInt8.self)
                let blue = UInt8(color.blue * 255)
                let green = UInt8(color.green * 255)
                let red = UInt8(color.red * 255)
                for pixelIndex in stride(from: 0, to: CVPixelBufferGetDataSize(buffer), by: 4) {
                    pixel[pixelIndex] = 255
                    pixel[pixelIndex + 1] = red
                    pixel[pixelIndex + 2] = green
                    pixel[pixelIndex + 3] = blue
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw writer.error ?? FirstFrameTestError.cannotAppendFrame
            }
        }

        input.markAsFinished()
        let finished = expectation(description: "local movie finishes writing")
        writer.finishWriting { finished.fulfill() }
        wait(for: [finished], timeout: 8)
        guard writer.status == .completed else {
            throw writer.error ?? FirstFrameTestError.writerDidNotFinish
        }
        return url
    }
}

@MainActor
private struct FirstFramePresentationHarness: View {
    let player: AVPlayer
    let surfaceID = UUID()
    let onCoverVisibilityChange: (Bool) -> Void
    @State private var readyItemID: ObjectIdentifier?

    var body: some View {
        ZStack {
            Color.black
            FocusNativePlayerSurface(
                surfaceID: surfaceID,
                player: player,
                showsPlaybackControls: false,
                onReadyForDisplayChange: { callbackSurfaceID, itemID, isReady in
                    guard callbackSurfaceID == surfaceID else { return }
                    readyItemID = isReady ? itemID : nil
                }
            )
            .id(surfaceID)
            if readyItemID == nil {
                Color.red
                    .accessibilityIdentifier("first-frame-cover")
            }
        }
        .onAppear {
            onCoverVisibilityChange(true)
        }
        .onChange(of: readyItemID) { itemID in
            onCoverVisibilityChange(itemID == nil)
        }
    }
}

private final class FirstFrameReadyController: AVPlayerViewController {
    override var isReadyForDisplay: Bool { true }
}

private enum FirstFrameTestError: Error {
    case cannotAddWriterInput
    case cannotStartWriter
    case missingPixelBufferPool
    case cannotAllocatePixelBuffer(CVReturn)
    case cannotAppendFrame
    case writerDidNotFinish
}

private struct PlayerControlsTestCookies: CookieSnapshotProvider {
    func loadCookies() async -> [HTTPCookie] { [] }
}

@MainActor
private struct PlayerControlsRenderHarness: View {
    let model: FocusNativeVideoViewModel
    let fullscreen: Bool
    @State private var bottomInset: CGFloat = 90
    private let surfaceID = UUID()

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.16, blue: 0.20)
            FocusNativePlayerSurface(surfaceID: surfaceID, player: model.player, showsPlaybackControls: false,
                                     onReadyForDisplayChange: { _, _, _ in })
            FocusNativePlaybackControls(viewModel: model, isFullscreen: fullscreen, title: "离线播放测试 · 原生控制层",
                                        accentColor: Color(red: 0.98, green: 0.35, blue: 0.55),
                                        onBottomOcclusionChange: { bottomInset = $0 })
            FocusNativeSubtitleCaption(content: "字幕应始终位于播放控制上方", isFullscreen: fullscreen, bottomInset: bottomInset)
                .allowsHitTesting(false)
        }
        .accentColor(Color(red: 0.98, green: 0.35, blue: 0.55))
    }
}

private actor PlayerControlsTestPersistence: FocusPlaybackStatePersistence {
    private var data: Data?
    func loadPlaybackState() -> Data? { data }
    func savePlaybackState(_ data: Data) { self.data = data }
}

private enum PlayerControlsTestAPI {
    static func response(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let payload: String
        switch request.url!.path {
        case "/x/web-interface/view":
            payload = #"{"code":0,"data":{"bvid":"BV1xx411c7mD","aid":42,"cid":4201,"title":"离线播放测试","duration":30,"dimension":{"width":1920,"height":1080},"owner":{"mid":1,"name":"Fixture"},"pages":[{"cid":4201,"page":1,"duration":30,"part":"Part 1"}]}}"#
        case "/x/player/playurl", "/x/player/wbi/playurl":
            let quality = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "qn" }?.value ?? "80"
            payload = #"{"code":0,"data":{"quality":\#(quality),"accept_quality":[80,64],"accept_description":["1080P 高清","720P 高清"],"durl":[{"url":"https://media.test/video.mp4"}]}}"#
        case "/x/player/v2", "/x/player/wbi/v2":
            payload = #"{"code":0,"data":{"last_play_cid":0,"last_play_time":0}}"#
        default:
            payload = #"{"code":0,"data":{"replies":[]}}"#
        }
        return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
