#if canImport(UIKit)
import AVFoundation
import AVKit
import Combine
import FocusCore
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class FocusNativeVideoViewModel: ObservableObject {
    typealias LandscapeRequest = @MainActor () -> Void
    typealias PortraitFullscreenRequest = @MainActor () -> Void
    typealias PortraitTransition = @MainActor () async -> Void
    typealias DanmakuPreferenceChange = @MainActor (Bool) -> Void

    enum State: Equatable {
        case idle
        case loading
        case loaded(FocusVideoDetail)
        case failed(String)
    }

    enum Action: Hashable {
        case like
        case coin
        case favorite
    }

    enum DanmakuLoadState: Equatable {
        case idle
        case loading
        case ready
        case closed
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var comments: [FocusVideoComment] = []
    @Published private(set) var interactionState = FocusVideoInteractionState()
    @Published private(set) var isLoadingInteractions = false
    @Published private(set) var actionsInFlight: Set<Action> = []
    @Published private(set) var selectedPageCID: Int64?
    @Published private(set) var isLoadingPlayback = false
    @Published private(set) var hasPreparedPlayer = false
    @Published private(set) var playerErrorMessage: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackRate: Float = 1
    @Published private(set) var playbackPositionMilliseconds: Int64 = 0
    @Published private(set) var danmakus: [FocusVideoDanmaku] = []
    @Published private(set) var danmakuLoadState: DanmakuLoadState = .idle
    @Published private(set) var isDanmakuEnabled: Bool
    @Published var isFullscreen = false
    @Published var actionErrorMessage: String?

    let player: AVQueuePlayer

    private let detailService: FocusVideoDetailService
    private let actionService: FocusVideoActionService
    private var sourceURL: URL?
    private var requestedPageNumber: Int?
    private var requestedPageCID: Int64?
    private var loadTask: Task<Void, Never>?
    private var commentsTask: Task<Void, Never>?
    private var interactionTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var actionTasks: [Action: Task<Void, Never>] = [:]
    private var watchHistoryReportTask: Task<Void, Never>?
    private var lastQueuedWatchHistoryReport: WatchHistoryReport?
    private var orientationDebounceTask: Task<Void, Never>?
    private var portraitExitTask: Task<Void, Never>?
    private var timeControlObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var periodicTimeObserver: Any?
    private var danmakuViewTask: Task<Void, Never>?
    private var danmakuSegmentTasks: [Int: Task<Void, Never>] = [:]
    private var danmakuSegmentCache: [Int: [FocusVideoDanmaku]] = [:]
    private var danmakuView: FocusVideoDanmakuView?
    private var danmakuContext: DanmakuContext?
    private var danmakuRevision = 0
    private var shouldResumeAfterActivation = false
    private var shouldResumeAfterAudioInterruption = false
    private var isReplacingPlayerItem = false
    private var isPlaybackSessionActive = false
    nonisolated(unsafe) private var audioInterruptionObserver: NSObjectProtocol?
    nonisolated(unsafe) private var audioRouteChangeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var mediaServicesResetObserver: NSObjectProtocol?
    nonisolated(unsafe) private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var nowPlayingArtworkTask: Task<Void, Never>?
    private var nowPlayingRevision = 0
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var lastNowPlayingElapsedUpdate: Int64 = -1
    private var lastHandledDeviceOrientation: UIDeviceOrientation = .unknown
    private var fullscreenTransitionRevision = 0
    private let landscapeRequest: LandscapeRequest
    private let portraitFullscreenRequest: PortraitFullscreenRequest
    private let portraitTransition: PortraitTransition
    private let danmakuPreferenceChange: DanmakuPreferenceChange
    private(set) var isCompletingPortraitExit = false

    var navigationTitle: String {
        if case let .loaded(detail) = state {
            return detail.title
        }
        return "视频"
    }

    var currentURL: URL? {
        sourceURL
    }

    var detail: FocusVideoDetail? {
        guard case let .loaded(detail) = state else {
            return nil
        }
        return detail
    }

    var activePage: FocusVideoPage? {
        guard let detail else {
            return nil
        }
        return detail.pages.first(where: { $0.cid == selectedPageCID })
            ?? detail.pages.first(where: { $0.cid == detail.cid })
            ?? detail.pages.first
    }

    var showsPlaybackControls: Bool {
        detail != nil
    }

    var hasActiveLoadTask: Bool {
        loadTask != nil || commentsTask != nil || interactionTask != nil || playbackTask != nil
    }

    init(
        detailService: FocusVideoDetailService,
        actionService: FocusVideoActionService,
        nativeDanmakuEnabled: Bool = true,
        danmakuPreferenceChange: DanmakuPreferenceChange? = nil,
        landscapeRequest: LandscapeRequest? = nil,
        portraitFullscreenRequest: PortraitFullscreenRequest? = nil,
        portraitTransition: PortraitTransition? = nil
    ) {
        self.detailService = detailService
        self.actionService = actionService
        self.isDanmakuEnabled = nativeDanmakuEnabled
        self.danmakuPreferenceChange = danmakuPreferenceChange ?? { _ in }
        self.landscapeRequest = landscapeRequest ?? {
            FocusNativeVideoOrientation.update(to: .landscape)
        }
        self.portraitFullscreenRequest = portraitFullscreenRequest ?? {
            FocusNativeVideoOrientation.update(to: .portrait)
        }
        self.portraitTransition = portraitTransition ?? {
            await FocusNativeVideoOrientation.rotateToPortraitAndWait()
        }
        let player = AVQueuePlayer()
        player.actionAtItemEnd = .advance
        player.automaticallyWaitsToMinimizeStalling = true
        player.audiovisualBackgroundPlaybackPolicy =
            FocusNativePlaybackLifecyclePolicy.audiovisualBackgroundPlaybackPolicy
        self.player = player

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.isPlaying = player.timeControlStatus == .playing
                self.updateNowPlayingInfo()
                if player.timeControlStatus != .playing, !self.isReplacingPlayerItem {
                    self.queueWatchHistoryReport(force: true)
                }
            }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            guard player.rate > 0 else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.playbackRate = player.rate
                self.updateNowPlayingInfo()
            }
        }
        playerStatusObservation = player.observe(\.status, options: [.new]) { [weak self] player, _ in
            guard player.status == .failed else {
                return
            }
            let message = player.error?.localizedDescription ?? "播放过程中断，请重试。"
            Task { @MainActor [weak self] in
                self?.playerErrorMessage = message
                self?.hasPreparedPlayer = false
            }
        }
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                let milliseconds = Self.milliseconds(from: time)
                self?.playbackPositionMilliseconds = milliseconds
                self?.updateDanmakuPosition(milliseconds)
                self?.updateNowPlayingInfoIfNeeded(milliseconds: milliseconds)
                if self?.player.timeControlStatus == .playing {
                    self?.queueWatchHistoryReport(force: false)
                }
            }
        }
    }

    deinit {
        loadTask?.cancel()
        commentsTask?.cancel()
        interactionTask?.cancel()
        playbackTask?.cancel()
        actionTasks.values.forEach { $0.cancel() }
        orientationDebounceTask?.cancel()
        portraitExitTask?.cancel()
        nowPlayingArtworkTask?.cancel()
        timeControlObservation?.invalidate()
        rateObservation?.invalidate()
        playerStatusObservation?.invalidate()
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
        }
        danmakuViewTask?.cancel()
        danmakuSegmentTasks.values.forEach { $0.cancel() }
        if let audioInterruptionObserver {
            NotificationCenter.default.removeObserver(audioInterruptionObserver)
        }
        if let audioRouteChangeObserver {
            NotificationCenter.default.removeObserver(audioRouteChangeObserver)
        }
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
        }
        for entry in remoteCommandTargets {
            entry.command.removeTarget(entry.target)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        player.pause()
        player.removeAllItems()
    }

    func activate(url: URL) {
        open(url)
        activatePlaybackSession()
        loadIfNeeded()

        if let detail {
            configureDanmaku(
                for: detail,
                playbackPositionMilliseconds: currentPlaybackMilliseconds
            )
        }

        if hasPreparedPlayer, shouldResumeAfterActivation {
            player.playImmediately(atRate: playbackRate)
        } else if detail != nil, player.currentItem == nil, playbackTask == nil {
            preparePlayback()
        }
        shouldResumeAfterActivation = false
    }

    func open(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard sourceURL != canonicalURL else {
            return
        }

        queueWatchHistoryReport(force: true)
        cancelTasks()
        sourceURL = canonicalURL
        requestedPageNumber = FocusVideoDetailService.requestedPageNumber(from: canonicalURL)
        requestedPageCID = FocusVideoDetailService.requestedPageCID(from: canonicalURL)
        state = .idle
        comments = []
        interactionState = FocusVideoInteractionState()
        isLoadingInteractions = false
        actionsInFlight = []
        selectedPageCID = nil
        resetDanmakuSession()
        playerErrorMessage = nil
        hasPreparedPlayer = false
        isLoadingPlayback = false
        resetNowPlayingMetadata()
        player.pause()
        player.removeAllItems()
    }

    func loadIfNeeded() {
        guard case .idle = state else {
            return
        }
        reload()
    }

    func reload() {
        guard let sourceURL else {
            state = .failed("缺少视频地址")
            return
        }

        queueWatchHistoryReport(force: true)
        cancelTasks()
        state = .loading
        comments = []
        interactionState = FocusVideoInteractionState()
        isLoadingInteractions = false
        selectedPageCID = nil
        resetDanmakuSession()
        playerErrorMessage = nil
        hasPreparedPlayer = false
        isLoadingPlayback = false
        player.pause()
        player.removeAllItems()

        loadTask = Task { [weak self, detailService] in
            defer { self?.loadTask = nil }
            guard let self else {
                return
            }
            do {
                let detail = try await detailService.fetchDetail(for: sourceURL)
                try Task.checkCancellation()
                state = .loaded(detail)
                let requestedPage = requestedPageNumber.flatMap { number in
                    detail.pages.first(where: { $0.pageNumber == number })
                }
                selectedPageCID = requestedPage?.cid
                    ?? requestedPageCID.flatMap { requestedCID in
                        detail.pages.first(where: { $0.cid == requestedCID })?.cid
                    }
                    ?? detail.pages.first(where: { $0.cid == detail.cid })?.cid
                    ?? detail.pages.first?.cid
                    ?? detail.cid
                configureNowPlayingMetadata(for: detail)
                configureDanmaku(for: detail, playbackPositionMilliseconds: 0)
                preparePlayback()
                loadComments(for: detail)
                loadInteractions(for: detail)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func suspend() {
        queueWatchHistoryReport(force: true)
        shouldResumeAfterActivation = player.timeControlStatus == .playing
        shouldResumeAfterAudioInterruption = false
        loadTask?.cancel()
        loadTask = nil
        commentsTask?.cancel()
        commentsTask = nil
        interactionTask?.cancel()
        interactionTask = nil
        playbackTask?.cancel()
        playbackTask = nil
        actionTasks.values.forEach { $0.cancel() }
        actionTasks.removeAll()
        cancelFullscreenTransitions()
        actionsInFlight = []
        cancelDanmakuRequests()
        isLoadingInteractions = false
        isLoadingPlayback = false
        if isFullscreen {
            FocusNativeVideoOrientation.update(to: .portrait)
        }
        isFullscreen = false
        player.pause()
        tearDownPlaybackSession(clearNowPlaying: true)
        if case .loading = state {
            state = .idle
        }
    }

    func handleAppDidEnterBackground() {
        queueWatchHistoryReport(force: true)
        if FocusNativePlaybackLifecyclePolicy.shouldPauseForApplicationBackground(
            isPlaying: player.timeControlStatus == .playing
        ) {
            player.pause()
        }
        updateNowPlayingInfo()
    }

    func handleAppDidBecomeActive() {
        updateNowPlayingInfo()
    }

    func selectPage(_ page: FocusVideoPage) {
        guard selectedPageCID != page.cid else {
            return
        }
        queueWatchHistoryReport(force: true)
        selectedPageCID = page.cid
        updateNowPlayingInfo()
        if let detail {
            configureDanmaku(for: detail, playbackPositionMilliseconds: 0)
        }
        preparePlayback()
    }

    func retryPlayback() {
        preparePlayback()
    }

    func togglePlayback() {
        guard player.currentItem != nil else {
            preparePlayback()
            return
        }

        if player.timeControlStatus == .playing {
            queueWatchHistoryReport(force: true)
            player.pause()
            return
        }

        if let item = player.currentItem,
           item.duration.isNumeric,
           CMTimeCompare(item.currentTime(), item.duration) >= 0
        {
            player.seek(to: .zero)
        }
        configureAudioSession()
        player.playImmediately(atRate: playbackRate)
    }

    func cyclePlaybackRate() {
        let rates: [Float] = [1, 1.25, 1.5, 2]
        let currentIndex = rates.firstIndex(where: { abs($0 - playbackRate) < 0.01 }) ?? 0
        let nextRate = rates[(currentIndex + 1) % rates.count]
        playbackRate = nextRate
        player.defaultRate = nextRate
        if player.timeControlStatus == .playing {
            player.rate = nextRate
        }
    }

    func toggleDanmaku() {
        setDanmakuEnabled(!isDanmakuEnabled, persist: true)
    }

    func applyDanmakuPreference(_ enabled: Bool) {
        setDanmakuEnabled(enabled, persist: false)
    }

    func retryDanmaku() {
        danmakuViewTask?.cancel()
        danmakuSegmentTasks.values.forEach { $0.cancel() }
        danmakuSegmentTasks.removeAll()
        danmakuLoadState = .loading
        if danmakuView == nil {
            loadDanmakuView(playbackPositionMilliseconds: currentPlaybackMilliseconds)
        } else {
            updateDanmakuPosition(currentPlaybackMilliseconds)
        }
    }

    func requestFullscreen() {
        guard let detail else {
            return
        }
        cancelPortraitExitTransition()
        setFullscreenPresented(true)
        switch FocusNativeVideoFullscreenPolicy.orientation(for: detail) {
        case .portrait:
            portraitFullscreenRequest()
        default:
            landscapeRequest()
        }
    }

    func exitFullscreen() {
        guard isFullscreen, !isCompletingPortraitExit else {
            return
        }

        fullscreenTransitionRevision &+= 1
        let revision = fullscreenTransitionRevision
        let transition = portraitTransition
        isCompletingPortraitExit = true
        portraitExitTask = Task { @MainActor [weak self] in
            await transition()
            guard let self, self.fullscreenTransitionRevision == revision else {
                return
            }
            defer {
                self.portraitExitTask = nil
                self.isCompletingPortraitExit = false
            }
            guard !Task.isCancelled else {
                return
            }
            self.setFullscreenPresented(false)
        }
    }

    func handleDeviceOrientationChange(_ orientation: UIDeviceOrientation) {
        guard UIDevice.current.userInterfaceIdiom == .phone, detail != nil else {
            return
        }
        guard orientation.isLandscape || orientation == .portrait else {
            return
        }
        guard orientation != lastHandledDeviceOrientation else {
            return
        }

        lastHandledDeviceOrientation = orientation
        orientationDebounceTask?.cancel()
        orientationDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self, !Task.isCancelled else {
                return
            }
            switch orientation {
            case .landscapeLeft, .landscapeRight:
                if self.prefersLandscapeFullscreen {
                    self.requestFullscreen()
                }
            case .portrait:
                if self.prefersLandscapeFullscreen {
                    self.exitFullscreen()
                }
            default:
                break
            }
        }
    }

    private var prefersLandscapeFullscreen: Bool {
        guard let detail else {
            return false
        }
        return FocusNativeVideoFullscreenPolicy.orientation(for: detail) == .landscape
    }

    func toggleLike() {
        guard
            let detail,
            !actionsInFlight.contains(.like)
        else {
            return
        }
        let shouldLike = !interactionState.liked
        performAction(.like) { [weak self, actionService] in
            try await actionService.setLiked(aid: detail.aid, liked: shouldLike)
            guard let self else {
                return
            }
            interactionState = FocusVideoInteractionState(
                liked: shouldLike,
                coined: interactionState.coined,
                favorited: interactionState.favorited,
                favoriteFolderID: interactionState.favoriteFolderID
            )
            updateStatistics { statistics in
                statistics.replacing(
                    likes: max(statistics.likes + (shouldLike ? 1 : -1), 0)
                )
            }
        }
    }

    func addCoin() {
        guard
            let detail,
            !interactionState.coined,
            !actionsInFlight.contains(.coin)
        else {
            return
        }
        performAction(.coin) { [weak self, actionService] in
            try await actionService.addCoin(aid: detail.aid)
            guard let self else {
                return
            }
            interactionState = FocusVideoInteractionState(
                liked: interactionState.liked,
                coined: true,
                favorited: interactionState.favorited,
                favoriteFolderID: interactionState.favoriteFolderID
            )
            updateStatistics { statistics in
                statistics.replacing(coins: statistics.coins + 1)
            }
        }
    }

    func toggleFavorite() {
        guard
            let detail,
            !actionsInFlight.contains(.favorite)
        else {
            return
        }
        let shouldFavorite = !interactionState.favorited
        let currentFolderID = interactionState.favoriteFolderID
        performAction(.favorite) { [weak self, actionService] in
            let folderID = try await actionService.setFavorited(
                aid: detail.aid,
                favorited: shouldFavorite,
                folderID: currentFolderID
            )
            guard let self else {
                return
            }
            interactionState = FocusVideoInteractionState(
                liked: interactionState.liked,
                coined: interactionState.coined,
                favorited: shouldFavorite,
                favoriteFolderID: folderID
            )
            updateStatistics { statistics in
                statistics.replacing(
                    favorites: max(statistics.favorites + (shouldFavorite ? 1 : -1), 0)
                )
            }
        }
    }

    private func preparePlayback() {
        guard let detail else {
            return
        }
        let cid = selectedPageCID
            ?? detail.pages.first(where: { $0.cid == detail.cid })?.cid
            ?? detail.pages.first?.cid
            ?? detail.cid

        playbackTask?.cancel()
        isReplacingPlayerItem = true
        player.pause()
        player.removeAllItems()
        isLoadingPlayback = true
        hasPreparedPlayer = false
        playerErrorMessage = nil

        playbackTask = Task { [weak self, detailService] in
            defer { self?.playbackTask = nil }
            guard let self else {
                return
            }
            do {
                let source = try await detailService.fetchPlayback(bvid: detail.bvid, cid: cid)
                try Task.checkCancellation()
                let items = try await FocusNativePlaybackFactory.makeItems(for: source)
                try Task.checkCancellation()
                guard !items.isEmpty else {
                    throw FocusVideoDetailService.ServiceError.noStream
                }

                player.removeAllItems()
                var previousItem: AVPlayerItem?
                for item in items where player.canInsert(item, after: previousItem) {
                    player.insert(item, after: previousItem)
                    previousItem = item
                }
                isLoadingPlayback = false
                hasPreparedPlayer = player.currentItem != nil
                configureAudioSession()
                player.defaultRate = playbackRate
                player.playImmediately(atRate: playbackRate)
                isReplacingPlayerItem = false
                updateNowPlayingInfo()
                queueWatchHistoryReport(force: true)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                isLoadingPlayback = false
                hasPreparedPlayer = false
                isReplacingPlayerItem = false
                playerErrorMessage = error.localizedDescription
            }
        }
    }

    private func queueWatchHistoryReport(force: Bool) {
        guard let detail else {
            return
        }
        let cid = selectedPageCID
            ?? detail.pages.first(where: { $0.cid == detail.cid })?.cid
            ?? detail.pages.first?.cid
            ?? detail.cid
        let report = WatchHistoryReport(
            aid: detail.aid,
            cid: cid,
            progressSeconds: max(currentPlaybackMilliseconds / 1_000, 0)
        )

        if let previous = lastQueuedWatchHistoryReport,
           previous.aid == report.aid,
           previous.cid == report.cid
        {
            guard previous.progressSeconds != report.progressSeconds else {
                return
            }
            if !force, abs(previous.progressSeconds - report.progressSeconds) < 15 {
                return
            }
        }

        lastQueuedWatchHistoryReport = report
        let precedingTask = watchHistoryReportTask
        watchHistoryReportTask = Task { [actionService] in
            _ = await precedingTask?.result
            guard !Task.isCancelled else {
                return
            }
            try? await actionService.reportWatchHistory(
                aid: report.aid,
                cid: report.cid,
                progressSeconds: report.progressSeconds
            )
        }
    }

    private var currentPlaybackMilliseconds: Int64 {
        Self.milliseconds(from: player.currentTime())
    }

    var danmakuPlaybackPositionMilliseconds: Int64 {
        currentPlaybackMilliseconds
    }

    private func setDanmakuEnabled(_ enabled: Bool, persist: Bool) {
        let changed = isDanmakuEnabled != enabled
        isDanmakuEnabled = enabled
        if persist, changed {
            danmakuPreferenceChange(enabled)
        }
        if enabled {
            if let detail {
                configureDanmaku(
                    for: detail,
                    playbackPositionMilliseconds: currentPlaybackMilliseconds
                )
            }
        } else {
            danmakuRevision &+= 1
            cancelDanmakuRequests()
        }
    }

    private func configureDanmaku(
        for detail: FocusVideoDetail,
        playbackPositionMilliseconds: Int64
    ) {
        let page = detail.pages.first(where: { $0.cid == selectedPageCID }) ?? detail.pages.first
        let cid = selectedPageCID ?? page?.cid ?? detail.cid
        let duration = max(page?.duration ?? detail.duration, 0) * 1_000
        let context = DanmakuContext(aid: detail.aid, cid: cid, durationMilliseconds: duration)
        if danmakuContext != context {
            resetDanmakuSession()
            danmakuContext = context
        }
        guard isDanmakuEnabled else {
            return
        }
        if danmakuView == nil, danmakuViewTask == nil {
            loadDanmakuView(playbackPositionMilliseconds: playbackPositionMilliseconds)
        } else {
            updateDanmakuPosition(playbackPositionMilliseconds)
        }
    }

    private func loadDanmakuView(playbackPositionMilliseconds: Int64) {
        guard let context = danmakuContext else {
            return
        }
        let revision = danmakuRevision
        danmakuLoadState = .loading
        danmakuViewTask = Task { [weak self, detailService] in
            let view: FocusVideoDanmakuView
            do {
                view = try await detailService.fetchDanmakuView(aid: context.aid, cid: context.cid)
            } catch {
                let total = context.durationMilliseconds > 0
                    ? Int((context.durationMilliseconds + Self.defaultDanmakuSegmentMilliseconds - 1)
                        / Self.defaultDanmakuSegmentMilliseconds)
                    : 0
                view = FocusVideoDanmakuView(
                    state: 0,
                    segmentDurationMilliseconds: Self.defaultDanmakuSegmentMilliseconds,
                    totalSegments: total,
                    count: 0
                )
            }
            guard
                let self,
                !Task.isCancelled,
                revision == danmakuRevision,
                context == danmakuContext
            else {
                return
            }
            danmakuViewTask = nil
            danmakuView = view
            if view.isClosed {
                danmakuLoadState = .closed
                return
            }
            updateDanmakuPosition(playbackPositionMilliseconds)
        }
    }

    private func updateDanmakuPosition(_ playbackPositionMilliseconds: Int64) {
        guard isDanmakuEnabled, let view = danmakuView, !view.isClosed else {
            return
        }
        FocusDanmakuSegmentScheduler.segmentIndexes(
            playbackPositionMilliseconds: playbackPositionMilliseconds,
            segmentDurationMilliseconds: view.segmentDurationMilliseconds,
            totalSegments: view.totalSegments
        ).forEach(ensureDanmakuSegment)
    }

    private func ensureDanmakuSegment(_ segmentIndex: Int) {
        guard
            segmentIndex > 0,
            let context = danmakuContext,
            let view = danmakuView,
            view.totalSegments <= 0 || segmentIndex <= view.totalSegments,
            danmakuSegmentCache[segmentIndex] == nil,
            danmakuSegmentTasks[segmentIndex] == nil
        else {
            return
        }

        let revision = danmakuRevision
        danmakuSegmentTasks[segmentIndex] = Task { [weak self, detailService] in
            defer {
                if self?.danmakuRevision == revision {
                    self?.danmakuSegmentTasks[segmentIndex] = nil
                }
            }
            do {
                let segment = try await detailService.fetchDanmakuSegment(
                    aid: context.aid,
                    cid: context.cid,
                    segmentIndex: segmentIndex
                )
                guard
                    let self,
                    !Task.isCancelled,
                    revision == danmakuRevision,
                    context == danmakuContext
                else {
                    return
                }
                if segment.isClosed {
                    markDanmakuClosed()
                    return
                }
                danmakuSegmentCache[segmentIndex] = segment.danmakus
                danmakus = danmakuSegmentCache.keys.sorted().flatMap {
                    danmakuSegmentCache[$0] ?? []
                }.sorted {
                    if $0.progressMilliseconds != $1.progressMilliseconds {
                        return $0.progressMilliseconds < $1.progressMilliseconds
                    }
                    return $0.weight > $1.weight
                }
                danmakuLoadState = .ready
            } catch {
                guard
                    let self,
                    !Task.isCancelled,
                    revision == danmakuRevision,
                    context == danmakuContext
                else {
                    return
                }
                if danmakuSegmentCache.isEmpty {
                    danmakuLoadState = .failed("弹幕加载失败")
                }
            }
        }
    }

    private func cancelDanmakuRequests() {
        danmakuViewTask?.cancel()
        danmakuViewTask = nil
        danmakuSegmentTasks.values.forEach { $0.cancel() }
        danmakuSegmentTasks.removeAll()
    }

    private func resetDanmakuSession() {
        danmakuRevision &+= 1
        cancelDanmakuRequests()
        danmakuSegmentCache.removeAll()
        danmakuView = nil
        danmakuContext = nil
        danmakus = []
        danmakuLoadState = .idle
    }

    private func markDanmakuClosed() {
        if let view = danmakuView {
            danmakuView = FocusVideoDanmakuView(
                state: 1,
                segmentDurationMilliseconds: view.segmentDurationMilliseconds,
                totalSegments: view.totalSegments,
                count: view.count
            )
        }
        danmakuRevision &+= 1
        cancelDanmakuRequests()
        danmakuSegmentCache.removeAll()
        danmakus = []
        danmakuLoadState = .closed
    }

    private nonisolated static func milliseconds(from time: CMTime) -> Int64 {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds >= 0 else {
            return 0
        }
        return Int64(seconds * 1_000)
    }

    private func loadComments(for detail: FocusVideoDetail) {
        commentsTask?.cancel()
        commentsTask = Task { [weak self, detailService] in
            defer { self?.commentsTask = nil }
            do {
                let comments = try await detailService.fetchComments(aid: detail.aid)
                guard !Task.isCancelled else {
                    return
                }
                self?.comments = comments
            } catch {
                return
            }
        }
    }

    private func loadInteractions(for detail: FocusVideoDetail) {
        interactionTask?.cancel()
        isLoadingInteractions = true
        interactionTask = Task { [weak self, actionService] in
            defer {
                self?.interactionTask = nil
                self?.isLoadingInteractions = false
            }
            do {
                let state = try await actionService.fetchInteractionState(aid: detail.aid)
                guard !Task.isCancelled else {
                    return
                }
                self?.interactionState = state
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func performAction(
        _ action: Action,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        actionTasks[action]?.cancel()
        actionsInFlight.insert(action)
        actionErrorMessage = nil
        actionTasks[action] = Task { [weak self] in
            defer {
                self?.actionsInFlight.remove(action)
                self?.actionTasks[action] = nil
            }
            do {
                try await operation()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func updateStatistics(
        _ transform: (FocusVideoStatistics) -> FocusVideoStatistics
    ) {
        guard case let .loaded(detail) = state else {
            return
        }
        state = .loaded(detail.replacing(statistics: transform(detail.statistics)))
    }

    private func activatePlaybackSession() {
        guard !isPlaybackSessionActive else {
            return
        }
        isPlaybackSessionActive = true
        installAudioSessionObservers()
        installRemoteCommands()
        updateNowPlayingInfo()
    }

    private func tearDownPlaybackSession(clearNowPlaying: Bool) {
        if let audioInterruptionObserver {
            NotificationCenter.default.removeObserver(audioInterruptionObserver)
            self.audioInterruptionObserver = nil
        }
        if let audioRouteChangeObserver {
            NotificationCenter.default.removeObserver(audioRouteChangeObserver)
            self.audioRouteChangeObserver = nil
        }
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
            self.mediaServicesResetObserver = nil
        }
        removeRemoteCommands()
        isPlaybackSessionActive = false
        shouldResumeAfterAudioInterruption = false
        if clearNowPlaying {
            resetNowPlayingMetadata()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func installAudioSessionObservers() {
        guard audioInterruptionObserver == nil else {
            return
        }
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        audioInterruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                self?.handleAudioInterruption(rawType: rawType, rawOptions: rawOptions)
            }
        }
        audioRouteChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleAudioRouteChange(rawReason: rawReason)
            }
        }
        mediaServicesResetObserver = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMediaServicesReset()
            }
        }
    }

    private func handleAudioInterruption(rawType: UInt?, rawOptions: UInt) {
        guard
            isPlaybackSessionActive,
            let rawType,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch type {
        case .began:
            shouldResumeAfterAudioInterruption = player.timeControlStatus == .playing
            queueWatchHistoryReport(force: true)
            player.pause()
            updateNowPlayingInfo()

        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            let shouldResume = FocusNativePlaybackLifecyclePolicy.shouldResumeAfterInterruption(
                wasPlaying: shouldResumeAfterAudioInterruption,
                systemAllowsResume: options.contains(.shouldResume)
            )
            shouldResumeAfterAudioInterruption = false
            guard shouldResume, player.currentItem != nil else {
                updateNowPlayingInfo()
                return
            }
            configureAudioSession()
            player.playImmediately(atRate: playbackRate)
            updateNowPlayingInfo()

        @unknown default:
            shouldResumeAfterAudioInterruption = false
        }
    }

    private func handleAudioRouteChange(rawReason: UInt?) {
        guard
            isPlaybackSessionActive,
            let rawReason,
            AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable
        else {
            return
        }
        guard player.timeControlStatus == .playing else {
            return
        }
        queueWatchHistoryReport(force: true)
        player.pause()
        updateNowPlayingInfo()
    }

    private func handleMediaServicesReset() {
        guard isPlaybackSessionActive, player.currentItem != nil else {
            return
        }
        let shouldResume = player.timeControlStatus == .playing || isPlaying
        configureAudioSession()
        if shouldResume {
            player.playImmediately(atRate: playbackRate)
        }
        updateNowPlayingInfo()
    }

    private func installRemoteCommands() {
        removeRemoteCommands()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false

        let playTarget = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playFromRemoteCommand()
            }
            return .success
        }
        remoteCommandTargets.append((center.playCommand, playTarget))

        let pauseTarget = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pauseFromRemoteCommand()
            }
            return .success
        }
        remoteCommandTargets.append((center.pauseCommand, pauseTarget))

        let toggleTarget = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.togglePlayback()
            }
            return .success
        }
        remoteCommandTargets.append((center.togglePlayPauseCommand, toggleTarget))

        let positionTarget = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            Task { @MainActor [weak self] in
                self?.seekFromRemoteCommand(to: position)
            }
            return .success
        }
        remoteCommandTargets.append((center.changePlaybackPositionCommand, positionTarget))
    }

    private func removeRemoteCommands() {
        for entry in remoteCommandTargets {
            entry.command.removeTarget(entry.target)
        }
        remoteCommandTargets.removeAll()
    }

    private func playFromRemoteCommand() {
        guard isPlaybackSessionActive, player.currentItem != nil else {
            return
        }
        configureAudioSession()
        player.playImmediately(atRate: playbackRate)
        updateNowPlayingInfo()
    }

    private func pauseFromRemoteCommand() {
        guard isPlaybackSessionActive else {
            return
        }
        queueWatchHistoryReport(force: true)
        player.pause()
        updateNowPlayingInfo()
    }

    private func seekFromRemoteCommand(to seconds: TimeInterval) {
        guard isPlaybackSessionActive, let item = player.currentItem else {
            return
        }
        let duration = item.duration.seconds
        let upperBound = duration.isFinite && duration > 0 ? duration : seconds
        let position = min(max(seconds, 0), max(upperBound, 0))
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        playbackPositionMilliseconds = Int64(position * 1_000)
        updateDanmakuPosition(playbackPositionMilliseconds)
        queueWatchHistoryReport(force: true)
        updateNowPlayingInfo()
    }

    private func configureNowPlayingMetadata(for detail: FocusVideoDetail) {
        nowPlayingRevision &+= 1
        let revision = nowPlayingRevision
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtwork = nil
        lastNowPlayingElapsedUpdate = -1
        updateNowPlayingInfo()

        guard let coverURL = detail.coverURL else {
            return
        }
        let referer = currentURL?.absoluteString ?? "https://www.bilibili.com/"
        nowPlayingArtworkTask = Task { [weak self] in
            var request = URLRequest(url: coverURL)
            request.setValue(referer, forHTTPHeaderField: "Referer")
            request.setValue(FocusUserAgent.mobileSafari(), forHTTPHeaderField: "User-Agent")
            guard
                let (data, response) = try? await URLSession.shared.data(for: request),
                !Task.isCancelled,
                (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) != false,
                let image = UIImage(data: data)
            else {
                return
            }
            guard let self, revision == self.nowPlayingRevision else {
                return
            }
            self.nowPlayingArtwork = makeFocusNowPlayingArtwork(image: image)
            self.updateNowPlayingInfo()
        }
    }

    private func resetNowPlayingMetadata() {
        nowPlayingRevision &+= 1
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = nil
        nowPlayingArtwork = nil
        lastNowPlayingElapsedUpdate = -1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }

    private func updateNowPlayingInfoIfNeeded(milliseconds: Int64) {
        let elapsedSeconds = max(milliseconds / 1_000, 0)
        guard lastNowPlayingElapsedUpdate < 0 || abs(elapsedSeconds - lastNowPlayingElapsedUpdate) >= 15 else {
            return
        }
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard isPlaybackSessionActive, let detail else {
            return
        }
        let page = activePage
        let duration = max(page?.duration ?? detail.duration, 0)
        let elapsed = max(Double(currentPlaybackMilliseconds) / 1_000, 0)
        let effectiveRate = player.timeControlStatus == .playing ? Double(playbackRate) : 0
        let title: String
        if detail.pages.count > 1, let page, !page.title.isEmpty {
            title = "\(detail.title) · \(page.title)"
        } else {
            title = detail.title
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: detail.owner.name,
            MPMediaItemPropertyPlaybackDuration: Double(duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: min(elapsed, Double(max(duration, 0))),
            MPNowPlayingInfoPropertyPlaybackRate: effectiveRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(playbackRate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyExternalContentIdentifier: detail.bvid,
        ]
        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        if #available(iOS 13.0, *) {
            center.playbackState = player.timeControlStatus == .playing ? .playing : .paused
        }
        lastNowPlayingElapsedUpdate = Int64(elapsed)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            // AVPlayer can still attempt playback when another audio session owns the route.
        }
    }

    private func cancelTasks() {
        loadTask?.cancel()
        loadTask = nil
        commentsTask?.cancel()
        commentsTask = nil
        interactionTask?.cancel()
        interactionTask = nil
        playbackTask?.cancel()
        playbackTask = nil
        actionTasks.values.forEach { $0.cancel() }
        actionTasks.removeAll()
        cancelDanmakuRequests()
    }

    private func cancelPortraitExitTransition() {
        fullscreenTransitionRevision &+= 1
        portraitExitTask?.cancel()
        portraitExitTask = nil
        isCompletingPortraitExit = false
    }

    private func setFullscreenPresented(_ presented: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isFullscreen = presented
        }
    }

    private func cancelFullscreenTransitions() {
        orientationDebounceTask?.cancel()
        orientationDebounceTask = nil
        lastHandledDeviceOrientation = .unknown
        cancelPortraitExitTransition()
    }

    private struct WatchHistoryReport: Equatable, Sendable {
        let aid: Int64
        let cid: Int64
        let progressSeconds: Int64
    }

    private struct DanmakuContext: Equatable {
        let aid: Int64
        let cid: Int64
        let durationMilliseconds: Int64
    }

    private static let defaultDanmakuSegmentMilliseconds: Int64 = 360_000
}

enum FocusDanmakuSegmentScheduler {
    static let defaultSegmentDurationMilliseconds: Int64 = 360_000
    static let defaultPrefetchWindowMilliseconds: Int64 = 30_000

    static func segmentIndexes(
        playbackPositionMilliseconds: Int64,
        segmentDurationMilliseconds: Int64,
        totalSegments: Int,
        prefetchWindowMilliseconds: Int64 = defaultPrefetchWindowMilliseconds
    ) -> [Int] {
        let position = max(playbackPositionMilliseconds, 0)
        let duration = segmentDurationMilliseconds > 0
            ? segmentDurationMilliseconds
            : defaultSegmentDurationMilliseconds
        let quotient = position / duration
        let calculated = quotient >= Int64(Int.max) ? Int.max : Int(quotient) + 1
        let current = totalSegments > 0
            ? min(calculated, totalSegments)
            : calculated
        guard current > 0 else {
            return []
        }

        var result = [current]
        let (segmentEnd, overflow) = Int64(current).multipliedReportingOverflow(by: duration)
        let remaining = overflow ? Int64.max : segmentEnd - position
        if current < Int.max,
           remaining <= max(prefetchWindowMilliseconds, 0),
           totalSegments <= 0 || current + 1 <= totalSegments
        {
            result.append(current + 1)
        }
        return result
    }
}

private enum FocusNativePlaybackFactory {
    private static let headerOptionsKey = "AVURLAssetHTTPHeaderFieldsKey"

    @MainActor
    static func makeItems(for source: FocusVideoPlaybackSource) async throws -> [AVPlayerItem] {
        switch source.stream {
        case let .progressive(urls):
            return urls.map { url in
                AVPlayerItem(asset: makeAsset(url: url, headers: source.headers))
            }

        case let .dash(videoURL, audioURL):
            let videoAsset = makeAsset(url: videoURL, headers: source.headers)
            guard let audioURL else {
                return [AVPlayerItem(asset: videoAsset)]
            }
            let audioAsset = makeAsset(url: audioURL, headers: source.headers)
            let composition = try await makeComposition(videoAsset: videoAsset, audioAsset: audioAsset)
            return [AVPlayerItem(asset: composition)]
        }
    }

    private static func makeAsset(url: URL, headers: [String: String]) -> AVURLAsset {
        AVURLAsset(url: url, options: [headerOptionsKey: headers])
    }

    @MainActor
    private static func makeComposition(
        videoAsset: AVURLAsset,
        audioAsset: AVURLAsset
    ) async throws -> AVMutableComposition {
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let sourceVideoTrack = videoTracks.first, let sourceAudioTrack = audioTracks.first else {
            throw FocusVideoDetailService.ServiceError.noStream
        }

        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        guard videoDuration.isNumeric, CMTimeCompare(videoDuration, .zero) > 0 else {
            throw FocusVideoDetailService.ServiceError.noStream
        }

        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw FocusVideoDetailService.ServiceError.noStream
        }

        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: sourceVideoTrack,
            at: .zero
        )
        videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        let resolvedAudioDuration: CMTime
        if audioDuration.isNumeric, CMTimeCompare(audioDuration, .zero) > 0 {
            resolvedAudioDuration = CMTimeCompare(audioDuration, videoDuration) < 0
                ? audioDuration
                : videoDuration
        } else {
            resolvedAudioDuration = videoDuration
        }
        try audioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: resolvedAudioDuration),
            of: sourceAudioTrack,
            at: .zero
        )
        return composition
    }
}

private func makeFocusNowPlayingArtwork(image: UIImage) -> MPMediaItemArtwork {
    // MediaPlayer invokes this handler on its own access queue. Keeping the
    // closure outside the @MainActor view model avoids inheriting MainActor.
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
}

enum FocusNativePlaybackLifecyclePolicy {
    static let audiovisualBackgroundPlaybackPolicy: AVPlayerAudiovisualBackgroundPlaybackPolicy =
        .continuesIfPossible

    static func shouldPauseForApplicationBackground(isPlaying _: Bool) -> Bool {
        false
    }

    static func shouldResumeAfterInterruption(
        wasPlaying: Bool,
        systemAllowsResume: Bool
    ) -> Bool {
        wasPlaying && systemAllowsResume
    }
}

enum FocusNativeVideoSelection {
    static func currentEpisodeIndex(
        in episodes: [FocusVideoEpisode],
        currentBVID: String,
        currentCID: Int64? = nil
    ) -> Int? {
        if let currentCID, currentCID > 0 {
            if let exactMatch = episodes.firstIndex(where: {
                $0.bvid == currentBVID && $0.cid == currentCID
            }) {
                return exactMatch
            }
            if let caseInsensitiveMatch = episodes.firstIndex(where: {
                $0.cid == currentCID
                    && $0.bvid.caseInsensitiveCompare(currentBVID) == .orderedSame
            }) {
                return caseInsensitiveMatch
            }
            if let cidMatch = episodes.firstIndex(where: { $0.cid == currentCID }) {
                return cidMatch
            }
        }

        return episodes.firstIndex(where: { $0.bvid == currentBVID })
            ?? episodes.firstIndex(where: {
                $0.bvid.caseInsensitiveCompare(currentBVID) == .orderedSame
            })
    }

    static func episodeURL(for episode: FocusVideoEpisode) -> URL? {
        guard var components = URLComponents(
            string: "https://www.bilibili.com/video/\(episode.bvid)/"
        ) else {
            return nil
        }
        if episode.cid > 0 {
            components.queryItems = [URLQueryItem(name: "cid", value: String(episode.cid))]
        }
        return components.url
    }
}

struct FocusNativeVideoDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: FocusNativeVideoViewModel
    let onOpenUser: (Int64) -> Void
    let onOpenVideo: (URL) -> Void
    let onOpenURL: (URL) -> Void
    let onOpenWeb: (URL) -> Void
    @State private var isDescriptionExpanded = true

    var body: some View {
        content
            .background(Color(uiColor: .systemGroupedBackground))
            .fullScreenCover(isPresented: $viewModel.isFullscreen) {
                FocusNativeVideoFullscreenView(viewModel: viewModel)
            }
            .alert(
                "操作未完成",
                isPresented: Binding(
                    get: { viewModel.actionErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.actionErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("知道了", role: .cancel) {
                    viewModel.actionErrorMessage = nil
                }
            } message: {
                Text(viewModel.actionErrorMessage ?? "请稍后重试")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                viewModel.handleDeviceOrientationChange(UIDevice.current.orientation)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: 0) {
                playerPlaceholder(coverURL: nil)
                ProgressView("加载视频详情…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        case let .failed(message):
            VStack(spacing: 0) {
                playerPlaceholder(coverURL: nil)
                FocusStateView(
                    title: "原生视频加载失败",
                    message: message,
                    buttonTitle: "重新加载",
                    action: viewModel.reload
                )
                if let url = viewModel.currentURL {
                    Button("改用网页打开") {
                        onOpenWeb(url)
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 24)
                }
            }

        case let .loaded(detail):
            VStack(spacing: 0) {
                player(detail: detail)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        titleSection(detail)
                        FocusNativeVideoActionBar(viewModel: viewModel, statistics: detail.statistics)
                        authorSection(detail.owner)
                        if detail.pages.count > 1 {
                            pageSection(detail.pages)
                        }
                        ForEach(detail.episodeGroups) { group in
                            episodeSection(
                                group,
                                currentBVID: detail.bvid,
                                currentCID: viewModel.activePage?.cid ?? detail.cid
                            )
                        }
                        if !detail.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            descriptionSection(detail.summary)
                        }
                        commentsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func player(detail: FocusVideoDetail) -> some View {
        ZStack {
            Color.black
            if viewModel.hasPreparedPlayer, !viewModel.isFullscreen {
                FocusNativePlayerSurface(player: viewModel.player, showsPlaybackControls: false)
            } else {
                FocusRemoteImage(url: detail.coverURL, referer: viewModel.currentURL?.absoluteString ?? "https://www.bilibili.com/") { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .opacity(0.72)
                    case .empty, .failure:
                        Color.black
                    }
                }
            }

            if !viewModel.isFullscreen {
                FocusNativeDanmakuOverlay(viewModel: viewModel)
                    .allowsHitTesting(false)
                FocusNativeDanmakuStatusOverlay(viewModel: viewModel)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }

            if viewModel.isLoadingPlayback {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.15)
            }

            if let message = viewModel.playerErrorMessage {
                VStack(spacing: 10) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    HStack(spacing: 10) {
                        Button("重试播放", action: viewModel.retryPlayback)
                            .buttonStyle(.borderedProminent)
                        if let url = viewModel.currentURL {
                            Button("网页播放") {
                                onOpenWeb(url)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }
                    }
                }
                .padding(20)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(max(detail.aspectRatio, 0.5), contentMode: .fit)
        .clipped()
        .accessibilityLabel("原生视频播放器")
    }

    private func playerPlaceholder(coverURL: URL?) -> some View {
        ZStack {
            Color.black
            if let coverURL {
                FocusRemoteImage(url: coverURL) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFit().opacity(0.7)
                    } else {
                        Color.black
                    }
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }

    private func titleSection(_ detail: FocusVideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Label(FocusNativeVideoFormatting.count(detail.statistics.views), systemImage: "play.rectangle")
                Label(FocusNativeVideoFormatting.count(detail.statistics.danmaku), systemImage: "text.bubble")
                if detail.publishedAt > 0 {
                    Text(FocusNativeVideoFormatting.date(detail.publishedAt))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        }
    }

    private func authorSection(_ owner: FocusVideoOwner) -> some View {
        Button {
            guard owner.mid > 0 else {
                return
            }
            onOpenUser(owner.mid)
        } label: {
            HStack(spacing: 12) {
                FocusRemoteImage(
                    url: owner.avatarURL,
                    referer: owner.mid > 0 ? "https://space.bilibili.com/\(owner.mid)" : "https://www.bilibili.com/"
                ) { phase in
                    Group {
                        if case let .success(image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(owner.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("查看 UP 主空间")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(owner.mid <= 0)
    }

    private func pageSection(_ pages: [FocusVideoPage]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分P · 共 \(pages.count) 条")
                .font(.headline)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(pages) { page in
                            let isSelectedPage = viewModel.selectedPageCID == page.cid
                            Button {
                                viewModel.selectPage(page)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("P\(page.pageNumber)")
                                        .font(.caption.weight(.semibold))
                                    Text(page.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                    Text(FocusNativeVideoFormatting.duration(page.duration))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(isSelectedPage ? FocusSharedDesign.primary : .primary)
                                .frame(width: 156, alignment: .leading)
                                .padding(12)
                                .background(
                                    isSelectedPage
                                        ? FocusSharedDesign.primary.opacity(0.12)
                                        : Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(
                                            isSelectedPage
                                                ? FocusSharedDesign.primary.opacity(colorScheme == .dark ? 1 : 0.72)
                                                : Color.clear,
                                            lineWidth: colorScheme == .dark ? 2 : 1.5
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .id(page.cid)
                        }
                    }
                }
                .task(id: viewModel.selectedPageCID) {
                    guard let selectedPageCID = viewModel.selectedPageCID else {
                        return
                    }
                    await scrollToSelection(selectedPageCID, using: proxy)
                }
            }
        }
    }

    private func episodeSection(
        _ group: FocusVideoEpisodeGroup,
        currentBVID: String,
        currentCID: Int64
    ) -> some View {
        let currentEpisodeIndex = FocusNativeVideoSelection.currentEpisodeIndex(
            in: group.episodes,
            currentBVID: currentBVID,
            currentCID: currentCID
        )
        let currentEpisodeID = currentEpisodeIndex.map { group.episodes[$0].id }

        return VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.headline)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(group.episodes) { episode in
                            let isCurrentEpisode = episode.id == currentEpisodeID
                            Button {
                                guard !isCurrentEpisode,
                                      let url = FocusNativeVideoSelection.episodeURL(for: episode)
                                else {
                                    return
                                }
                                onOpenVideo(url)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    FocusRemoteImage(url: episode.coverURL, referer: "https://www.bilibili.com/video/\(episode.bvid)/") { phase in
                                        Group {
                                            if case let .success(image) = phase {
                                                image.resizable().scaledToFill()
                                            } else {
                                                Color(uiColor: .tertiarySystemFill)
                                                    .overlay { Image(systemName: "play.rectangle").foregroundStyle(.secondary) }
                                            }
                                        }
                                        .frame(width: 170, height: 96)
                                        .clipped()
                                    }
                                    Text(episode.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    if !episode.badge.isEmpty {
                                        Text(episode.badge)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(FocusSharedDesign.primary)
                                    }
                                }
                                .frame(width: 170, alignment: .leading)
                                .padding(10)
                                .background(
                                    isCurrentEpisode
                                        ? FocusSharedDesign.primary.opacity(0.12)
                                        : Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(
                                            isCurrentEpisode
                                                ? FocusSharedDesign.primary.opacity(colorScheme == .dark ? 1 : 0.72)
                                                : Color.clear,
                                            lineWidth: colorScheme == .dark ? 2 : 1.5
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .id(episode.id)
                        }
                    }
                }
                .task(id: currentEpisodeID) {
                    guard let currentEpisodeID else {
                        return
                    }
                    await scrollToSelection(currentEpisodeID, using: proxy)
                }
            }
        }
    }

    private func scrollToSelection<ID: Hashable>(
        _ id: ID,
        using proxy: ScrollViewProxy
    ) async {
        // The first pass establishes the lazy stack's target. A second pass on the
        // next layout window prevents distant items from being left just outside
        // the viewport when a large episode list is materialized asynchronously.
        await Task.yield()
        guard !Task.isCancelled else {
            return
        }
        proxy.scrollTo(id, anchor: .center)
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard !Task.isCancelled else {
            return
        }
        proxy.scrollTo(id, anchor: .center)
    }

    private func descriptionSection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(isDescriptionExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if summary.count > 120 {
                Button(isDescriptionExpanded ? "收起" : "展开") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDescriptionExpanded.toggle()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(FocusSharedDesign.primary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var commentsSection: some View {
        if !viewModel.comments.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("评论 · \(viewModel.comments.count)")
                    .font(.headline)
                ForEach(viewModel.comments) { comment in
                    FocusNativeVideoCommentRow(comment: comment, onOpenURL: onOpenURL)
                }
            }
        }
    }
}

struct FocusNativeVideoControlDock: View {
    @ObservedObject var viewModel: FocusNativeVideoViewModel

    var body: some View {
        HStack(spacing: 8) {
            FocusVideoControlButton(
                systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill",
                title: viewModel.isPlaying ? "暂停" : "播放",
                accessibilityLabel: viewModel.isPlaying ? "暂停视频" : "播放视频",
                action: viewModel.togglePlayback
            )
            FocusVideoControlButton(
                systemImage: "speedometer",
                title: FocusNativeVideoFormatting.rate(viewModel.playbackRate),
                accessibilityLabel: "切换播放速度",
                action: viewModel.cyclePlaybackRate
            )
            FocusVideoControlButton(
                systemImage: "text.bubble",
                title: viewModel.isDanmakuEnabled ? "开" : "关",
                isActive: viewModel.isDanmakuEnabled,
                accessibilityLabel: viewModel.isDanmakuEnabled ? "关闭弹幕" : "开启弹幕",
                action: viewModel.toggleDanmaku
            )
            FocusVideoControlButton(
                systemImage: "arrow.up.left.and.arrow.down.right",
                title: "全屏",
                accessibilityLabel: "进入全屏",
                action: viewModel.requestFullscreen
            )
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FocusSharedDesign.chromePanelBackground.opacity(0.32))
        )
    }
}

private struct FocusNativeVideoActionBar: View {
    @ObservedObject var viewModel: FocusNativeVideoViewModel
    let statistics: FocusVideoStatistics

    var body: some View {
        HStack(spacing: 0) {
            actionButton(
                action: .like,
                title: "点赞",
                value: statistics.likes,
                image: "BiliLike",
                active: viewModel.interactionState.liked,
                enabled: !viewModel.isLoadingInteractions,
                handler: viewModel.toggleLike
            )
            Divider().frame(height: 42)
            actionButton(
                action: .coin,
                title: "投币",
                value: statistics.coins,
                image: "BiliCoin",
                active: viewModel.interactionState.coined,
                enabled: !viewModel.isLoadingInteractions && !viewModel.interactionState.coined,
                handler: viewModel.addCoin
            )
            Divider().frame(height: 42)
            actionButton(
                action: .favorite,
                title: "收藏",
                value: statistics.favorites,
                image: "BiliFavorite",
                active: viewModel.interactionState.favorited,
                enabled: !viewModel.isLoadingInteractions,
                handler: viewModel.toggleFavorite
            )
        }
        .padding(.vertical, 5)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func actionButton(
        action: FocusNativeVideoViewModel.Action,
        title: String,
        value: Int64,
        image: String,
        active: Bool,
        enabled: Bool,
        handler: @escaping () -> Void
    ) -> some View {
        Button(action: handler) {
            VStack(spacing: 5) {
                if viewModel.actionsInFlight.contains(action) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                } else {
                    Image(image)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
                Text("\(title) · \(FocusNativeVideoFormatting.count(value))")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? FocusSharedDesign.primary : .secondary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || viewModel.actionsInFlight.contains(action))
        .accessibilityLabel("\(title)，\(FocusNativeVideoFormatting.count(value))")
    }
}

private struct FocusNativeVideoCommentRow: View {
    let comment: FocusVideoComment
    let onOpenURL: (URL) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FocusRemoteImage(url: comment.avatarURL, referer: "https://www.bilibili.com/") { phase in
                Group {
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(comment.authorName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(FocusNativeVideoFormatting.relativeDate(comment.publishedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                FocusInlineRichText(
                    runs: comment.contentRuns,
                    font: .subheadline,
                    onOpenURL: onOpenURL
                )
                .fixedSize(horizontal: false, vertical: true)
                ForEach(comment.previewReplies.prefix(2)) { reply in
                    HStack(alignment: .top, spacing: 2) {
                        Text("\(reply.authorName)：")
                            .font(.caption)
                            .foregroundStyle(FocusSharedDesign.primary)
                        FocusInlineRichText(
                            runs: reply.contentRuns,
                            font: .caption,
                            foreground: .secondary,
                            onOpenURL: onOpenURL
                        )
                    }
                    .padding(.leading, 8)
                }
                HStack(spacing: 12) {
                    if comment.likes > 0 {
                        Label(FocusNativeVideoFormatting.count(comment.likes), systemImage: "hand.thumbsup")
                    }
                    if comment.replies > 0 {
                        Text("\(FocusNativeVideoFormatting.count(comment.replies)) 回复")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FocusNativeDanmakuOverlay: View {
    @ObservedObject var viewModel: FocusNativeVideoViewModel

    var body: some View {
        GeometryReader { geometry in
            let laneHeight: CGFloat = 32
            let usableHeight = geometry.size.height * 0.75
            let laneCount = max(Int(usableHeight / laneHeight), 1)
            let placements = FocusNativeDanmakuLayout.placements(
                for: viewModel.danmakus,
                laneCount: laneCount
            )

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !viewModel.isPlaying)) { _ in
                let playbackMilliseconds = viewModel.isPlaying
                    ? viewModel.danmakuPlaybackPositionMilliseconds
                    : viewModel.playbackPositionMilliseconds
                Canvas { context, size in
                    for placement in placements {
                        let elapsed = playbackMilliseconds - placement.danmaku.progressMilliseconds
                        guard elapsed >= 0, elapsed < FocusNativeDanmakuLayout.displayMilliseconds else {
                            continue
                        }

                        let color = FocusNativeDanmakuLayout.color(placement.danmaku.colorRGB)
                        let fontScale = min(max(CGFloat(placement.danmaku.fontSize) / 25, 0.72), 1.44)
                        let text = Text(placement.danmaku.content)
                            .font(.system(size: 18 * fontScale, weight: .semibold))
                            .foregroundColor(color.opacity(0.94))
                        let resolvedText = context.resolve(text)
                        let textSize = resolvedText.measure(
                            in: CGSize(width: .greatestFiniteMagnitude, height: laneHeight)
                        )
                        let x: CGFloat
                        switch placement.danmaku.mode {
                        case .scrolling:
                            let progress = CGFloat(elapsed) / CGFloat(FocusNativeDanmakuLayout.displayMilliseconds)
                            x = size.width - progress * (size.width + textSize.width)
                        case .top, .bottom:
                            x = (size.width - textSize.width) / 2
                        }
                        let y: CGFloat
                        switch placement.danmaku.mode {
                        case .bottom:
                            y = usableHeight - CGFloat(placement.lane + 1) * laneHeight
                        case .scrolling, .top:
                            y = CGFloat(placement.lane) * laneHeight
                        }
                        let shadowColor: Color = FocusNativeDanmakuLayout.isDark(color) ? .white : .black
                        context.drawLayer { layer in
                            layer.addFilter(
                                .shadow(
                                    color: shadowColor.opacity(0.95),
                                    radius: 2,
                                    x: 1,
                                    y: 1
                                )
                            )
                            layer.draw(
                                resolvedText,
                                at: CGPoint(x: x, y: max(y, 0)),
                                anchor: .topLeading
                            )
                        }
                    }
                }
            }
        }
        .opacity(viewModel.isDanmakuEnabled ? 1 : 0)
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct FocusNativeDanmakuStatusOverlay: View {
    @ObservedObject var viewModel: FocusNativeVideoViewModel

    @ViewBuilder
    var body: some View {
        if viewModel.isDanmakuEnabled {
            switch viewModel.danmakuLoadState {
            case .failed:
                Button("弹幕加载失败 · 重试", action: viewModel.retryDanmaku)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.62), in: Capsule())
                    .buttonStyle(.plain)
            case .closed:
                Text("该视频未开启弹幕")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.62), in: Capsule())
            case .idle, .loading, .ready:
                EmptyView()
            }
        }
    }
}

enum FocusNativeDanmakuLayout {
    static let displayMilliseconds: Int64 = 5_000

    struct Placement {
        let danmaku: FocusVideoDanmaku
        let lane: Int
    }

    static func placements(
        for danmakus: [FocusVideoDanmaku],
        laneCount: Int
    ) -> [Placement] {
        guard laneCount > 0 else {
            return []
        }
        var availableAt = Dictionary(
            uniqueKeysWithValues: FocusVideoDanmakuMode.allCases.map {
                ($0, Array(repeating: Int64(0), count: laneCount))
            }
        )
        var result: [Placement] = []
        for danmaku in danmakus {
            guard var lanes = availableAt[danmaku.mode],
                  let lane = lanes.firstIndex(where: { $0 <= danmaku.progressMilliseconds })
            else {
                continue
            }
            lanes[lane] = danmaku.progressMilliseconds + displayMilliseconds
            availableAt[danmaku.mode] = lanes
            result.append(Placement(danmaku: danmaku, lane: lane))
        }
        return result
    }

    static func color(_ rgb: Int?) -> Color {
        let value = rgb ?? 0xffffff
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    static func isDark(_ color: Color) -> Bool {
        guard let components = UIColor(color).cgColor.components else {
            return false
        }
        let red = components.count > 0 ? components[0] : 1
        let green = components.count > 1 ? components[1] : red
        let blue = components.count > 2 ? components[2] : red
        return (0.299 * red + 0.587 * green + 0.114 * blue) < 0.28
    }
}

private extension FocusVideoDanmakuMode {
    static var allCases: [FocusVideoDanmakuMode] {
        [.scrolling, .top, .bottom]
    }
}

private struct FocusNativePlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    let showsPlaybackControls: Bool

    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = false
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context _: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.showsPlaybackControls = showsPlaybackControls
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = false
        controller.view.backgroundColor = .black
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator _: Void) {
        controller.player = nil
    }
}

private struct FocusNativeVideoFullscreenView: View {
    @ObservedObject var viewModel: FocusNativeVideoViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            FocusNativePlayerSurface(player: viewModel.player, showsPlaybackControls: true)
                .ignoresSafeArea()
            FocusNativeDanmakuOverlay(viewModel: viewModel)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            FocusNativeDanmakuStatusOverlay(viewModel: viewModel)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 18)
        }
        .statusBarHidden(true)
        .onDisappear {
            FocusNativeVideoOrientation.update(to: .portrait)
        }
    }
}

enum FocusNativeVideoFullscreenPolicy {
    static func orientation(for detail: FocusVideoDetail) -> UIInterfaceOrientationMask {
        guard detail.width > 0, detail.height > 0 else {
            return .landscape
        }
        return detail.width > detail.height ? .landscape : .portrait
    }
}

@MainActor
private enum FocusNativeVideoOrientation {
    static func update(to mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        guard let scene = activeWindowScene else {
            return
        }

        let rootViewController = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        rootViewController?.presentedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }

    static func rotateToPortraitAndWait() async {
        update(to: .portrait)
        guard let scene = activeWindowScene else {
            await Task.yield()
            return
        }

        var settledSamples = 0
        for _ in 0 ..< 90 {
            guard !Task.isCancelled else {
                return
            }
            if hasSettledPortraitGeometry(scene) {
                settledSamples += 1
                if settledSamples >= 2 {
                    return
                }
            } else {
                settledSamples = 0
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    private static func hasSettledPortraitGeometry(_ scene: UIWindowScene) -> Bool {
        let bounds = scene.coordinateSpace.bounds
        return scene.interfaceOrientation.isPortrait && bounds.height >= bounds.width
    }

    private static var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
    }
}

private enum FocusNativeVideoFormatting {
    static func count(_ value: Int64) -> String {
        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return String(value)
        }
    }

    static func duration(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return ""
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%lld:%02lld:%02lld", hours, minutes, remainingSeconds)
        }
        return String(format: "%02lld:%02lld", minutes, remainingSeconds)
    }

    static func rate(_ value: Float) -> String {
        value.rounded() == value ? "\(Int(value))x" : "\(String(format: "%.2g", value))x"
    }

    static func date(_ timestamp: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    static func relativeDate(_ timestamp: Int64) -> String {
        guard timestamp > 0 else {
            return ""
        }
        let delta = max(Int64(Date().timeIntervalSince1970) - timestamp, 0)
        switch delta {
        case 0 ..< 60:
            return "刚刚"
        case 60 ..< 3_600:
            return "\(max(delta / 60, 1))分钟前"
        case 3_600 ..< 86_400:
            return "\(max(delta / 3_600, 1))小时前"
        case 86_400 ..< 604_800:
            return "\(max(delta / 86_400, 1))天前"
        default:
            return date(timestamp)
        }
    }
}

private extension FocusVideoStatistics {
    func replacing(
        views: Int64? = nil,
        danmaku: Int64? = nil,
        replies: Int64? = nil,
        favorites: Int64? = nil,
        coins: Int64? = nil,
        shares: Int64? = nil,
        likes: Int64? = nil
    ) -> FocusVideoStatistics {
        FocusVideoStatistics(
            views: views ?? self.views,
            danmaku: danmaku ?? self.danmaku,
            replies: replies ?? self.replies,
            favorites: favorites ?? self.favorites,
            coins: coins ?? self.coins,
            shares: shares ?? self.shares,
            likes: likes ?? self.likes
        )
    }
}

private extension FocusVideoDetail {
    func replacing(statistics: FocusVideoStatistics) -> FocusVideoDetail {
        FocusVideoDetail(
            bvid: bvid,
            aid: aid,
            cid: cid,
            title: title,
            summary: summary,
            coverURL: coverURL,
            duration: duration,
            publishedAt: publishedAt,
            width: width,
            height: height,
            owner: owner,
            statistics: statistics,
            pages: pages,
            episodeGroups: episodeGroups
        )
    }
}
#endif
