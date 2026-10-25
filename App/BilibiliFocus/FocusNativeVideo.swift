#if canImport(UIKit)
import AVFoundation
import AVKit
import Combine
import FocusCore
import MediaPlayer
import SwiftUI
import UIKit

/// Serializes local playback-progress writes across video routes. Registering a
/// write is synchronous on the main actor, so a route opened immediately after
/// another route is suspended can wait for every write that was already queued.
/// Remote history delivery deliberately stays outside this coordinator.
@MainActor
final class FocusPlaybackProgressWriteCoordinator {
    typealias Write = @Sendable () async -> Void

    private var tail: Task<Void, Never>?

    @discardableResult
    func enqueue(_ write: @escaping Write) -> Task<Void, Never> {
        let predecessor = tail
        let task = Task { @MainActor in
            await predecessor?.value
            await write()
        }
        tail = task
        return task
    }

    func waitForPendingWrites() async {
        let pendingWrites = tail
        await pendingWrites?.value
    }
}

@MainActor
final class FocusNativeVideoViewModel: ObservableObject {
    typealias LandscapeRequest = @MainActor () -> Void
    typealias PortraitFullscreenRequest = @MainActor () -> Void
    typealias PortraitTransition = @MainActor () async -> Void
    typealias DanmakuPreferenceChange = @MainActor (Bool) -> Void
    typealias SubtitlePreferenceChange = @MainActor (Bool, String) -> Void
    typealias PlaybackReadyWaiter = @MainActor (AVPlayerItem) async throws -> Void
    typealias InitialPlaybackSeeker = @MainActor (AVQueuePlayer, Int64) async throws -> Void
    typealias PlaybackItemFactory = @MainActor (FocusVideoPlaybackSource) async throws -> [AVPlayerItem]
    typealias AccountScopeProvider = @Sendable () async -> FocusPlaybackAccountScope

    /// Route-local list metadata only. Never substitutes for fetched detail,
    /// player readiness or the first-frame diagnostic.
    struct RoutePreview: Equatable {
        let title: String
        let coverURL: URL?
    }

    enum PlaybackPreparationError: Error, LocalizedError {
        case readinessTimedOut

        var errorDescription: String? {
            "播放器准备超时，请重试播放。"
        }
    }

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

    enum SubtitleLoadState: Equatable {
        case idle
        case loadingTracks
        case loadingDocument
        case ready
        case unavailable
        case failed(String)
    }

    struct CommentThreadState: Equatable {
        var replies: [FocusVideoComment]
        var totalCount: Int64
        var nextCursor: FocusVideoCommentRepliesCursor?
        var isExpanded: Bool
        var isLoading: Bool
        var hasLoadedFirstPage: Bool
        var errorMessage: String?
    }

    struct CommentLikeState: Equatable {
        let likes: Int64
        let isLiked: Bool
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var routePreview: RoutePreview?
    @Published private(set) var comments: [FocusVideoComment] = []
    @Published private(set) var commentTotalCount: Int64 = 0
    @Published private(set) var isLoadingMoreComments = false
    @Published private(set) var commentsErrorMessage: String?
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
    @Published private(set) var availableQualities: [FocusVideoQuality] = []
    @Published private(set) var selectedQuality = 80
    @Published private(set) var qualityDescription = "自动清晰度"
    @Published private(set) var danmakus: [FocusVideoDanmaku] = []
    @Published private(set) var danmakuLoadState: DanmakuLoadState = .idle
    @Published private(set) var isDanmakuEnabled: Bool
    @Published private(set) var subtitleTracks: [FocusVideoSubtitleTrack] = []
    @Published private(set) var selectedSubtitleTrackID: Int64?
    @Published private(set) var subtitleCues: [FocusVideoSubtitleCue] = []
    @Published private(set) var subtitleLoadState: SubtitleLoadState = .idle
    @Published private(set) var isSubtitleEnabled: Bool
    @Published private(set) var commentThreadStates: [Int64: CommentThreadState] = [:]
    @Published private(set) var commentLikeOverrides: [Int64: CommentLikeState] = [:]
    @Published private(set) var commentLikeActionsInFlight: Set<Int64> = []
    @Published var isFullscreen = false
    @Published var actionErrorMessage: String?

    let player: AVQueuePlayer

    private let detailService: FocusVideoDetailService
    private let actionService: FocusVideoActionService
    private let subtitleService: FocusVideoSubtitleService?
    private let commentService: FocusVideoCommentService?
    private let playbackProgressStore: FocusPlaybackProgressStore
    private let playbackProgressWriteCoordinator: FocusPlaybackProgressWriteCoordinator
    private let accountScopeProvider: AccountScopeProvider
    private var activePlaybackAccountScope: FocusPlaybackAccountScope?
    private var commentAccountScope: FocusPlaybackAccountScope?
    private var sourceURL: URL?
    private var requestedPageNumber: Int?
    private var requestedPageCID: Int64?
    private var shouldResolveInitialResumePage = false
    private var loadTask: Task<Void, Never>?
    private var commentsTask: Task<Void, Never>?
    private var commentsNextCursor: FocusVideoCommentCursor?
    private var consumedCommentCursors: Set<FocusVideoCommentCursor> = []
    private var isCommentsPaginationActive = false
    private var commentReplyTasks: [Int64: Task<Void, Never>] = [:]
    private var commentLikeTasks: [Int64: Task<Void, Never>] = [:]
    private var interactionTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var actionTasks: [Action: Task<Void, Never>] = [:]
    private var loadGeneration: UInt64 = 0
    private var commentsGeneration: UInt64 = 0
    private var commentThreadsGeneration: UInt64 = 0
    private var commentLikeGenerations: [Int64: UInt64] = [:]
    private var interactionGeneration: UInt64 = 0
    private var playbackGeneration: UInt64 = 0
    private var actionGenerations: [Action: UInt64] = [:]
    private var watchHistoryReportTask: Task<Void, Never>?
    private var watchHistoryRetryTask: Task<Void, Never>?
    private var watchHistoryRetryGeneration: UInt64 = 0
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
    private var subtitleTracksTask: Task<Void, Never>?
    private var subtitleDocumentTask: Task<Void, Never>?
    private var subtitleGeneration: UInt64 = 0
    private var subtitleDocumentGeneration: UInt64 = 0
    private var subtitleContext: SubtitleContext?
    private var subtitleCueCache: [Int64: [FocusVideoSubtitleCue]] = [:]
    private var preferredSubtitleLanguageCode: String
    private var shouldResumeAfterActivation = false
    private var shouldResumeAfterAudioInterruption = false
    private var isReplacingPlayerItem = false
    private var playbackRateBeforeTemporaryChange: Float?
    private var preparedMediaDurationMilliseconds: Int64?
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
    private let subtitlePreferenceChange: SubtitlePreferenceChange
    private let playbackReadyWaiter: PlaybackReadyWaiter
    private let initialPlaybackSeeker: InitialPlaybackSeeker
    private let playbackItemFactory: PlaybackItemFactory
    private let resumeBudgetNanoseconds: UInt64
    private let resumeBudgetSleeper: FocusAsyncDeadline.Sleeper
    private(set) var playbackDiagnosticID = UUID()
    private var requestSessionVersion: UInt64?
    private var firstFrameSpan: BiliPerformanceSpan?
    private var videoStartupSpan: BiliPerformanceSpan?
    private var videoStartupID = UUID()
    private var activeSurfaces: Set<UUID> = []
    private var readySurface: (surface: UUID, item: ObjectIdentifier, request: UUID, fullscreen: Bool)?
    private(set) var isCompletingPortraitExit = false

    var navigationTitle: String {
        if case let .loaded(detail) = state {
            return detail.title
        }
        return routePreview?.title.nilIfBlank ?? "视频"
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

    var playbackDurationMilliseconds: Int64 {
        if let item = player.currentItem, item.duration.isNumeric {
            let seconds = item.duration.seconds
            if seconds.isFinite, seconds > 0 { return Int64(seconds * 1_000) }
        }
        if let preparedMediaDurationMilliseconds { return preparedMediaDurationMilliseconds }
        return max(activePage?.duration ?? detail?.duration ?? 0, 0) * 1_000
    }

    var hasPlaybackEnded: Bool {
        hasPreparedPlayer && !isLoadingPlayback && player.currentItem == nil
    }

    private var isPlaybackRequested: Bool {
        FocusNativePlaybackLifecyclePolicy.isPlaybackRequested(
            rate: player.rate, timeControlStatus: player.timeControlStatus
        )
    }

    var showsPlaybackControls: Bool {
        detail != nil
    }

    var hasActiveLoadTask: Bool {
        loadTask != nil || commentsTask != nil || interactionTask != nil || playbackTask != nil
    }

    var hasActivePlaybackPreparationTask: Bool {
        playbackTask != nil
    }

    var hasActiveWatchHistoryRetryTask: Bool {
        watchHistoryRetryTask != nil
    }

    var hasBoundPlaybackAccountScope: Bool {
        activePlaybackAccountScope != nil
    }

    var hasMoreComments: Bool {
        commentsNextCursor != nil
    }

    var displayedCommentCount: Int64 {
        commentTotalCount > 0 ? commentTotalCount : Int64(comments.count)
    }

    init(
        detailService: FocusVideoDetailService,
        actionService: FocusVideoActionService,
        subtitleService: FocusVideoSubtitleService? = nil,
        commentService: FocusVideoCommentService? = nil,
        playbackProgressStore: FocusPlaybackProgressStore = .shared,
        playbackProgressWriteCoordinator: FocusPlaybackProgressWriteCoordinator? = nil,
        accountScopeProvider: @escaping AccountScopeProvider = { .anonymous },
        nativeDanmakuEnabled: Bool = true,
        danmakuPreferenceChange: DanmakuPreferenceChange? = nil,
        nativeSubtitleEnabled: Bool = true,
        preferredSubtitleLanguageCode: String = "",
        subtitlePreferenceChange: SubtitlePreferenceChange? = nil,
        landscapeRequest: LandscapeRequest? = nil,
        portraitFullscreenRequest: PortraitFullscreenRequest? = nil,
        portraitTransition: PortraitTransition? = nil,
        playbackReadyWaiter: PlaybackReadyWaiter? = nil,
        initialPlaybackSeeker: InitialPlaybackSeeker? = nil,
        playbackItemFactory: PlaybackItemFactory? = nil,
        resumeBudgetNanoseconds: UInt64 = 2_000_000_000,
        resumeBudgetSleeper: @escaping FocusAsyncDeadline.Sleeper = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.detailService = detailService
        self.actionService = actionService
        self.subtitleService = subtitleService
        self.commentService = commentService
        self.playbackProgressStore = playbackProgressStore
        self.playbackProgressWriteCoordinator =
            playbackProgressWriteCoordinator ?? FocusPlaybackProgressWriteCoordinator()
        self.accountScopeProvider = accountScopeProvider
        self.isDanmakuEnabled = nativeDanmakuEnabled
        self.isSubtitleEnabled = nativeSubtitleEnabled
        self.preferredSubtitleLanguageCode = preferredSubtitleLanguageCode
        self.danmakuPreferenceChange = danmakuPreferenceChange ?? { _ in }
        self.subtitlePreferenceChange = subtitlePreferenceChange ?? { _, _ in }
        self.landscapeRequest = landscapeRequest ?? {
            FocusNativeVideoOrientation.update(to: .landscape)
        }
        self.portraitFullscreenRequest = portraitFullscreenRequest ?? {
            FocusNativeVideoOrientation.update(to: .portrait)
        }
        self.portraitTransition = portraitTransition ?? {
            await FocusNativeVideoOrientation.rotateToPortraitAndWait()
        }
        self.playbackReadyWaiter = playbackReadyWaiter ?? { item in
            try await Self.waitUntilReadyToPlay(item)
        }
        self.initialPlaybackSeeker = initialPlaybackSeeker ?? { player, milliseconds in
            try await Self.seek(player, toMilliseconds: milliseconds)
        }
        self.playbackItemFactory = playbackItemFactory ?? FocusNativePlaybackFactory.makeItems
        self.resumeBudgetNanoseconds = resumeBudgetNanoseconds
        self.resumeBudgetSleeper = resumeBudgetSleeper
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
                self.isPlaying = player.rate > 0 && player.timeControlStatus == .playing
                if self.hasPlaybackEnded {
                    self.playbackPositionMilliseconds = self.playbackDurationMilliseconds
                }
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
                // The callback may have been queued by a positive rate just
                // before pause(). Re-read once on the actor; zero is transport
                // state, not a new user-selected playback speed.
                let rate = player.rate
                guard let self, rate > 0 else {
                    return
                }
                self.playbackRate = rate
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
        retryPendingWatchHistoryReports()
    }

    deinit {
        loadTask?.cancel()
        commentsTask?.cancel()
        commentReplyTasks.values.forEach { $0.cancel() }
        commentLikeTasks.values.forEach { $0.cancel() }
        interactionTask?.cancel()
        playbackTask?.cancel()
        actionTasks.values.forEach { $0.cancel() }
        watchHistoryRetryTask?.cancel()
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
        subtitleTracksTask?.cancel()
        subtitleDocumentTask?.cancel()
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

    func reconcileSessionVersion(_ version: UInt64) {
        guard version == detailService.sessionVersion, requestSessionVersion != version else { return }
        requestSessionVersion = version
        // Only unfinished setup needs replacement. Unchanged credentials must
        // not interrupt an already-running media item.
        if case .loading = state { reload() }
        else if isLoadingPlayback && !hasPreparedPlayer { reload() }
    }

    func seedRoutePreview(_ preview: RoutePreview?, for url: URL) {
        open(url)
        routePreview = preview
    }

    func activate(url: URL) {
        open(url)
        if !hasPreparedPlayer, videoStartupSpan == nil { beginVideoStartup() }
        isCommentsPaginationActive = true
        retryPendingWatchHistoryReports()
        activatePlaybackSession()
        loadIfNeeded()

        if let detail {
            configureDanmaku(
                for: detail,
                playbackPositionMilliseconds: currentPlaybackMilliseconds
            )
            configureSubtitles(for: detail)
            if (comments.isEmpty || commentAccountScope == nil),
               commentsTask == nil
            {
                loadComments(for: detail)
            }
            resumeExpandedCommentReplyLoads()
        }

        if hasPreparedPlayer, shouldResumeAfterActivation {
            player.playImmediately(atRate: playbackRate)
        } else if detail != nil, !hasPreparedPlayer, playbackTask == nil {
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
        activePlaybackAccountScope = nil
        cancelTasks()
        finishVideoStartup(outcome: .cancelled)
        beginVideoStartup()
        sourceURL = canonicalURL
        routePreview = nil
        requestedPageNumber = FocusVideoDetailService.requestedPageNumber(from: canonicalURL)
        requestedPageCID = FocusVideoDetailService.requestedPageCID(from: canonicalURL)
        shouldResolveInitialResumePage = requestedPageNumber == nil && requestedPageCID == nil
        state = .idle
        comments = []
        commentTotalCount = 0
        commentsNextCursor = nil
        consumedCommentCursors.removeAll()
        commentsErrorMessage = nil
        isLoadingMoreComments = false
        resetCommentInteractionSession()
        interactionState = FocusVideoInteractionState()
        isLoadingInteractions = false
        actionsInFlight = []
        selectedPageCID = nil
        availableQualities = []
        selectedQuality = 80
        qualityDescription = "自动清晰度"
        resetDanmakuSession()
        resetSubtitleSession()
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
        activePlaybackAccountScope = nil
        cancelTasks()
        if videoStartupSpan == nil { beginVideoStartup() }
        state = .loading
        comments = []
        commentTotalCount = 0
        commentsNextCursor = nil
        consumedCommentCursors.removeAll()
        commentsErrorMessage = nil
        isLoadingMoreComments = false
        resetCommentInteractionSession()
        interactionState = FocusVideoInteractionState()
        isLoadingInteractions = false
        selectedPageCID = nil
        resetDanmakuSession()
        resetSubtitleSession()
        playerErrorMessage = nil
        hasPreparedPlayer = false
        isLoadingPlayback = false
        shouldResolveInitialResumePage = requestedPageNumber == nil && requestedPageCID == nil
        player.pause()
        player.removeAllItems()

        let generation = loadGeneration
        requestSessionVersion = detailService.sessionVersion
        let detailDiagnosticID = videoStartupID
        let detailSpan = BiliPerformanceStore.shared.begin(.videoDetail, correlationID: detailDiagnosticID)
        loadTask = Task { [weak self, detailService] in
            guard let self else {
                return
            }
            defer {
                if self.loadGeneration == generation {
                    self.loadTask = nil
                }
            }
            do {
                let detail = try await detailService.fetchDetail(for: sourceURL)
                try Task.checkCancellation()
                guard loadGeneration == generation else {
                    BiliPerformanceStore.shared.end(detailSpan, outcome: .stale)
                    return
                }
                BiliPerformanceStore.shared.end(detailSpan)
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
                configureSubtitles(for: detail)
                preparePlayback(correlationID: detailDiagnosticID)
                loadComments(for: detail)
                loadInteractions(for: detail)
            } catch is CancellationError {
                BiliPerformanceStore.shared.end(detailSpan, outcome: .cancelled)
                return
            } catch {
                BiliPerformanceStore.shared.end(detailSpan, outcome: .failure)
                guard !Task.isCancelled, loadGeneration == generation else {
                    return
                }
                state = .failed(error.localizedDescription)
                finishVideoStartup(outcome: .failure)
            }
        }
    }

    func suspend() {
        endTemporaryPlaybackRate()
        isCommentsPaginationActive = false
        finishVideoStartup(outcome: .cancelled)
        queueWatchHistoryReport(force: true)
        shouldResumeAfterActivation = isPlaybackRequested
        shouldResumeAfterAudioInterruption = false
        let wasPreparingPlayback = playbackTask != nil || isLoadingPlayback
        cancelLoadTask()
        cancelCommentsTask()
        cancelInteractionTask()
        cancelPlaybackTask()
        cancelActionTasks()
        cancelCommentReplyTasks()
        cancelFullscreenTransitions()
        actionsInFlight = []
        cancelDanmakuRequests()
        cancelSubtitleRequests()
        isLoadingInteractions = false
        isLoadingPlayback = false
        isReplacingPlayerItem = false
        if wasPreparingPlayback {
            hasPreparedPlayer = false
            player.removeAllItems()
        }
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
        endTemporaryPlaybackRate()
        queueWatchHistoryReport(force: true)
        if FocusNativePlaybackLifecyclePolicy.shouldPauseForApplicationBackground(
            isPlaying: player.timeControlStatus == .playing
        ) {
            player.pause()
        }
        updateNowPlayingInfo()
    }

    func handleAppDidBecomeActive() {
        retryPendingWatchHistoryReports()
        updateNowPlayingInfo()
    }

    func selectPage(_ page: FocusVideoPage) {
        guard selectedPageCID != page.cid else {
            return
        }
        queueWatchHistoryReport(force: true)
        activePlaybackAccountScope = nil
        shouldResolveInitialResumePage = false
        selectedPageCID = page.cid
        updateNowPlayingInfo()
        if let detail {
            configureDanmaku(for: detail, playbackPositionMilliseconds: 0)
            configureSubtitles(for: detail)
        }
        preparePlayback()
    }

    func retryPlayback() {
        preparePlayback()
    }

    func togglePlayback() {
        guard !isLoadingPlayback else {
            return
        }
        guard player.currentItem != nil else {
            preparePlayback()
            return
        }

        if isPlaybackRequested {
            queueWatchHistoryReport(force: true)
            player.pause()
            isPlaying = false
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
        setPlaybackRate(nextRate)
    }

    func setPlaybackRate(_ rate: Float) {
        guard rate.isFinite, rate >= 0.5, rate <= 3 else { return }
        playbackRateBeforeTemporaryChange = nil
        applyPlaybackRate(rate)
    }

    func beginTemporaryPlaybackRate(_ rate: Float = 2) {
        guard hasPreparedPlayer, isPlaybackRequested,
              playbackRateBeforeTemporaryChange == nil else { return }
        playbackRateBeforeTemporaryChange = playbackRate
        applyPlaybackRate(max(playbackRate, rate))
    }

    func endTemporaryPlaybackRate() {
        guard let previous = playbackRateBeforeTemporaryChange else { return }
        playbackRateBeforeTemporaryChange = nil
        applyPlaybackRate(previous)
    }

    private func applyPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player.defaultRate = rate
        if isPlaybackRequested {
            player.rate = rate
        }
        updateNowPlayingInfo()
    }

    func seek(toMilliseconds position: Int64) {
        guard hasPreparedPlayer, !isLoadingPlayback, let item = player.currentItem else { return }
        let target = min(max(position, 0), playbackDurationMilliseconds)
        let generation = playbackGeneration
        item.cancelPendingSeeks()
        playbackPositionMilliseconds = target
        updateDanmakuPosition(target)
        player.seek(to: CMTime(value: target, timescale: 1_000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] finished in
            Task { @MainActor [weak self, weak item] in
                guard let self, finished, playbackGeneration == generation,
                      player.currentItem === item else { return }
                queueWatchHistoryReport(force: true)
                updateNowPlayingInfo()
            }
        }
    }

    func selectQuality(_ quality: FocusVideoQuality) {
        guard !isLoadingPlayback, quality.id != selectedQuality,
              availableQualities.contains(where: { $0.id == quality.id }) else { return }
        let position = currentPlaybackMilliseconds
        let shouldPlay = isPlaybackRequested
        queueWatchHistoryReport(force: true)
        selectedQuality = quality.id
        preparePlayback(initialPosition: position, startsPlaying: shouldPlay)
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

    var selectedSubtitleTrack: FocusVideoSubtitleTrack? {
        subtitleTracks.first(where: { $0.id == selectedSubtitleTrackID })
    }

    var subtitleControlTitle: String {
        guard isSubtitleEnabled else {
            return "关"
        }
        switch subtitleLoadState {
        case .loadingTracks, .loadingDocument:
            return "…"
        case .unavailable:
            return "无"
        case .failed:
            return "!"
        case .idle, .ready:
            return selectedSubtitleTrack?.displayName ?? "开"
        }
    }

    func selectSubtitleTrack(_ track: FocusVideoSubtitleTrack) {
        guard subtitleTracks.contains(where: { $0.id == track.id }) else {
            return
        }
        let preferenceChanged = !isSubtitleEnabled
            || preferredSubtitleLanguageCode != track.languageCode
        isSubtitleEnabled = true
        preferredSubtitleLanguageCode = track.languageCode
        selectedSubtitleTrackID = track.id
        if preferenceChanged {
            subtitlePreferenceChange(true, track.languageCode)
        }
        loadSubtitleDocument(for: track)
    }

    func disableSubtitles() {
        setSubtitlesEnabled(false, persist: true)
    }

    func enableSubtitles() {
        setSubtitlesEnabled(true, persist: true)
    }

    func applySubtitlePreference(enabled: Bool, languageCode: String) {
        preferredSubtitleLanguageCode = languageCode
        setSubtitlesEnabled(enabled, persist: false)
        guard enabled else {
            return
        }
        if let preferredTrack = preferredSubtitleTrack(in: subtitleTracks) {
            selectedSubtitleTrackID = preferredTrack.id
            loadSubtitleDocument(for: preferredTrack)
        }
    }

    func retrySubtitles() {
        guard let detail else {
            return
        }
        subtitleTracksTask?.cancel()
        subtitleDocumentTask?.cancel()
        subtitleTracksTask = nil
        subtitleDocumentTask = nil
        configureSubtitles(for: detail, forceReload: subtitleTracks.isEmpty)
    }

    func subtitleText(at playbackPositionMilliseconds: Int64) -> String {
        guard isSubtitleEnabled, !subtitleCues.isEmpty else {
            return ""
        }
        let position = max(playbackPositionMilliseconds, 0)
        return subtitleCues.lazy
            .filter {
                $0.startMilliseconds <= position
                    && position < $0.endMilliseconds
            }
            .map(\.content)
            .joined(separator: "\n")
    }

    func commentDidAppear(_ commentID: Int64) {
        guard commentsErrorMessage == nil,
              comments.suffix(4).contains(where: { $0.id == commentID }) else { return }
        loadMoreComments()
    }

    func retryComments() {
        if comments.isEmpty, let detail { loadComments(for: detail) }
        else { loadMoreComments() }
    }

    func loadMoreComments() {
        guard
            isCommentsPaginationActive,
            commentsTask == nil,
            let detail,
            let cursor = commentsNextCursor,
            let accountScope = commentAccountScope
        else {
            return
        }

        let generation = commentsGeneration
        commentsErrorMessage = nil
        isLoadingMoreComments = true
        commentsTask = Task {
            [weak self, detailService, accountScopeProvider] in
            guard let self else {
                return
            }
            defer {
                if self.commentsGeneration == generation {
                    self.commentsTask = nil
                    self.isLoadingMoreComments = false
                }
            }
            do {
                let currentScope = await accountScopeProvider()
                try Task.checkCancellation()
                guard commentsGeneration == generation else {
                    return
                }
                guard currentScope == accountScope else {
                    invalidateCommentSessionForAccountChange(
                        detail: detail,
                        presentsError: true
                    )
                    return
                }

                let page = try await detailService.fetchCommentsPage(
                    aid: detail.aid,
                    cursor: cursor
                )
                try Task.checkCancellation()
                guard commentsGeneration == generation else {
                    return
                }

                let resultingScope = await accountScopeProvider()
                try Task.checkCancellation()
                guard commentsGeneration == generation else {
                    return
                }
                guard resultingScope == accountScope else {
                    invalidateCommentSessionForAccountChange(
                        detail: detail,
                        presentsError: true
                    )
                    return
                }

                var seen = Set(comments.map(\.id))
                comments.append(
                    contentsOf: page.comments.filter { seen.insert($0.id).inserted }
                )
                commentTotalCount = max(commentTotalCount, page.totalCount)
                consumedCommentCursors.insert(cursor)
                commentsNextCursor = page.nextCursor.flatMap { consumedCommentCursors.contains($0) ? nil : $0 }
            } catch is CancellationError {
                return
            } catch {
                guard commentsGeneration == generation, !Task.isCancelled else { return }
                commentsErrorMessage = error.localizedDescription
            }
        }
    }

    func replies(for comment: FocusVideoComment) -> [FocusVideoComment] {
        guard let thread = commentThreadStates[comment.id], thread.isExpanded else {
            return Array(comment.previewReplies.prefix(2))
        }
        return thread.replies
    }

    func commentThreadState(for commentID: Int64) -> CommentThreadState? {
        commentThreadStates[commentID]
    }

    func toggleCommentReplies(_ comment: FocusVideoComment) {
        var thread = commentThreadStates[comment.id] ?? initialCommentThreadState(for: comment)
        if thread.isExpanded {
            thread.isExpanded = false
            commentThreadStates[comment.id] = thread
            return
        }

        thread.isExpanded = true
        thread.errorMessage = nil
        commentThreadStates[comment.id] = thread
        if !thread.hasLoadedFirstPage, !thread.isLoading {
            loadCommentReplies(for: comment, cursor: nil)
        }
    }

    func loadMoreCommentReplies(for comment: FocusVideoComment) {
        guard
            let thread = commentThreadStates[comment.id],
            thread.isExpanded,
            !thread.isLoading,
            let cursor = thread.nextCursor
        else {
            return
        }
        loadCommentReplies(for: comment, cursor: cursor)
    }

    func retryCommentReplies(for comment: FocusVideoComment) {
        guard commentThreadStates[comment.id]?.isLoading != true else {
            return
        }
        let cursor = commentThreadStates[comment.id]?.hasLoadedFirstPage == true
            ? commentThreadStates[comment.id]?.nextCursor
            : nil
        loadCommentReplies(for: comment, cursor: cursor)
    }

    func commentLikeState(for comment: FocusVideoComment) -> CommentLikeState {
        commentLikeOverrides[comment.id]
            ?? CommentLikeState(likes: comment.likes, isLiked: comment.isLiked)
    }

    func toggleCommentLike(_ comment: FocusVideoComment) {
        guard
            let detail,
            let commentService,
            let accountScope = commentAccountScope,
            comment.id > 0,
            !commentLikeActionsInFlight.contains(comment.id)
        else {
            return
        }

        let previous = commentLikeState(for: comment)
        let shouldLike = !previous.isLiked
        let optimistic = CommentLikeState(
            likes: max(previous.likes + (shouldLike ? 1 : -1), 0),
            isLiked: shouldLike
        )
        let generation = (commentLikeGenerations[comment.id] ?? 0) &+ 1
        commentLikeGenerations[comment.id] = generation
        commentLikeOverrides[comment.id] = optimistic
        commentLikeActionsInFlight.insert(comment.id)
        actionErrorMessage = nil

        commentLikeTasks[comment.id]?.cancel()
        commentLikeTasks[comment.id] = Task {
            [weak self, accountScopeProvider] in
            guard let self else {
                return
            }
            defer {
                if self.commentLikeGenerations[comment.id] == generation {
                    self.commentLikeActionsInFlight.remove(comment.id)
                    self.commentLikeTasks[comment.id] = nil
                }
            }
            do {
                let currentScope = await accountScopeProvider()
                try Task.checkCancellation()
                guard commentLikeGenerations[comment.id] == generation else {
                    return
                }
                guard currentScope == accountScope else {
                    invalidateCommentSessionForAccountChange(
                        detail: detail,
                        presentsError: true
                    )
                    return
                }

                try await commentService.setCommentLiked(
                    aid: detail.aid,
                    commentID: comment.id,
                    liked: shouldLike,
                    expectedAccountScope: accountScope
                )
                try Task.checkCancellation()
                guard commentLikeGenerations[comment.id] == generation else {
                    return
                }

                let resultingScope = await accountScopeProvider()
                try Task.checkCancellation()
                guard commentLikeGenerations[comment.id] == generation else {
                    return
                }
                guard resultingScope == accountScope else {
                    invalidateCommentSessionForAccountChange(
                        detail: detail,
                        presentsError: true
                    )
                    return
                }
            } catch is CancellationError {
                return
            } catch FocusVideoCommentService.ServiceError.accountScopeChanged {
                guard
                    !Task.isCancelled,
                    commentLikeGenerations[comment.id] == generation
                else {
                    return
                }
                invalidateCommentSessionForAccountChange(
                    detail: detail,
                    presentsError: true
                )
            } catch {
                guard
                    !Task.isCancelled,
                    commentLikeGenerations[comment.id] == generation
                else {
                    return
                }
                commentLikeOverrides[comment.id] = previous
                actionErrorMessage = error.localizedDescription
            }
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
            guard let self, !Task.isCancelled else {
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
            guard let self, !Task.isCancelled else {
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
            guard let self, !Task.isCancelled else {
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

    private func preparePlayback(
        correlationID: UUID? = nil, initialPosition: Int64? = nil,
        startsPlaying: Bool = true
    ) {
        guard let detail else {
            return
        }
        let cid = selectedPageCID
            ?? detail.pages.first(where: { $0.cid == detail.cid })?.cid
            ?? detail.pages.first?.cid
            ?? detail.cid
        // Only a multi-part video needs history before choosing a stream CID.
        // Single-part videos can fetch the stream while history is still loading.
        let mayResolveResumePage = shouldResolveInitialResumePage && detail.pages.count > 1
        let requestedQuality = selectedQuality

        endTemporaryPlaybackRate()
        cancelPlaybackTask()
        playbackDiagnosticID = correlationID ?? (videoStartupSpan == nil ? UUID() : videoStartupID)
        requestSessionVersion = detailService.sessionVersion
        let diagnosticID = playbackDiagnosticID
        firstFrameSpan = BiliPerformanceStore.shared.begin(.firstFrame, correlationID: diagnosticID)
        readySurface = nil
        activePlaybackAccountScope = nil
        let generation = playbackGeneration
        isReplacingPlayerItem = true
        player.pause()
        player.removeAllItems()
        playbackPositionMilliseconds = 0
        preparedMediaDurationMilliseconds = nil
        isLoadingPlayback = true
        hasPreparedPlayer = false
        playerErrorMessage = nil

        playbackTask = Task {
            [
                weak self,
                detailService,
                playbackProgressStore,
                playbackProgressWriteCoordinator,
                accountScopeProvider,
                initialPlaybackSeeker,
            ] in
            guard let self else {
                return
            }
            defer {
                if self.playbackGeneration == generation {
                    self.playbackTask = nil
                }
            }
            do {
                async let sessionVersionRequest = detailService.prepareSessionVersion()
                async let accountScopeRequest = accountScopeProvider()
                let (sessionVersion, accountScope) = await (sessionVersionRequest, accountScopeRequest)
                try Task.checkCancellation()
                guard playbackGeneration == generation, detailService.sessionVersion == sessionVersion else {
                    return
                }
                var playbackCID = cid
                var localResume: FocusPlaybackProgressEntry?
                var serverResume: FocusVideoPlaybackResume?
                if initialPosition != nil {
                    try await prepareMedia(
                        bvid: detail.bvid, cid: cid, quality: requestedQuality, generation: generation,
                        sessionVersion: sessionVersion, diagnosticID: diagnosticID
                    )
                } else if mayResolveResumePage {
                    await playbackProgressWriteCoordinator.waitForPendingWrites()
                    try Task.checkCancellation()
                    let storedResume = await playbackProgressStore.recentProgress(
                        accountScope: accountScope,
                        aid: detail.aid,
                        bvid: detail.bvid
                    )
                    try Task.checkCancellation()
                    guard playbackGeneration == generation else {
                        return
                    }

                    if shouldResolveInitialResumePage {
                        shouldResolveInitialResumePage = false
                        if let storedResume,
                           FocusPlaybackResumeResolver.isMeaningfulResume(
                               storedResume.playbackResume
                           ),
                           detail.pages.contains(where: { $0.cid == storedResume.cid })
                        {
                            localResume = storedResume
                            playbackCID = storedResume.cid
                            selectedPageCID = storedResume.cid
                            updateNowPlayingInfo()
                            configureDanmaku(for: detail, playbackPositionMilliseconds: 0)
                        } else {
                            serverResume = try await boundedServerResume(aid: detail.aid, cid: cid, diagnosticID: diagnosticID)
                            try Task.checkCancellation()
                            guard playbackGeneration == generation else {
                                return
                            }
                            if let serverResume,
                               FocusPlaybackResumeResolver.isMeaningfulResume(serverResume),
                               detail.pages.contains(where: { $0.cid == serverResume.cid })
                            {
                                playbackCID = serverResume.cid
                                selectedPageCID = serverResume.cid
                                updateNowPlayingInfo()
                                configureDanmaku(for: detail, playbackPositionMilliseconds: 0)
                            }
                        }
                    }
                    try await prepareMedia(
                        bvid: detail.bvid, cid: playbackCID, quality: requestedQuality, generation: generation,
                        sessionVersion: sessionVersion, diagnosticID: diagnosticID
                    )
                } else {
                    shouldResolveInitialResumePage = false
                    async let mediaReady: Void = prepareMedia(
                        bvid: detail.bvid, cid: cid, quality: requestedQuality, generation: generation,
                        sessionVersion: sessionVersion, diagnosticID: diagnosticID
                    )
                    // The CID is already known. A previous route's progress
                    // write must finish before reading resume, not before CDN
                    // preparation; both branches still join before playback.
                    await playbackProgressWriteCoordinator.waitForPendingWrites()
                    try Task.checkCancellation()
                    localResume = await playbackProgressStore.recentProgress(
                        accountScope: accountScope,
                        aid: detail.aid,
                        bvid: detail.bvid,
                        cid: cid
                    )
                    try Task.checkCancellation()
                    guard playbackGeneration == generation else {
                        return
                    }
                    if let storedResume = localResume,
                       !FocusPlaybackResumeResolver.isMeaningfulResume(
                           storedResume.playbackResume
                       )
                    {
                        localResume = nil
                    }
                    if localResume == nil {
                        serverResume = try await boundedServerResume(aid: detail.aid, cid: cid, diagnosticID: diagnosticID)
                    }
                    try await mediaReady
                }
                try Task.checkCancellation()
                guard playbackGeneration == generation else {
                    return
                }
                guard detailService.sessionVersion == sessionVersion else { throw CancellationError() }

                let durationSeconds = detail.pages.first(where: { $0.cid == playbackCID })?.duration
                    ?? detail.duration
                let initialPositionMilliseconds = initialPosition ??
                    FocusPlaybackResumeResolver.initialPositionMilliseconds(
                        local: localResume,
                        server: serverResume,
                        selectedCID: playbackCID,
                        durationSeconds: durationSeconds
                    )
                if initialPositionMilliseconds > 0 {
                    try await initialPlaybackSeeker(player, initialPositionMilliseconds)
                    try Task.checkCancellation()
                    guard playbackGeneration == generation else {
                        return
                    }
                    playbackPositionMilliseconds = initialPositionMilliseconds
                    updateDanmakuPosition(initialPositionMilliseconds)
                }

                guard detailService.sessionVersion == sessionVersion else { throw CancellationError() }
                activePlaybackAccountScope = accountScope
                isLoadingPlayback = false
                hasPreparedPlayer = true
                finishFirstFrameIfPresentable()
                configureAudioSession()
                player.defaultRate = playbackRate
                isReplacingPlayerItem = false
                updateNowPlayingInfo()
                if startsPlaying { player.playImmediately(atRate: playbackRate) }
                else { player.pause() }
                queueWatchHistoryReport(force: true)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, playbackGeneration == generation else {
                    return
                }
                isLoadingPlayback = false
                hasPreparedPlayer = false
                isReplacingPlayerItem = false
                if let firstFrameSpan { BiliPerformanceStore.shared.end(firstFrameSpan, outcome: .failure) }
                firstFrameSpan = nil
                finishVideoStartup(outcome: .failure)
                playerErrorMessage = error.localizedDescription
            }
        }
    }

    private func prepareMedia(
        bvid: String, cid: Int64, quality: Int, generation: UInt64, sessionVersion: UInt64, diagnosticID: UUID
    ) async throws {
        let urlSpan = BiliPerformanceStore.shared.begin(.playbackURL, correlationID: diagnosticID)
        let source: FocusVideoPlaybackSource
        do {
            source = try await detailService.fetchPlayback(bvid: bvid, cid: cid, quality: quality)
            BiliPerformanceStore.shared.end(urlSpan)
        } catch {
            BiliPerformanceStore.shared.end(urlSpan, outcome: error is CancellationError ? .cancelled : .failure)
            throw error
        }
        try Task.checkCancellation()
        guard playbackGeneration == generation, detailService.sessionVersion == sessionVersion else { throw CancellationError() }
        availableQualities = source.availableQualities
        selectedQuality = source.quality ?? quality
        qualityDescription = source.qualityDescription

        let streams = [source.stream] + source.fallbackStreams
        let started = ContinuousClock.now
        let totalBudget: UInt64 = 30_000_000_000
        for (index, stream) in streams.enumerated() {
            try Task.checkCancellation()
            let elapsed = started.duration(to: .now).components
            let elapsedNanoseconds = UInt64(elapsed.seconds) * 1_000_000_000 + UInt64(elapsed.attoseconds / 1_000_000_000)
            guard elapsedNanoseconds < totalBudget else { throw PlaybackPreparationError.readinessTimedOut }
            // Give each remaining address a chance inside the original 30s
            // startup budget, rather than waiting 30s again for every CDN.
            let attemptBudget = (totalBudget - elapsedNanoseconds) / UInt64(streams.count - index)
            let candidate = FocusVideoPlaybackSource(
                stream: stream, headers: source.headers, qualityDescription: source.qualityDescription
            )
            do {
                try await FocusAsyncDeadline.value(timeoutNanoseconds: attemptBudget) { [weak self] in
                    guard let self else { throw CancellationError() }
                    try await self.prepareMediaCandidate(
                        candidate, generation: generation, sessionVersion: sessionVersion, diagnosticID: diagnosticID
                    )
                }
                return
            } catch {
                try Task.checkCancellation()
                guard playbackGeneration == generation, detailService.sessionVersion == sessionVersion else { throw CancellationError() }
                guard index + 1 < streams.count, Self.canTryBackupStream(after: error) else {
                    if error is FocusAsyncDeadlineError { throw PlaybackPreparationError.readinessTimedOut }
                    throw error
                }
            }
        }
    }

    private static func canTryBackupStream(after error: Error) -> Bool {
        if error is FocusAsyncDeadlineError || error is PlaybackPreparationError { return true }
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain {
            return [URLError.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                    .dnsLookupFailed, .badServerResponse, .resourceUnavailable, .cannotLoadFromNetwork]
                .contains(URLError.Code(rawValue: failure.code))
        }
        if failure.domain == AVFoundationErrorDomain {
            return [AVError.failedToLoadMediaData, .serverIncorrectlyConfigured, .fileFormatNotRecognized,
                    .contentIsUnavailable].contains(AVError.Code(rawValue: failure.code))
        }
        if let underlying = failure.userInfo[NSUnderlyingErrorKey] as? Error {
            return canTryBackupStream(after: underlying)
        }
        return false
    }

    private func prepareMediaCandidate(
        _ source: FocusVideoPlaybackSource, generation: UInt64, sessionVersion: UInt64, diagnosticID: UUID
    ) async throws {
        let mediaSpan = BiliPerformanceStore.shared.begin(.mediaPreparation, correlationID: diagnosticID)
        let items: [AVPlayerItem]
        do {
            items = try await playbackItemFactory(source)
            try Task.checkCancellation()
            guard playbackGeneration == generation, detailService.sessionVersion == sessionVersion else { throw CancellationError() }
            guard !items.isEmpty else { throw FocusVideoDetailService.ServiceError.noStream }
            player.removeAllItems()
            var previous: AVPlayerItem?
            for item in items where player.canInsert(item, after: previous) {
                player.insert(item, after: previous)
                previous = item
            }
            BiliPerformanceStore.shared.end(mediaSpan)
        } catch {
            BiliPerformanceStore.shared.end(mediaSpan, outcome: error is CancellationError ? .cancelled : .failure)
            throw error
        }
        guard let firstItem = player.currentItem else { throw FocusVideoDetailService.ServiceError.noStream }
        let readySpan = BiliPerformanceStore.shared.begin(.playerReady, correlationID: diagnosticID)
        do {
            try await playbackReadyWaiter(firstItem)
            try Task.checkCancellation()
            guard playbackGeneration == generation, detailService.sessionVersion == sessionVersion,
                  player.currentItem === firstItem else { throw CancellationError() }
            let durationSeconds = firstItem.duration.seconds
            if durationSeconds.isFinite, durationSeconds > 0 {
                preparedMediaDurationMilliseconds = Int64(durationSeconds * 1_000)
            }
            BiliPerformanceStore.shared.end(readySpan)
        } catch {
            BiliPerformanceStore.shared.end(readySpan, outcome: error is CancellationError ? .cancelled : .failure)
            throw error
        }
    }

    private func boundedServerResume(aid: Int64, cid: Int64, diagnosticID: UUID) async throws -> FocusVideoPlaybackResume? {
        let span = BiliPerformanceStore.shared.begin(.resumeLookup, correlationID: diagnosticID)
        do {
            let resume = try await FocusAsyncDeadline.value(
                timeoutNanoseconds: resumeBudgetNanoseconds, sleeper: resumeBudgetSleeper
            ) { [detailService] in try await detailService.fetchPlaybackResume(aid: aid, cid: cid) }
            BiliPerformanceStore.shared.end(span)
            return resume
        } catch is CancellationError {
            BiliPerformanceStore.shared.end(span, outcome: .cancelled)
            throw CancellationError()
        } catch FocusAsyncDeadlineError.timedOut {
            BiliPerformanceStore.shared.end(span, outcome: .timedOut)
            return nil
        } catch {
            BiliPerformanceStore.shared.end(span, outcome: .fallback)
            return nil
        }
    }

    func activatePresentationSurface(_ id: UUID) { activeSurfaces.insert(id) }
    func deactivatePresentationSurface(_ id: UUID) {
        activeSurfaces.remove(id)
        if readySurface?.surface == id { readySurface = nil }
    }
    func recordSurfaceReadiness(surface: UUID, itemID: ObjectIdentifier?, isReady: Bool, requestID: UUID,
                                isFullscreenSurface: Bool = false) {
        guard requestID == playbackDiagnosticID, activeSurfaces.contains(surface),
              isFullscreenSurface == isFullscreen,
              let itemID, player.currentItem.map(ObjectIdentifier.init) == itemID else { return }
        if isReady { readySurface = (surface, itemID, requestID, isFullscreenSurface) }
        else if readySurface?.surface == surface { readySurface = nil }
        finishFirstFrameIfPresentable()
    }
    private func finishFirstFrameIfPresentable() {
        guard hasPreparedPlayer, !isLoadingPlayback, let readySurface,
              readySurface.request == playbackDiagnosticID, readySurface.fullscreen == isFullscreen,
              activeSurfaces.contains(readySurface.surface),
              player.currentItem.map(ObjectIdentifier.init) == readySurface.item,
              let span = firstFrameSpan else { return }
        BiliPerformanceStore.shared.end(span)
        firstFrameSpan = nil
        finishVideoStartup(outcome: .success)
    }

    private func beginVideoStartup() {
        videoStartupID = UUID()
        videoStartupSpan = BiliPerformanceStore.shared.begin(.videoStartup, correlationID: videoStartupID)
    }

    private func finishVideoStartup(outcome: BiliPerformanceOutcome) {
        if let videoStartupSpan { BiliPerformanceStore.shared.end(videoStartupSpan, outcome: outcome) }
        videoStartupSpan = nil
    }

    private func queueWatchHistoryReport(force: Bool) {
        guard let detail, let activePlaybackAccountScope else {
            return
        }
        let cid = selectedPageCID
            ?? detail.pages.first(where: { $0.cid == detail.cid })?.cid
            ?? detail.pages.first?.cid
            ?? detail.cid
        let report = WatchHistoryReport(
            accountScope: activePlaybackAccountScope,
            aid: detail.aid,
            bvid: detail.bvid,
            cid: cid,
            positionMilliseconds: max(currentPlaybackMilliseconds, 0)
        )

        if let previous = lastQueuedWatchHistoryReport,
           previous.accountScope == report.accountScope,
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
        let localWrite = playbackProgressWriteCoordinator.enqueue {
            [playbackProgressStore] in
            if report.accountScope == .anonymous {
                _ = await playbackProgressStore.recordProgress(
                    accountScope: report.accountScope,
                    aid: report.aid,
                    bvid: report.bvid,
                    cid: report.cid,
                    positionMilliseconds: report.positionMilliseconds
                )
                return
            }

            _ = await playbackProgressStore.recordProgressAndEnqueueHistory(
                accountScope: report.accountScope,
                aid: report.aid,
                bvid: report.bvid,
                cid: report.cid,
                positionMilliseconds: report.positionMilliseconds
            )
        }
        guard report.accountScope != .anonymous else {
            watchHistoryReportTask = localWrite
            return
        }

        watchHistoryReportTask = Task { [actionService, playbackProgressStore] in
            await localWrite.value
            FocusHistoryBackgroundScheduler.shared.schedule()
            let outcome = await playbackProgressStore.drainPendingHistory(
                accountScope: report.accountScope
            ) { pendingReport in
                await actionService.attemptWatchHistory(pendingReport)
            }
            if outcome.requiresRetry {
                FocusHistoryBackgroundScheduler.shared.schedule()
            }
        }
    }

    private func retryPendingWatchHistoryReports() {
        guard watchHistoryRetryTask == nil else {
            return
        }
        watchHistoryRetryGeneration &+= 1
        let generation = watchHistoryRetryGeneration
        watchHistoryRetryTask = Task {
            [
                weak self,
                actionService,
                playbackProgressStore,
                accountScopeProvider,
            ] in
            let accountScope = await accountScopeProvider()
            if accountScope != .anonymous, !Task.isCancelled {
                let outcome = await playbackProgressStore.drainPendingHistory(
                    accountScope: accountScope
                ) { pendingReport in
                    await actionService.attemptWatchHistory(pendingReport)
                }
                if outcome.requiresRetry {
                    FocusHistoryBackgroundScheduler.shared.schedule()
                }
            }
            guard let self, watchHistoryRetryGeneration == generation else {
                return
            }
            watchHistoryRetryTask = nil
        }
    }

    private var currentPlaybackMilliseconds: Int64 {
        hasPlaybackEnded ? playbackDurationMilliseconds : Self.milliseconds(from: player.currentTime())
    }

    var danmakuPlaybackPositionMilliseconds: Int64 {
        currentPlaybackMilliseconds
    }

    var subtitlePlaybackPositionMilliseconds: Int64 {
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

    private func setSubtitlesEnabled(_ enabled: Bool, persist: Bool) {
        let changed = isSubtitleEnabled != enabled
        isSubtitleEnabled = enabled
        if persist, changed {
            subtitlePreferenceChange(enabled, preferredSubtitleLanguageCode)
        }

        guard enabled else {
            subtitleDocumentGeneration &+= 1
            subtitleDocumentTask?.cancel()
            subtitleDocumentTask = nil
            return
        }
        guard let detail else {
            return
        }
        configureSubtitles(for: detail)
    }

    private func configureSubtitles(
        for detail: FocusVideoDetail,
        forceReload: Bool = false
    ) {
        guard let subtitleService else {
            subtitleLoadState = .unavailable
            return
        }
        let cid = selectedPageCID
            ?? detail.pages.first(where: { $0.cid == detail.cid })?.cid
            ?? detail.pages.first?.cid
            ?? detail.cid
        let context = SubtitleContext(aid: detail.aid, cid: cid)
        if subtitleContext != context || forceReload {
            resetSubtitleSession()
            subtitleContext = context
        }

        if !subtitleTracks.isEmpty {
            let track = selectedSubtitleTrack
                ?? preferredSubtitleTrack(in: subtitleTracks)
            selectedSubtitleTrackID = track?.id
            if isSubtitleEnabled, let track {
                loadSubtitleDocument(for: track)
            } else {
                subtitleLoadState = .ready
            }
            return
        }
        guard subtitleTracksTask == nil else {
            return
        }

        let generation = subtitleGeneration
        subtitleLoadState = .loadingTracks
        subtitleTracksTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                if self.subtitleGeneration == generation {
                    self.subtitleTracksTask = nil
                }
            }
            do {
                let tracks = try await subtitleService.fetchTracks(
                    aid: context.aid,
                    cid: context.cid
                )
                guard
                    !Task.isCancelled,
                    subtitleGeneration == generation,
                    subtitleContext == context
                else {
                    return
                }
                subtitleTracks = tracks
                guard !tracks.isEmpty else {
                    selectedSubtitleTrackID = nil
                    subtitleCues = []
                    subtitleLoadState = .unavailable
                    return
                }
                let track = preferredSubtitleTrack(in: tracks) ?? tracks[0]
                selectedSubtitleTrackID = track.id
                if isSubtitleEnabled {
                    loadSubtitleDocument(for: track)
                } else {
                    subtitleLoadState = .ready
                }
            } catch is CancellationError {
                return
            } catch {
                guard
                    !Task.isCancelled,
                    subtitleGeneration == generation,
                    subtitleContext == context
                else {
                    return
                }
                subtitleLoadState = .failed(error.localizedDescription)
            }
        }
    }

    private func loadSubtitleDocument(for track: FocusVideoSubtitleTrack) {
        guard isSubtitleEnabled, let subtitleService else {
            return
        }
        selectedSubtitleTrackID = track.id
        if let cachedCues = subtitleCueCache[track.id] {
            subtitleCues = cachedCues
            subtitleLoadState = .ready
            return
        }

        subtitleDocumentGeneration &+= 1
        let generation = subtitleDocumentGeneration
        subtitleDocumentTask?.cancel()
        subtitleLoadState = .loadingDocument
        subtitleCues = []
        subtitleDocumentTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                if self.subtitleDocumentGeneration == generation {
                    self.subtitleDocumentTask = nil
                }
            }
            do {
                let document = try await subtitleService.fetchDocument(for: track)
                guard
                    !Task.isCancelled,
                    subtitleDocumentGeneration == generation,
                    selectedSubtitleTrackID == track.id
                else {
                    return
                }
                subtitleCueCache[track.id] = document.cues
                subtitleCues = document.cues
                subtitleLoadState = .ready
            } catch is CancellationError {
                return
            } catch {
                guard
                    !Task.isCancelled,
                    subtitleDocumentGeneration == generation,
                    selectedSubtitleTrackID == track.id
                else {
                    return
                }
                subtitleCues = []
                subtitleLoadState = .failed(error.localizedDescription)
            }
        }
    }

    private func preferredSubtitleTrack(
        in tracks: [FocusVideoSubtitleTrack]
    ) -> FocusVideoSubtitleTrack? {
        let unlockedTracks = tracks.filter { !$0.isLocked }
        let candidates = unlockedTracks.isEmpty ? tracks : unlockedTracks
        let preferredCodes = [
            preferredSubtitleLanguageCode,
            Locale.preferredLanguages.first ?? "",
        ]
        .map { $0.replacingOccurrences(of: "_", with: "-").lowercased() }
        .filter { !$0.isEmpty }

        for code in preferredCodes {
            if let exact = candidates.first(where: {
                $0.languageCode.replacingOccurrences(of: "_", with: "-")
                    .lowercased() == code
            }) {
                return exact
            }
            let base = code.split(separator: "-").first.map(String.init) ?? code
            if let languageMatch = candidates.first(where: {
                $0.languageCode.replacingOccurrences(of: "_", with: "-")
                    .lowercased()
                    .split(separator: "-")
                    .first
                    .map(String.init) == base
            }) {
                return languageMatch
            }
        }
        return candidates.first
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

    private func cancelSubtitleRequests() {
        subtitleGeneration &+= 1
        subtitleDocumentGeneration &+= 1
        subtitleTracksTask?.cancel()
        subtitleDocumentTask?.cancel()
        subtitleTracksTask = nil
        subtitleDocumentTask = nil
        if subtitleTracks.isEmpty {
            subtitleLoadState = .idle
        } else if subtitleLoadState == .loadingDocument
            || subtitleLoadState == .loadingTracks
        {
            subtitleLoadState = .ready
        }
    }

    private func resetSubtitleSession() {
        cancelSubtitleRequests()
        subtitleContext = nil
        subtitleCueCache.removeAll()
        subtitleTracks = []
        selectedSubtitleTrackID = nil
        subtitleCues = []
        subtitleLoadState = .idle
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
        cancelCommentsTask()
        commentsNextCursor = nil
        consumedCommentCursors.removeAll()
        commentsErrorMessage = nil
        commentTotalCount = 0
        commentAccountScope = nil
        let generation = commentsGeneration
        commentsTask = Task {
            [weak self, detailService, accountScopeProvider] in
            guard let self else {
                return
            }
            defer {
                if self.commentsGeneration == generation {
                    self.commentsTask = nil
                }
            }
            do {
                let accountScope = await accountScopeProvider()
                try Task.checkCancellation()
                guard commentsGeneration == generation else {
                    return
                }

                let page = try await detailService.fetchCommentsPage(aid: detail.aid)
                try Task.checkCancellation()
                guard commentsGeneration == generation else {
                    return
                }

                let resultingScope = await accountScopeProvider()
                try Task.checkCancellation()
                guard commentsGeneration == generation else {
                    return
                }
                guard resultingScope == accountScope else {
                    invalidateCommentSessionForAccountChange(
                        detail: detail,
                        presentsError: false
                    )
                    return
                }

                var seen: Set<Int64> = []
                self.comments = page.comments.filter { seen.insert($0.id).inserted }
                self.commentTotalCount = page.totalCount
                self.commentsNextCursor = page.nextCursor
                self.commentAccountScope = accountScope
            } catch is CancellationError {
                return
            } catch {
                guard commentsGeneration == generation, !Task.isCancelled else { return }
                commentsErrorMessage = error.localizedDescription
            }
        }
    }

    private func initialCommentThreadState(
        for comment: FocusVideoComment
    ) -> CommentThreadState {
        let previewReplies = Array(comment.previewReplies.prefix(2))
        return CommentThreadState(
            replies: previewReplies,
            totalCount: max(comment.replies, Int64(previewReplies.count)),
            nextCursor: nil,
            isExpanded: false,
            isLoading: false,
            hasLoadedFirstPage: comment.replies <= Int64(previewReplies.count),
            errorMessage: nil
        )
    }

    private func resumeExpandedCommentReplyLoads() {
        guard commentAccountScope != nil else {
            return
        }
        let pendingComments = comments.filter { comment in
            guard let thread = commentThreadStates[comment.id] else {
                return false
            }
            return thread.isExpanded
                && !thread.hasLoadedFirstPage
                && !thread.isLoading
                && commentReplyTasks[comment.id] == nil
        }
        for comment in pendingComments {
            loadCommentReplies(for: comment, cursor: nil)
        }
    }

    private func loadCommentReplies(
        for comment: FocusVideoComment,
        cursor: FocusVideoCommentRepliesCursor?
    ) {
        guard let detail, let commentService else {
            var thread = commentThreadStates[comment.id]
                ?? initialCommentThreadState(for: comment)
            thread.errorMessage = "评论回复服务暂不可用"
            thread.isLoading = false
            commentThreadStates[comment.id] = thread
            return
        }
        guard let accountScope = commentAccountScope else {
            invalidateCommentSessionForAccountChange(
                detail: detail,
                presentsError: false
            )
            return
        }
        guard commentReplyTasks[comment.id] == nil else {
            return
        }

        var loadingThread = commentThreadStates[comment.id]
            ?? initialCommentThreadState(for: comment)
        loadingThread.isExpanded = true
        loadingThread.isLoading = true
        loadingThread.errorMessage = nil
        commentThreadStates[comment.id] = loadingThread

        let generation = commentThreadsGeneration
        commentReplyTasks[comment.id] = Task {
            [weak self, accountScopeProvider] in
            guard let self else {
                return
            }
            defer {
                if commentThreadsGeneration == generation {
                    commentReplyTasks[comment.id] = nil
                    if var thread = commentThreadStates[comment.id] {
                        thread.isLoading = false
                        commentThreadStates[comment.id] = thread
                    }
                }
            }
            do {
                let currentScope = await accountScopeProvider()
                try Task.checkCancellation()
                guard commentThreadsGeneration == generation else {
                    return
                }
                guard currentScope == accountScope else {
                    invalidateCommentSessionForAccountChange(
                        detail: detail,
                        presentsError: true
                    )
                    return
                }

                let page = try await commentService.fetchReplies(
                    aid: detail.aid,
                    rootCommentID: comment.id,
                    cursor: cursor
                )
                try Task.checkCancellation()
                guard commentThreadsGeneration == generation else {
                    return
                }

                let resultingScope = await accountScopeProvider()
                try Task.checkCancellation()
                guard commentThreadsGeneration == generation else {
                    return
                }
                guard resultingScope == accountScope else {
                    invalidateCommentSessionForAccountChange(
                        detail: detail,
                        presentsError: true
                    )
                    return
                }

                var thread = commentThreadStates[comment.id]
                    ?? initialCommentThreadState(for: comment)
                let existing = cursor == nil ? [] : thread.replies
                var seen = Set<Int64>()
                thread.replies = (existing + page.replies).filter {
                    seen.insert($0.id).inserted
                }
                thread.totalCount = max(
                    max(page.totalCount, comment.replies),
                    Int64(thread.replies.count)
                )
                thread.nextCursor = page.nextCursor
                thread.hasLoadedFirstPage = true
                thread.errorMessage = nil
                commentThreadStates[comment.id] = thread
            } catch is CancellationError {
                return
            } catch {
                guard
                    !Task.isCancelled,
                    commentThreadsGeneration == generation
                else {
                    return
                }
                var thread = commentThreadStates[comment.id]
                    ?? initialCommentThreadState(for: comment)
                thread.errorMessage = error.localizedDescription
                commentThreadStates[comment.id] = thread
            }
        }
    }

    private func invalidateCommentSessionForAccountChange(
        detail: FocusVideoDetail,
        presentsError: Bool
    ) {
        guard self.detail?.aid == detail.aid else {
            return
        }

        comments = []
        commentTotalCount = 0
        commentsNextCursor = nil
        isLoadingMoreComments = false
        resetCommentInteractionSession()
        if presentsError {
            actionErrorMessage = "登录账号已切换，评论已刷新，请重试。"
        }
        loadComments(for: detail)
    }

    private func loadInteractions(for detail: FocusVideoDetail) {
        cancelInteractionTask()
        let generation = interactionGeneration
        isLoadingInteractions = true
        interactionTask = Task { [weak self, actionService] in
            guard let self else {
                return
            }
            defer {
                if self.interactionGeneration == generation {
                    self.interactionTask = nil
                    self.isLoadingInteractions = false
                }
            }
            do {
                let state = try await actionService.fetchInteractionState(aid: detail.aid)
                guard !Task.isCancelled, interactionGeneration == generation else {
                    return
                }
                self.interactionState = state
            } catch {
                guard !Task.isCancelled, interactionGeneration == generation else {
                    return
                }
                self.actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func performAction(
        _ action: Action,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        actionTasks[action]?.cancel()
        let generation = (actionGenerations[action] ?? 0) &+ 1
        actionGenerations[action] = generation
        actionsInFlight.insert(action)
        actionErrorMessage = nil
        actionTasks[action] = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                if self.actionGenerations[action] == generation {
                    self.actionsInFlight.remove(action)
                    self.actionTasks[action] = nil
                }
            }
            do {
                try await operation()
            } catch is CancellationError {
                return
            } catch {
                guard
                    !Task.isCancelled,
                    actionGenerations[action] == generation
                else {
                    return
                }
                self.actionErrorMessage = error.localizedDescription
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
        guard
            isPlaybackSessionActive,
            hasPreparedPlayer,
            !isLoadingPlayback,
            player.currentItem != nil
        else {
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
        guard
            isPlaybackSessionActive,
            hasPreparedPlayer,
            !isLoadingPlayback,
            let item = player.currentItem
        else {
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

    static func waitUntilReadyToPlay(
        _ item: AVPlayerItem,
        timeout: Duration = .seconds(30)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        // AsyncPublisher can drop the ready transition between iterator demands.
        // Read the actual state so an already-ready item cannot wait forever.
        while true {
            try Task.checkCancellation()
            switch item.status {
            case .readyToPlay:
                return
            case .failed:
                if let error = item.error {
                    throw error
                }
                throw FocusVideoDetailService.ServiceError.invalidResponse
            case .unknown:
                break
            @unknown default:
                break
            }
            guard ContinuousClock.now < deadline else {
                throw PlaybackPreparationError.readinessTimedOut
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func seek(
        _ player: AVQueuePlayer,
        toMilliseconds milliseconds: Int64
    ) async throws {
        guard milliseconds > 0 else {
            return
        }
        let target = CMTime(value: milliseconds, timescale: 1_000)
        let finished = await withCheckedContinuation { continuation in
            player.seek(
                to: target,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { completed in
                continuation.resume(returning: completed)
            }
        }
        try Task.checkCancellation()
        guard finished else {
            throw FocusVideoDetailService.ServiceError.invalidResponse
        }
    }

    private func cancelTasks() {
        cancelLoadTask()
        cancelCommentsTask()
        cancelInteractionTask()
        cancelPlaybackTask()
        cancelActionTasks()
        cancelCommentReplyTasks()
        cancelCommentLikeTasks()
        cancelDanmakuRequests()
        cancelSubtitleRequests()
    }

    private func cancelLoadTask() {
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
    }

    private func cancelCommentsTask() {
        commentsGeneration &+= 1
        commentsTask?.cancel()
        commentsTask = nil
        isLoadingMoreComments = false
    }

    private func cancelCommentReplyTasks() {
        commentThreadsGeneration &+= 1
        commentReplyTasks.values.forEach { $0.cancel() }
        commentReplyTasks.removeAll()
        for commentID in Array(commentThreadStates.keys) {
            guard var thread = commentThreadStates[commentID] else {
                continue
            }
            thread.isLoading = false
            commentThreadStates[commentID] = thread
        }
    }

    private func cancelCommentLikeTasks() {
        for commentID in commentLikeTasks.keys {
            commentLikeGenerations[commentID] =
                (commentLikeGenerations[commentID] ?? 0) &+ 1
        }
        commentLikeTasks.values.forEach { $0.cancel() }
        commentLikeTasks.removeAll()
        commentLikeActionsInFlight.removeAll()
    }

    private func resetCommentInteractionSession() {
        cancelCommentReplyTasks()
        cancelCommentLikeTasks()
        commentThreadStates.removeAll()
        commentLikeOverrides.removeAll()
        commentAccountScope = nil
        // Keep per-comment generations monotonic. A cancelled task may finish
        // after a new session has started with the same comment identifier.
    }

    private func cancelInteractionTask() {
        interactionGeneration &+= 1
        interactionTask?.cancel()
        interactionTask = nil
    }

    private func cancelPlaybackTask() {
        if let firstFrameSpan { BiliPerformanceStore.shared.end(firstFrameSpan, outcome: .cancelled) }
        firstFrameSpan = nil
        readySurface = nil
        playbackGeneration &+= 1
        playbackTask?.cancel()
        playbackTask = nil
    }

    private func cancelActionTasks() {
        for action in actionTasks.keys {
            actionGenerations[action] = (actionGenerations[action] ?? 0) &+ 1
        }
        actionTasks.values.forEach { $0.cancel() }
        actionTasks.removeAll()
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
        let accountScope: FocusPlaybackAccountScope
        let aid: Int64
        let bvid: String
        let cid: Int64
        let positionMilliseconds: Int64

        var progressSeconds: Int64 {
            max(positionMilliseconds, 0) / 1_000
        }
    }

    private struct DanmakuContext: Equatable {
        let aid: Int64
        let cid: Int64
        let durationMilliseconds: Int64
    }

    private struct SubtitleContext: Equatable {
        let aid: Int64
        let cid: Int64
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

#if DEBUG
extension FocusNativeVideoViewModel {
    func installFixtureDetail(_ detail: FocusVideoDetail) {
        precondition(FocusTestRuntime.isRunningFixtures)
        cancelTasks()
        state = .loaded(detail)
        selectedPageCID = detail.cid
    }

    func installFixtureDanmakus(_ comments: [FocusVideoDanmaku]) {
        precondition(FocusTestRuntime.isRunningFixtures)
        cancelDanmakuRequests()
        danmakuContext = nil
        danmakus = comments
        danmakuLoadState = .ready
        isDanmakuEnabled = true
    }
}
#endif

enum FocusNativePlaybackFactory {
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
        async let videoTracksRequest = videoAsset.loadTracks(withMediaType: .video)
        async let audioTracksRequest = audioAsset.loadTracks(withMediaType: .audio)
        async let videoDurationRequest = videoAsset.load(.duration)
        async let audioDurationRequest = audioAsset.load(.duration)
        let (videoTracks, audioTracks, videoDuration, audioDuration) = try await (
            videoTracksRequest, audioTracksRequest, videoDurationRequest, audioDurationRequest
        )
        guard let sourceVideoTrack = videoTracks.first, let sourceAudioTrack = audioTracks.first else {
            throw FocusVideoDetailService.ServiceError.noStream
        }

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
    static func isPlaybackRequested(rate: Float, timeControlStatus: AVPlayer.TimeControlStatus) -> Bool {
        // pause() sets rate to zero before timeControlStatus necessarily leaves
        // .playing. Waiting, however, is an outstanding play request even when
        // no frames are advancing; tapping then must cancel it, not play again.
        rate > 0 || timeControlStatus == .waitingToPlayAtSpecifiedRate
    }

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

enum FocusNativeVideoFullscreenPolicy {
    static func orientation(for detail: FocusVideoDetail) -> UIInterfaceOrientationMask {
        guard detail.width > 0, detail.height > 0 else {
            return .landscape
        }
        return detail.width > detail.height ? .landscape : .portrait
    }
}

@MainActor
enum FocusNativeVideoOrientation {
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

enum FocusNativeVideoFormatting {
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
        value.rounded() == value ? "\(Int(value))x" : "\(value)x"
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
