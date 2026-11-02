import AVFoundation
import FocusCore
import Foundation
import XCTest
@testable import BilibiliFocus

/// Exercises AVPlayer's real local-file loading path. This intentionally does
/// not use a player-layer or replace the production readiness waiter.
@MainActor
final class FocusRealPlaybackTests: XCTestCase {
    func testSynchronousVideoModelLifetimeTearsDownWithoutAnAsyncTaskContext() {
        // Route pops can drop their final VM reference in a synchronous UIKit
        // callback. Exercise that lifetime separately from async playback tests.
        for _ in 0..<3 {
            weak var releasedModel: FocusNativeVideoViewModel?
            autoreleasepool {
                let cookies = PlaybackFixtureCookies()
                let api = PlaybackQualityFixtureAPI()
                let model = FocusNativeVideoViewModel(
                    detailService: FocusVideoDetailService(cookieProvider: cookies, requestLoader: { await api.response(for: $0) }),
                    actionService: FocusVideoActionService(cookieProvider: cookies, requestLoader: { await api.response(for: $0) }),
                    playbackProgressStore: FocusPlaybackProgressStore(persistence: PlaybackFixturePersistence()),
                    nativeDanmakuEnabled: false, nativeSubtitleEnabled: false)
                releasedModel = model
                model.suspend()
            }
            XCTAssertNil(releasedModel)
        }
    }

    func testLateCommentMutationsCannotOverwriteAReplacedCommentSession() async throws {
        for deletesComment in [false, true] {
            let cookies = [
                HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: "DedeUserID", .value: "1001"])!,
                HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: "SESSDATA", .value: "fixture-session"])!,
                HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: "bili_jct", .value: "fixture-csrf"])!,
            ]
            let provider = CommentMutationFixtureCookies(cookies: cookies)
            let scope = FocusPlaybackAccountScope.resolve(cookies: cookies)
            let gate = CommentMutationScopeGate(scope: scope)
            let api = CommentMutationFixtureAPI()
            let model = FocusNativeVideoViewModel(
                detailService: FocusVideoDetailService(cookieProvider: provider, requestLoader: { await api.response(for: $0) }),
                actionService: FocusVideoActionService(cookieProvider: provider, requestLoader: { await api.response(for: $0) }),
                commentService: FocusVideoCommentService(cookieProvider: provider, requestLoader: { await api.response(for: $0) }),
                playbackProgressStore: FocusPlaybackProgressStore(persistence: PlaybackFixturePersistence()),
                accountScopeProvider: { await gate.resolve() }, nativeDanmakuEnabled: false, nativeSubtitleEnabled: false)
            defer { model.suspend() }
            let detail = try FocusVideoDetailService.decodeDetailResponse(Data(#"{"code":0,"data":{"bvid":"BV1xx411c7mD","aid":42,"cid":4201,"title":"Comment fixture","duration":30,"owner":{"mid":1,"name":"fixture"},"pages":[{"page":1,"cid":4201,"part":"fixture","duration":30}]}}"#.utf8))
            let comment = FocusVideoComment(id: 90099, authorMID: 1001, authorName: "fixture", avatarURL: nil,
                                           message: "新会话评论", likes: 0, replies: 0, publishedAt: 1)
            model.installFixtureDetail(detail)
            model.installFixtureComments([comment], accountScope: scope)
            if deletesComment {
                model.deleteComment(comment)
            } else {
                model.commentDraft = "旧会话草稿"
                model.sendComment()
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while !(await gate.isWaiting) {
                guard ContinuousClock.now < deadline else { throw PlaybackTestError.conditionTimeout }
                try await Task.sleep(for: .milliseconds(10))
            }
            let pending = model.fixtureCommentMutationTasks
            model.suspend()
            model.installFixtureDetail(detail)
            model.installFixtureComments([comment], accountScope: scope)
            model.commentDraft = "新会话草稿"
            await gate.release()
            for task in pending { await task.value }
            XCTAssertEqual(model.comments, [comment], "A late \(deletesComment ? "delete" : "send") acknowledgement belongs to the old session")
            XCTAssertEqual(model.commentDraft, "新会话草稿")
            XCTAssertEqual(model.displayedCommentCount, 1)
        }
    }

    func testCommentDraftSurvivesFailureAndOwnPostedCommentCanBeDeleted() async throws {
        let cookies = [
            HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: "DedeUserID", .value: "1001"])!,
            HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: "SESSDATA", .value: "fixture-session"])!,
            HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: "bili_jct", .value: "fixture-csrf"])!,
        ]
        let provider = CommentMutationFixtureCookies(cookies: cookies)
        let scope = FocusPlaybackAccountScope.resolve(cookies: cookies)
        let api = CommentMutationFixtureAPI()
        let model = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(cookieProvider: provider, requestLoader: { await api.response(for: $0) }),
            actionService: FocusVideoActionService(cookieProvider: provider, requestLoader: { await api.response(for: $0) }),
            commentService: FocusVideoCommentService(cookieProvider: provider, requestLoader: { await api.response(for: $0) }),
            playbackProgressStore: FocusPlaybackProgressStore(persistence: PlaybackFixturePersistence()),
            accountScopeProvider: { scope }, nativeDanmakuEnabled: false, nativeSubtitleEnabled: false)
        defer { model.suspend() }
        let detail = try FocusVideoDetailService.decodeDetailResponse(Data(#"{"code":0,"data":{"bvid":"BV1xx411c7mD","aid":42,"cid":4201,"title":"Comment fixture","duration":30,"owner":{"mid":1,"name":"fixture"},"pages":[{"page":1,"cid":4201,"part":"fixture","duration":30}]}}"#.utf8))
        model.installFixtureDetail(detail)
        model.installFixtureComments([], accountScope: scope)
        model.composeComment()
        model.commentDraft = "保留草稿"
        await api.setRejectMutations(true)
        model.sendComment()
        try await waitUntil { !model.isSendingComment }
        XCTAssertEqual(model.commentDraft, "保留草稿")
        XCTAssertTrue(model.showsCommentComposer)
        XCTAssertNotNil(model.commentComposeError)
        XCTAssertTrue(model.comments.isEmpty)
        await api.setRejectMutations(false)
        model.sendComment()
        try await waitUntil { !model.isSendingComment }
        XCTAssertEqual(model.commentDraft, "")
        XCTAssertFalse(model.showsCommentComposer)
        let ownComment = try XCTUnwrap(model.comments.first)
        XCTAssertTrue(model.canDeleteComment(ownComment))
        model.deleteComment(ownComment)
        try await waitUntil { model.commentDeletesInFlight.isEmpty }
        XCTAssertTrue(model.comments.isEmpty)
        let mutationPaths = await api.mutationPaths
        XCTAssertEqual(mutationPaths, ["/x/v2/reply/add", "/x/v2/reply/add", "/x/v2/reply/del"])
    }

    func testRememberedRateDoesNotPersistTemporaryHold() async throws {
        let movieURL = try makeLocalMovie(frameCount: 180)
        defer { try? FileManager.default.removeItem(at: movieURL) }
        var changes: [FocusPlaybackPreferences] = []
        let model = try makeLocalPlaybackModel(movieURL: movieURL, api: PlaybackQualityFixtureAPI(), metadataDuration: 6,
            preferences: FocusPlaybackPreferences(preferredRate: 1.5), onPreferences: { changes.append($0) })
        defer { model.suspend() }
        XCTAssertEqual(model.playbackRate, 1.5)
        model.retryPlayback()
        try await waitUntil { model.isPlaying }
        model.beginTemporaryPlaybackRate()
        XCTAssertEqual(model.playbackRate, 2)
        XCTAssertTrue(changes.isEmpty)
        model.endTemporaryPlaybackRate()
        XCTAssertEqual(model.playbackRate, 1.5)
        model.setPlaybackRate(1.25)
        XCTAssertEqual(changes.last?.preferredRate, 1.25)
        model.setSleepTimer(minutes: 15)
        XCTAssertEqual(model.sleepTimerMinutes, 15)
        model.setSleepTimer(minutes: nil)
        XCTAssertNil(model.sleepTimerMinutes)
    }

    func testRuntimeRecoveryPreservesPausedPositionAndAutomaticallyStepsDown() async throws {
        let movieURL = try makeLocalMovie(frameCount: 180)
        defer { try? FileManager.default.removeItem(at: movieURL) }
        let api = PlaybackQualityFixtureAPI()
        let model = try makeLocalPlaybackModel(movieURL: movieURL, api: api, metadataDuration: 6)
        defer { model.suspend() }
        model.retryPlayback()
        try await waitUntil { model.isPlaying }
        model.togglePlayback()
        model.setPlaybackRate(1.5)
        model.seek(toMilliseconds: 500)
        try await waitUntil { abs(model.player.currentTime().seconds - 0.5) < 0.05 }
        model.simulateFixturePlaybackInterruption(URLError(.networkConnectionLost))
        try await waitUntil { model.hasPreparedPlayer && !model.hasActivePlaybackPreparationTask }
        XCTAssertEqual(model.selectedPageCID, 4201)
        XCTAssertEqual(model.selectedQuality, 64)
        XCTAssertTrue(model.isAutomaticQuality)
        XCTAssertEqual(model.player.currentTime().seconds, 0.5, accuracy: 0.05)
        XCTAssertEqual(model.playbackRate, 1.5)
        XCTAssertEqual(model.player.rate, 0)
        let qualities = await api.requestedQualities
        XCTAssertEqual(qualities, [80, 64])
    }

    func testRuntimeRecoveryHasFiniteBudgetAndNeverChangesManualQuality() async throws {
        let movieURL = try makeLocalMovie(frameCount: 180)
        defer { try? FileManager.default.removeItem(at: movieURL) }
        let api = PlaybackQualityFixtureAPI()
        let model = try makeLocalPlaybackModel(movieURL: movieURL, api: api, metadataDuration: 6)
        defer { model.suspend() }
        model.retryPlayback()
        try await waitUntil { model.isPlaying }
        model.selectQuality(try XCTUnwrap(model.availableQualities.first { $0.id == 80 }))
        try await waitUntil { model.hasPreparedPlayer && !model.hasActivePlaybackPreparationTask }
        for _ in 0..<2 {
            model.simulateFixturePlaybackInterruption(URLError(.networkConnectionLost))
            try await waitUntil { model.hasPreparedPlayer && !model.hasActivePlaybackPreparationTask }
        }
        model.simulateFixturePlaybackInterruption(URLError(.networkConnectionLost))
        XCTAssertFalse(model.hasPreparedPlayer)
        XCTAssertNotNil(model.playerErrorMessage)
        XCTAssertFalse(model.isAutomaticQuality)
        let qualities = await api.requestedQualities
        XCTAssertEqual(qualities, [80, 80, 80, 80])
    }

    func testPermissionFailureIsNotRetriedAndNextPartIsOptIn() async throws {
        let movieURL = try makeLocalMovie()
        defer { try? FileManager.default.removeItem(at: movieURL) }
        let api = PlaybackQualityFixtureAPI()
        let model = try makeLocalPlaybackModel(movieURL: movieURL, api: api, pageCount: 2)
        defer { model.suspend() }
        model.retryPlayback()
        try await waitUntil { model.hasPreparedPlayer }
        model.simulateFixturePlaybackInterruption(FocusVideoDetailService.ServiceError.api(code: -403, message: "拒绝"))
        XCTAssertFalse(model.hasPreparedPlayer)
        let requestsAfterPermissionFailure = await api.requestedQualities
        XCTAssertEqual(requestsAfterPermissionFailure, [80])
        model.retryPlayback()
        try await waitUntil { model.hasPlaybackEnded }
        XCTAssertEqual(model.selectedPageCID, 4201)
        model.updatePlaybackPreferences { $0.autoPlayNextPart = true }
        model.retryPlayback()
        try await waitUntil { model.selectedPageCID == 4202 }
        try await waitUntil { model.hasPlaybackEnded }
        XCTAssertEqual(model.selectedPageCID, 4202, "The last part must stop, not loop or start recommendations")
    }

    func testQueuedPositiveRateCallbackCannotTurnPausedSelectedSpeedIntoZero() async throws {
        let movieURL = try makeLocalMovie()
        defer { try? FileManager.default.removeItem(at: movieURL) }
        let model = try makeLocalPlaybackModel(movieURL: movieURL, api: PlaybackQualityFixtureAPI())
        defer { model.suspend() }
        model.retryPlayback()
        try await waitUntil { model.hasPreparedPlayer }
        model.player.pause()
        // Drain the initial play's observations before creating the specific
        // positive-rate -> immediate-pause sequence under test.
        await Task.yield()
        model.setPlaybackRate(1.25)
        let positiveRate = expectation(description: "real AVPlayer emitted a positive rate")
        positiveRate.assertForOverFulfill = false
        let observation = model.player.observe(\.rate, options: [.new]) { player, _ in
            if player.rate > 0 { positiveRate.fulfill() }
        }
        model.player.playImmediately(atRate: 1.25)
        model.player.pause()
        await fulfillment(of: [positiveRate], timeout: 2)
        await Task.yield()
        XCTAssertEqual(model.player.rate, 0)
        XCTAssertEqual(model.playbackRate, 1.25, "A delayed positive-rate notification must not read pause's 0 into the speed selection")
        var transportStates: [String] = []
        func recordTransport(_ stage: String) {
            transportStates.append("\(stage): rate=\(model.player.rate), selected=\(model.playbackRate), timeControl=\(model.player.timeControlStatus.rawValue), item=\(model.player.currentItem?.status.rawValue ?? -1), position=\(model.player.currentTime().seconds), loading=\(model.isLoadingPlayback), prepared=\(model.hasPreparedPlayer)")
        }
        defer {
            recordTransport("final")
            let attachment = XCTAttachment(string: transportStates.joined(separator: "\n"))
            attachment.name = "paused-rate-resume-transport"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let pausedTime = model.player.currentTime().seconds
        recordTransport("before-toggle")
        model.togglePlayback()
        recordTransport("after-toggle")
        try await waitUntil {
            model.player.timeControlStatus == .playing && model.player.currentTime().seconds > pausedTime
        }
        recordTransport("playing")
        XCTAssertEqual(model.player.rate, 1.25, accuracy: 0.001)
        observation.invalidate()
    }

    func testPlaybackSpeedFormattingPreservesEveryOfferedFraction() {
        let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3]
        XCTAssertEqual(rates.map(FocusNativeVideoFormatting.rate), ["0.5x", "0.75x", "1x", "1.25x", "1.5x", "2x", "3x"])
    }

    func testToggleDistinguishesStalePlayingStatusFromAnOutstandingBufferingRequest() {
        XCTAssertFalse(FocusNativePlaybackLifecyclePolicy.isPlaybackRequested(rate: 0, timeControlStatus: .playing))
        XCTAssertFalse(FocusNativePlaybackLifecyclePolicy.isPlaybackRequested(rate: 0, timeControlStatus: .paused))
        XCTAssertTrue(FocusNativePlaybackLifecyclePolicy.isPlaybackRequested(rate: 1.25, timeControlStatus: .playing))
        XCTAssertTrue(FocusNativePlaybackLifecyclePolicy.isPlaybackRequested(rate: 0, timeControlStatus: .waitingToPlayAtSpecifiedRate))
        XCTAssertTrue(FocusNativePlaybackLifecyclePolicy.isPlaybackRequested(rate: 1.25, timeControlStatus: .waitingToPlayAtSpecifiedRate))
    }

    func testPlaybackEndKeepsActualDurationAndSelectedSpeedAndCanReplay() async throws {
        let movieURL = try makeLocalMovie()
        defer { try? FileManager.default.removeItem(at: movieURL) }
        let model = try makeLocalPlaybackModel(movieURL: movieURL, api: PlaybackQualityFixtureAPI(), metadataDuration: 120)
        defer { model.suspend() }
        model.setPlaybackRate(1.25)
        model.retryPlayback()
        try await waitUntil { model.hasPreparedPlayer }
        try await waitUntil { model.hasPlaybackEnded }
        XCTAssertNil(model.player.currentItem)
        XCTAssertLessThanOrEqual(abs(model.playbackDurationMilliseconds - 1_000), 50)
        XCTAssertEqual(model.playbackRate, 1.25)
        model.togglePlayback()
        try await waitUntil { model.hasPreparedPlayer && !model.hasActivePlaybackPreparationTask }
        XCTAssertFalse(model.hasPlaybackEnded)
        XCTAssertNotNil(model.player.currentItem)
        XCTAssertEqual(model.playbackRate, 1.25)
    }

    func testQualitySwitchKeepsLocalPositionAndPausedStateWithoutAnotherResumeLookup() async throws {
        let movieURL = try makeLocalMovie()
        defer { try? FileManager.default.removeItem(at: movieURL) }
        let api = PlaybackQualityFixtureAPI()
        let model = try makeLocalPlaybackModel(movieURL: movieURL, api: api)
        defer { model.suspend() }
        model.retryPlayback()
        try await waitUntil { model.hasPreparedPlayer }
        model.player.pause()
        model.seek(toMilliseconds: 300)
        try await waitUntil { abs(model.player.currentTime().seconds - 0.3) < 0.05 }
        let historyCalls = await api.historyCalls
        let quality = try XCTUnwrap(model.availableQualities.first(where: { $0.id == 64 }))
        model.selectQuality(quality)
        try await waitUntil { model.hasPreparedPlayer && !model.hasActivePlaybackPreparationTask }
        XCTAssertEqual(model.selectedPageCID, 4201)
        XCTAssertEqual(model.selectedQuality, 64)
        XCTAssertEqual(model.qualityDescription, "720P")
        XCTAssertFalse(model.isAutomaticQuality)
        XCTAssertTrue(model.isQualitySelected(quality))
        XCTAssertEqual(model.player.currentTime().seconds, 0.3, accuracy: 0.05)
        XCTAssertEqual(model.player.rate, 0, "A quality selection must not resume a paused video")
        let callsAfterSwitch = await api.historyCalls
        XCTAssertEqual(callsAfterSwitch, historyCalls)
        model.selectQuality(quality)
        let requestedQualities = await api.requestedQualities
        XCTAssertEqual(requestedQualities, [80, 64], "Selecting the active quality does not reload playback")
        XCTAssertFalse(model.hasActivePlaybackPreparationTask)

        model.setPlaybackRate(1.25)
        model.selectAutomaticQuality()
        try await waitUntil { model.hasPreparedPlayer && !model.hasActivePlaybackPreparationTask }
        XCTAssertTrue(model.isAutomaticQuality)
        XCTAssertEqual(model.selectedPageCID, 4201)
        XCTAssertEqual(model.selectedQuality, 80)
        XCTAssertEqual(model.player.currentTime().seconds, 0.3, accuracy: 0.05)
        XCTAssertEqual(model.player.rate, 0)
        XCTAssertEqual(model.playbackRate, 1.25)
        model.selectAutomaticQuality()
        let callsAfterAutomaticSelection = await api.requestedQualities
        XCTAssertEqual(callsAfterAutomaticSelection, [80, 64, 80])
        let historyCallsAfterAutomaticSelection = await api.historyCalls
        XCTAssertEqual(historyCallsAfterAutomaticSelection, historyCalls)

        model.player.playImmediately(atRate: 1.25)
        model.beginTemporaryPlaybackRate()
        XCTAssertEqual(model.playbackRate, 2)
        model.endTemporaryPlaybackRate()
        XCTAssertEqual(model.playbackRate, 1.25)
        model.setPlaybackRate(3)
        model.beginTemporaryPlaybackRate()
        XCTAssertEqual(model.playbackRate, 3, "A 2x hold must not slow an existing 3x selection")
        model.endTemporaryPlaybackRate()
        XCTAssertEqual(model.playbackRate, 3)
    }

    func testAutomaticQualityRemainsSelectedWhenServerDeliversAnotherRepresentation() async throws {
        let movieURL = try makeLocalMovie()
        defer { try? FileManager.default.removeItem(at: movieURL) }
        let api = PlaybackQualityFixtureAPI(deliveredQuality: 64)
        let model = try makeLocalPlaybackModel(movieURL: movieURL, api: api)
        defer { model.suspend() }
        model.retryPlayback()
        try await waitUntil { model.hasPreparedPlayer }
        model.player.pause()
        model.seek(toMilliseconds: 300)
        try await waitUntil { abs(model.player.currentTime().seconds - 0.3) < 0.05 }
        XCTAssertTrue(model.isAutomaticQuality)
        XCTAssertEqual(model.selectedQuality, 64)
        XCTAssertEqual(model.qualityDescription, "720P")

        let manual1080 = try XCTUnwrap(model.availableQualities.first(where: { $0.id == 80 }))
        let manual720 = try XCTUnwrap(model.availableQualities.first(where: { $0.id == 64 }))
        model.selectQuality(manual1080)
        try await waitUntil { model.hasPreparedPlayer && !model.hasActivePlaybackPreparationTask }
        XCTAssertFalse(model.isAutomaticQuality)
        XCTAssertTrue(model.isQualitySelected(manual1080))
        XCTAssertFalse(model.isQualitySelected(manual720), "Delivered quality is not the user's manual preference")
        XCTAssertEqual(model.selectedQuality, 64)
        model.selectQuality(manual1080)
        XCTAssertFalse(model.hasActivePlaybackPreparationTask)

        model.selectAutomaticQuality()
        try await waitUntil { model.hasPreparedPlayer && !model.hasActivePlaybackPreparationTask }
        XCTAssertTrue(model.isAutomaticQuality)
        XCTAssertFalse(model.isQualitySelected(manual1080))
        XCTAssertFalse(model.isQualitySelected(manual720))
        XCTAssertEqual(model.selectedQuality, 64)
        XCTAssertEqual(model.player.currentTime().seconds, 0.3, accuracy: 0.05)
        XCTAssertEqual(model.player.rate, 0)
        model.selectAutomaticQuality()
        let requests = await api.requestedQualities
        XCTAssertEqual(requests, [80, 80, 80], "Mode changes reload the default strategy; selecting the same mode does not")
    }

    func testAutomaticAndManualQualitySwitchesKeepPlayingPositionAndSpeed() async throws {
        let movieURL = try makeLocalMovie(frameCount: 180)
        defer { try? FileManager.default.removeItem(at: movieURL) }
        let api = PlaybackQualityFixtureAPI()
        let model = try makeLocalPlaybackModel(movieURL: movieURL, api: api, metadataDuration: 6)
        defer { model.suspend() }
        model.retryPlayback()
        try await waitUntil { model.hasPreparedPlayer }
        model.setPlaybackRate(1.25)
        model.seek(toMilliseconds: 500)
        try await waitUntil { model.player.currentTime().seconds >= 0.49 }
        let historyCalls = await api.historyCalls
        let quality = try XCTUnwrap(model.availableQualities.first(where: { $0.id == 64 }))
        for select in [ { model.selectQuality(quality) }, { model.selectAutomaticQuality() } ] {
            let previousPosition = model.player.currentTime().seconds
            select()
            try await waitUntil { model.hasPreparedPlayer && !model.hasActivePlaybackPreparationTask }
            XCTAssertEqual(model.selectedPageCID, 4201)
            XCTAssertEqual(model.playbackRate, 1.25)
            XCTAssertEqual(model.player.rate, 1.25)
            XCTAssertGreaterThanOrEqual(model.player.currentTime().seconds, previousPosition - 0.05)
            XCTAssertLessThan(model.player.currentTime().seconds, previousPosition + 0.8)
        }
        XCTAssertTrue(model.isAutomaticQuality)
        let historyCallsAfterSwitches = await api.historyCalls
        XCTAssertEqual(historyCallsAfterSwitches, historyCalls)
    }

    private func makeLocalPlaybackModel(movieURL: URL, api: PlaybackQualityFixtureAPI, metadataDuration: Int = 1,
                                        pageCount: Int = 1, preferences: FocusPlaybackPreferences = .defaults,
                                        onPreferences: FocusNativeVideoViewModel.PlaybackPreferenceChange? = nil) throws -> FocusNativeVideoViewModel {
        let cookies = PlaybackFixtureCookies()
        let model = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(cookieProvider: cookies, requestLoader: { request in await api.response(for: request) }),
            actionService: FocusVideoActionService(cookieProvider: cookies, requestLoader: { request in await api.response(for: request) }),
            playbackProgressStore: FocusPlaybackProgressStore(persistence: PlaybackFixturePersistence()),
            nativeDanmakuEnabled: false, nativeSubtitleEnabled: false,
            playbackPreferences: preferences, playbackPreferenceChange: onPreferences,
            playbackItemFactory: { _ in [AVPlayerItem(url: movieURL)] }
        )
        let pages = (1...pageCount).map { "{\"page\":\($0),\"cid\":\(4200 + $0),\"part\":\"fixture\",\"duration\":\(metadataDuration)}" }.joined(separator: ",")
        let detail = try FocusVideoDetailService.decodeDetailResponse(Data("{\"code\":0,\"data\":{\"bvid\":\"BV1xx411c7mD\",\"aid\":42,\"cid\":4201,\"title\":\"Local quality fixture\",\"duration\":\(metadataDuration),\"owner\":{\"mid\":1,\"name\":\"fixture\"},\"pages\":[\(pages)]}}".utf8))
        model.installFixtureDetail(detail)
        return model
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw PlaybackTestError.conditionTimeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testSeparateAudioVideoAssetsComposeAndBecomeReady() async throws {
        let movieURL = try makeLocalMovie()
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("focus-audio-\(UUID().uuidString).caf")
        defer {
            try? FileManager.default.removeItem(at: movieURL)
            try? FileManager.default.removeItem(at: audioURL)
        }
        do {
            let audioFile = try AVAudioFile(forWriting: audioURL, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: 44_100))
            buffer.frameLength = 44_100
            let samples = try XCTUnwrap(buffer.floatChannelData)
            samples[0].update(repeating: 0, count: 44_100)
            try audioFile.write(from: buffer)
        }
        let items = try await FocusNativePlaybackFactory.makeItems(for: FocusVideoPlaybackSource(
            stream: .dash(videoURL: movieURL, audioURL: audioURL), headers: [:], qualityDescription: "fixture"
        ))
        let item = try XCTUnwrap(items.first)
        let tracks = try await item.asset.load(.tracks)
        XCTAssertEqual(tracks.filter { $0.mediaType == .video }.count, 1)
        XCTAssertEqual(tracks.filter { $0.mediaType == .audio }.count, 1)
        let player = AVQueuePlayer(items: items)
        defer { player.removeAllItems() }
        try await FocusNativeVideoViewModel.waitUntilReadyToPlay(item, timeout: .seconds(8))
        XCTAssertEqual(item.status, .readyToPlay)
    }

    func testPausedQueuePlayerWithoutPlayerLayerBecomesReadyAndCanSeek() async throws {
        let movieURL = try makeLocalMovie()
        defer { try? FileManager.default.removeItem(at: movieURL) }

        let player = AVQueuePlayer()
        let item = AVPlayerItem(url: movieURL)
        player.insert(item, after: nil)
        player.pause()

        try await FocusNativeVideoViewModel.waitUntilReadyToPlay(item, timeout: .seconds(8))
        // Re-enter after readiness too: no future state notification is needed.
        try await FocusNativeVideoViewModel.waitUntilReadyToPlay(item, timeout: .milliseconds(100))

        XCTAssertEqual(item.status, .readyToPlay)
        XCTAssertEqual(player.rate, 0, "Readiness should not require starting playback")

        let seekTarget = CMTime(value: 300, timescale: 1_000)
        let seekCompleted = await withCheckedContinuation { continuation in
            player.seek(to: seekTarget, toleranceBefore: .zero, toleranceAfter: .zero) {
                continuation.resume(returning: $0)
            }
        }

        XCTAssertTrue(seekCompleted)
        XCTAssertEqual(CMTimeGetSeconds(player.currentTime()), 0.3, accuracy: 0.05)
        player.removeAllItems()
    }

    func testReadinessTimeoutAndCancellationDoNotWaitForever() async throws {
        let item = AVPlayerItem(asset: AVMutableComposition())
        do {
            try await FocusNativeVideoViewModel.waitUntilReadyToPlay(item, timeout: .milliseconds(100))
            XCTFail("An unattached item must time out")
        } catch FocusNativeVideoViewModel.PlaybackPreparationError.readinessTimedOut {
            XCTAssertEqual(item.status, .unknown)
        }
        let task = Task { @MainActor in
            try await FocusNativeVideoViewModel.waitUntilReadyToPlay(item)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
    }

    private func makeLocalMovie(frameCount: Int = 30) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-playback-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64,
            ]
        )
        input.expectsMediaDataInRealTime = false
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

        guard writer.canAdd(input) else { throw PlaybackTestError.cannotCreateWriterInput }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? PlaybackTestError.cannotStartWriter
        }
        writer.startSession(atSourceTime: .zero)

        let writingDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else {
                    throw writer.error ?? PlaybackTestError.writerDidNotFinish
                }
                guard ContinuousClock.now < writingDeadline else {
                    writer.cancelWriting()
                    throw PlaybackTestError.writerDidNotFinish
                }
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw PlaybackTestError.missingPixelBufferPool
            }
            var optionalBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
            guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
                throw PlaybackTestError.cannotAllocatePixelBuffer(status)
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 0, CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: Int64(frame), timescale: 30)
            ) else {
                throw writer.error ?? PlaybackTestError.cannotAppendFrame
            }
        }

        input.markAsFinished()
        let finished = expectation(description: "AVAssetWriter finishes local fixture")
        writer.finishWriting { finished.fulfill() }
        wait(for: [finished], timeout: 8)
        guard writer.status == .completed else {
            throw writer.error ?? PlaybackTestError.writerDidNotFinish
        }
        return url
    }
}

private struct PlaybackFixtureCookies: CookieSnapshotProvider {
    func loadCookies() async -> [HTTPCookie] { [] }
}

private struct CommentMutationFixtureCookies: CookieSnapshotProvider {
    let cookies: [HTTPCookie]
    func loadCookies() async -> [HTTPCookie] { cookies }
}

private actor CommentMutationFixtureAPI {
    private var rejectsMutations = false
    private(set) var mutationPaths: [String] = []
    func setRejectMutations(_ rejects: Bool) { rejectsMutations = rejects }

    func response(for request: URLRequest) -> (Data, URLResponse) {
        let path = request.url!.path
        let payload: String
        if request.httpMethod == "POST" {
            mutationPaths.append(path)
            if rejectsMutations {
                payload = #"{"code":-403,"message":"fixture rejected"}"#
            } else if path == "/x/v2/reply/add" {
                payload = #"{"code":0,"data":{"reply":{"rpid":90099,"mid":1001,"ctime":1700000000,"member":{"mid":"1001","uname":"测试用户","avatar":""},"content":{"message":"保留草稿"}}}}"#
            } else {
                payload = #"{"code":0,"data":{}}"#
            }
        } else {
            payload = #"{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png","sub_url":"https://i0.hdslb.com/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png"}}}"#
        }
        return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor CommentMutationScopeGate {
    private let scope: FocusPlaybackAccountScope
    private var continuation: CheckedContinuation<FocusPlaybackAccountScope, Never>?
    var isWaiting: Bool { continuation != nil }
    init(scope: FocusPlaybackAccountScope) { self.scope = scope }
    func resolve() async -> FocusPlaybackAccountScope {
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume(returning: scope)
        continuation = nil
    }
}

private actor PlaybackFixturePersistence: FocusPlaybackStatePersistence {
    private var data: Data?
    func loadPlaybackState() -> Data? { data }
    func savePlaybackState(_ data: Data) { self.data = data }
}

private actor PlaybackQualityFixtureAPI {
    private(set) var historyCalls = 0
    private(set) var requestedQualities: [Int] = []
    private let deliveredQuality: Int?

    init(deliveredQuality: Int? = nil) {
        self.deliveredQuality = deliveredQuality
    }

    func response(for request: URLRequest) -> (Data, URLResponse) {
        let payload: String
        let path = request.url!.path
        if path.hasSuffix("playurl") {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let quality = query.first(where: { $0.name == "qn" }).flatMap { $0.value.flatMap(Int.init) } ?? 80
            requestedQualities.append(quality)
            payload = "{\"code\":0,\"data\":{\"quality\":\(deliveredQuality ?? quality),\"accept_quality\":[80,64],\"accept_description\":[\"1080P\",\"720P\"],\"durl\":[{\"url\":\"https://cdn.example/local.mp4\"}]}}"
        } else if path == "/x/web-interface/nav" {
            payload = #"{"code":0,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png","sub_url":"https://i0.hdslb.com/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png"}}}"#
        } else {
            historyCalls += 1
            payload = #"{"code":0,"data":{"last_play_cid":0,"last_play_time":0}}"#
        }
        return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private enum PlaybackTestError: Error {
    case conditionTimeout
    case cannotCreateWriterInput
    case cannotStartWriter
    case missingPixelBufferPool
    case cannotAllocatePixelBuffer(CVReturn)
    case cannotAppendFrame
    case writerDidNotFinish
}
