#if canImport(UIKit)
import Combine
import FocusCore
import Foundation
import OSLog
import SwiftUI
import UIKit

@MainActor
final class FocusDynamicFeedViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded([DynamicCard])
        case loginRequired(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var knownAuthors: [DynamicCard.Author] = []
    @Published private(set) var selectedFilter: FocusDynamicFilterKind = .all
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshErrorMessage: String?
    @Published private(set) var appendErrorMessage: String?
    @Published private(set) var dataRevision = 0
    @Published private(set) var expansionStates: [String: ExpansionState] = [:]
    @Published private(set) var cacheMessage: String?
    private var pendingPage: DynamicFeedService.FeedPage?
    private var pendingPageSessionVersion: UInt64?
    private var pendingApplyScheduled = false
    private var authorKeys: Set<String> = []

    struct ExpansionState: Equatable {
        var textExpanded = false
        var imagesExpanded = false
        var contentSignature: Int
    }

    private(set) var scrollOffsetY: CGFloat = 0
    private(set) var scrollRestorationRevision = 0

    private let service: DynamicFeedService
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var loadMoreID: UUID?
    private var nextOffset: String?
    private var consumedOffsets: Set<String> = []
    private var generation = UUID()
    private var loadedSessionVersion: UInt64?
    private var requestSessionVersion: UInt64?
    private var appendSessionVersion: UInt64?
    private var isVisible = true
    private var isForeground = true
    private var automaticRefreshTask: Task<Void, Never>?
    private var lastRefreshAttempt: Date?
    private var requestPreservesReadingPosition = false
    private let now: () -> Date
    private let automaticRefreshInterval: TimeInterval
    private var expansionOrder: [String] = []
    private var displaySpan: BiliPerformanceSpan?
    private var displayGeneration: UUID?
    var hasMore: Bool { nextOffset != nil }
    var hasPendingUpdates: Bool { pendingPage != nil }
    var isActuallyVisible: Bool { isVisible && isForeground }
    let scrollAnchor = FocusDynamicFeedVisualAnchor()

    func prepareForDetailReturn(_ completion: @escaping (FocusDynamicReturnOutcome) -> Void) {
        guard let prepare = scrollAnchor.prepareReturn else { completion(.unavailable); return }
        prepare(completion)
    }

    func freezeForDetails() { scrollAnchor.freezeForDetails?() }
    func cancelDetailReturn() { scrollAnchor.cancelReturn?() }
    func finishDetailReturnNow() { scrollAnchor.forceReturn?() }

#if DEBUG
    // Fixture-only observation and seeding; normal launches cannot access user data through this seam.
    weak var fixtureAnchor: FocusDynamicFeedVisualAnchor?
    func installFixtureCards(_ cards: [DynamicCard]) {
        precondition(FocusTestRuntime.isRunningFixtures)
        suspend()
        state = .loaded(cards)
        nextOffset = nil
        loadedSessionVersion = service.sessionVersion
        isVisible = true
        lastRefreshAttempt = now()
    }
    func installFixturePendingPage(_ cards: [DynamicCard]) {
        precondition(FocusTestRuntime.isRunningFixtures)
        pendingPage = .init(cards: cards, nextOffset: nil)
        pendingPageSessionVersion = service.sessionVersion
        applyPendingPageIfPossible()
    }
#endif

    init(service: DynamicFeedService, now: @escaping () -> Date = Date.init,
         automaticRefreshInterval: TimeInterval = 60) {
        self.service = service
        self.now = now
        self.automaticRefreshInterval = automaticRefreshInterval
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
        automaticRefreshTask?.cancel()
    }

    func suspend() {
        generation = UUID()
        isVisible = false
        automaticRefreshTask?.cancel(); automaticRefreshTask = nil
        task?.cancel(); task = nil
        loadMoreTask?.cancel(); loadMoreTask = nil; loadMoreID = nil
        isLoadingMore = false
        isRefreshing = false
        requestPreservesReadingPosition = false
        if let displaySpan { BiliPerformanceStore.shared.end(displaySpan, outcome: .cancelled) }
        displaySpan = nil
        if case .loading = state { state = .idle }
    }

    func setVisibility(_ visible: Bool) {
        isVisible = visible
        if !visible {
            automaticRefreshTask?.cancel(); automaticRefreshTask = nil
            cancelAutomaticRequest()
            loadMoreTask?.cancel()
            loadMoreTask = nil
            loadMoreID = nil
            isLoadingMore = false
        } else {
            startAutomaticRefreshLoop()
        }
    }

    func setApplicationActive(_ active: Bool) {
        isForeground = active
        if active {
            guard isVisible else { return }
            loadIfNeeded()
        } else {
            automaticRefreshTask?.cancel(); automaticRefreshTask = nil
            cancelAutomaticRequest()
            loadMoreTask?.cancel(); loadMoreTask = nil; loadMoreID = nil
            isLoadingMore = false
        }
    }

    private func cancelAutomaticRequest() {
        guard requestPreservesReadingPosition, task != nil else { return }
        task?.cancel(); task = nil
        generation = UUID()
        isRefreshing = false
        requestPreservesReadingPosition = false
        if case .loading = state { state = .idle }
    }

    private func startAutomaticRefreshLoop() {
        guard isVisible, isForeground, automaticRefreshTask == nil else { return }
        let interval = automaticRefreshInterval
        let remaining = lastRefreshAttempt.map { interval - now().timeIntervalSince($0) } ?? interval
        // Re-entering at second 59 must not postpone a due refresh by another
        // full minute. Subsequent ticks stay paced even when a request is busy.
        let initialDelay = remaining > 0 ? remaining : interval
        automaticRefreshTask = Task { [weak self] in
            var delay = initialDelay
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard let self else { return }
                self.refreshAutomaticallyIfDue()
                delay = interval
            }
        }
    }

    func refreshAutomaticallyIfDue() {
        guard isVisible, isForeground, task == nil, !isLoadingMore else { return }
        applyPendingPageIfPossible()
        guard lastRefreshAttempt.map({ now().timeIntervalSince($0) >= automaticRefreshInterval }) ?? true else { return }
        switch state {
        case .loaded, .failed:
            startReload(forceRefresh: true, preservesReadingPosition: true)
        case .idle, .loading, .loginRequired:
            break
        }
    }

    func resetForSessionChange() {
        suspend()
        state = .idle
        knownAuthors = []
        nextOffset = nil
        consumedOffsets.removeAll()
        loadedSessionVersion = nil
        expansionStates.removeAll()
        expansionOrder.removeAll()
        refreshErrorMessage = nil
        appendErrorMessage = nil
        pendingPage = nil
        pendingPageSessionVersion = nil
        lastRefreshAttempt = nil
        authorKeys.removeAll()
        dataRevision &+= 1
        resetScrollPosition()
        // Cache keys include account and session generation. A detached clear
        // here could invalidate the new account's first in-flight request.
    }

    func reconcileSessionVersion(_ version: UInt64) {
        guard version == service.sessionVersion else { return }
        if pendingPageSessionVersion != version {
            pendingPage = nil
            pendingPageSessionVersion = nil
        }
        if case .loaded = state { loadedSessionVersion = version }
        // A harmless Cookie update still fences requests from the old snapshot.
        // Restart only interrupted work; never clear the confirmed account's rows.
        if task != nil, requestSessionVersion != version {
            startReload(forceRefresh: false, preservesReadingPosition: requestPreservesReadingPosition)
        } else if loadMoreTask != nil, appendSessionVersion != version {
            loadMoreTask?.cancel(); loadMoreTask = nil; loadMoreID = nil
            isLoadingMore = false
            loadMore()
        } else if case .loading = state, task == nil, isVisible {
            startReload(forceRefresh: false)
        }
    }

    func markDisplayed() {
        if isVisible, isForeground, pendingPage != nil, !pendingApplyScheduled {
            pendingApplyScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                pendingApplyScheduled = false
                applyPendingPageIfPossible()
            }
        }
        guard isVisible, case let .loaded(cards) = state, !cards.isEmpty,
              let span = displaySpan, displayGeneration == generation else { return }
        BiliPerformanceStore.shared.end(span)
        displaySpan = nil
    }

    func expansionBinding(for card: DynamicCard, images: Bool) -> Binding<Bool> {
        let signature = Self.contentSignature(card)
        return Binding(
            get: { [weak self] in
                guard let state = self?.expansionStates[card.id], state.contentSignature == signature else { return false }
                return images ? state.imagesExpanded : state.textExpanded
            },
            set: { [weak self] expanded in
                guard let self else { return }
                var state = expansionStates[card.id].flatMap { $0.contentSignature == signature ? $0 : nil }
                    ?? ExpansionState(contentSignature: signature)
                // Expanding content is an explicit reading choice, just like a
                // pan. Do not let a previous detail-return anchor pull another
                // card back into place while this card opens or folds.
                if (images ? state.imagesExpanded : state.textExpanded) != expanded {
                    scrollAnchor.userWillChangeLayout?()
                }
                if images { state.imagesExpanded = expanded } else { state.textExpanded = expanded }
                expansionStates[card.id] = state
                expansionOrder.removeAll { $0 == card.id }
                expansionOrder.append(card.id)
                while expansionOrder.count > 512, let oldest = expansionOrder.first {
                    expansionOrder.removeFirst()
                    expansionStates[oldest] = nil
                }
            }
        )
    }

    private static func contentSignature(_ card: DynamicCard) -> Int {
        var hash = Hasher()
        hash.combine(card.text)
        hash.combine(card.coverURLs)
        return hash.finalize()
    }

    func loadIfNeeded() {
        isVisible = true
        startAutomaticRefreshLoop()
        guard case .idle = state else {
            refreshAutomaticallyIfDue()
            return
        }

        startReload(forceRefresh: false)
    }

    func reload() {
        resetScrollPosition()
        startReload(forceRefresh: true)
    }

    private func applyPendingPageIfPossible() {
        guard isVisible, isForeground, let page = pendingPage,
              pendingPageSessionVersion == service.sessionVersion else { return }
        let update = { [self] in
            loadMoreTask?.cancel(); loadMoreTask = nil; loadMoreID = nil
            isLoadingMore = false
            publishFirstPage(page)
            loadedSessionVersion = service.sessionVersion
        }
        // Reading owns the visible list. Fresh heads are published automatically
        // once the reader returns to the top and the gesture has ended.
        if let apply = scrollAnchor.applyContentUpdate {
            _ = apply(update)
        } else if scrollOffsetY <= 1 {
            update()
        }
    }

    func clearCachedFeed() {
        // Cancel writers before clearing. The store revision also fences any
        // already suspended persistence operation.
        let wasVisible = isVisible
        suspend()
        isVisible = wasVisible
        let clearGeneration = generation
        pendingPage = nil
        pendingPageSessionVersion = nil
        task = Task { [weak self, service] in
            do {
                try await service.clearPersistentCache()
                if self?.generation == clearGeneration { self?.cacheMessage = "动态缓存已清除；当前已显示内容保留" }
            } catch {
                if self?.generation == clearGeneration { self?.cacheMessage = "清除动态缓存失败：\(error.localizedDescription)" }
            }
            if self?.generation == clearGeneration { self?.task = nil }
        }
    }

    private func startReload(forceRefresh: Bool, preservesReadingPosition: Bool = false) {
        requestSessionVersion = service.sessionVersion
        requestPreservesReadingPosition = preservesReadingPosition
        lastRefreshAttempt = now()
        task?.cancel()
        loadMoreTask?.cancel(); loadMoreTask = nil; loadMoreID = nil
        generation = UUID()
        let requestID = generation
        task = Task { [weak self] in
            await self?.performReload(forceRefresh: forceRefresh, requestID: requestID,
                                      preservesReadingPosition: preservesReadingPosition)
        }
    }

    func refresh() async {
        resetScrollPosition()
        startReload(forceRefresh: true)
        await task?.value
    }

    func loadMoreIfNeeded(currentCardID: String) {
        guard case let .loaded(cards) = state, shouldLoadMore(after: currentCardID, in: cards),
              appendErrorMessage == nil else { return }
        loadMore()
    }

    /// Also serves filtered-empty feeds: one explicit click fetches one page,
    /// rather than scanning an unbounded number of invisible pages.
    func loadMore() {
        guard isVisible, isForeground, case let .loaded(displayedCards) = state, !isLoadingMore,
              !isRefreshing, task == nil, let offset = nextOffset,
              !offset.isEmpty, !consumedOffsets.contains(offset) else { return }
        isLoadingMore = true
        appendErrorMessage = nil
        let requestID = generation
        let appendID = UUID()
        appendSessionVersion = service.sessionVersion
        loadMoreID = appendID
        loadMoreTask = Task { [weak self, service] in
            guard let self else { return }
            let version = await service.prepareSessionVersion()
            let cacheRevision = await service.snapshotWriteRevision()
            defer {
                if generation == requestID, loadMoreID == appendID {
                    isLoadingMore = false; loadMoreTask = nil; loadMoreID = nil
                }
            }
            do {
                let page = try await service.fetchFollowingFeedPage(offset: offset)
                guard isCurrent(requestID, version: version), loadMoreID == appendID, isVisible else { return }
                consumedOffsets.insert(offset)
                let merged = mergeCards(displayedCards, with: page.cards)
                nextOffset = validNextOffset(page.nextOffset)
                mergeAdditionalAuthors(from: page.cards)
                state = .loaded(merged)
                loadedSessionVersion = version
                do {
                    if !hasPendingUpdates {
                        try await service.saveSnapshot(cards: merged, nextOffset: nextOffset, version: version, revision: cacheRevision)
                    }
                }
                catch { if isCurrent(requestID, version: version) { cacheMessage = "动态缓存保存失败：\(error.localizedDescription)" } }
            } catch {
                guard generation == requestID, loadMoreID == appendID, !Task.isCancelled else { return }
                if case DynamicFeedService.ServiceError.loginRequired = error,
                   service.sessionReadiness == .expired || version == service.sessionVersion {
                    nextOffset = nil
                    state = .loginRequired(error.localizedDescription)
                    knownAuthors = []
                } else if version == service.sessionVersion {
                    appendErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func validNextOffset(_ candidate: String?) -> String? {
        guard let candidate, !candidate.isEmpty, !consumedOffsets.contains(candidate) else { return nil }
        return candidate
    }

    private func isCurrent(_ requestID: UUID, version: UInt64) -> Bool {
        !Task.isCancelled && generation == requestID && service.sessionVersion == version
    }

    func selectFilter(_ filter: FocusDynamicFilterKind) {
        guard selectedFilter != filter else {
            return
        }
        selectedFilter = filter
        loadMoreTask?.cancel(); loadMoreTask = nil; loadMoreID = nil
        task?.cancel(); task = nil
        generation = UUID()
        isLoadingMore = false
        isRefreshing = false
        appendErrorMessage = nil
        resetScrollPosition()
        if case .loading = state { state = .idle; loadIfNeeded() }
    }

    func updateScrollOffset(_ offsetY: CGFloat) {
        scrollOffsetY = max(offsetY, 0)
        if scrollOffsetY <= 1, pendingPage != nil { markDisplayed() }
    }

    private func resetScrollPosition() {
        scrollOffsetY = 0
        scrollRestorationRevision &+= 1
        scrollAnchor.clear()
        // Revoke restoration synchronously with the user's refresh/filter
        // action, not one later SwiftUI body update after stale work can land.
        scrollAnchor.invalidateReturnScope?()
    }

    private func shouldLoadMore(after currentCardID: String, in cards: [DynamicCard]) -> Bool {
        guard let currentIndex = cards.firstIndex(where: { $0.id == currentCardID }) else {
            return false
        }

        return currentIndex >= max(cards.count - 4, 0)
    }

    private func performReload(forceRefresh: Bool, requestID: UUID, preservesReadingPosition: Bool) async {
        isLoadingMore = false
        var retainedCards: [DynamicCard]?
        if case let .loaded(cards) = state { retainedCards = cards } else { retainedCards = nil }
        isRefreshing = retainedCards != nil
        refreshErrorMessage = nil
        appendErrorMessage = nil
        if retainedCards == nil { state = .loading }
        let span = BiliPerformanceStore.shared.begin(.dynamicLoad, correlationID: requestID)
        let firstPage = BiliPerformanceStore.shared.begin(.dynamicFirstPage, correlationID: requestID)
        if let displaySpan { BiliPerformanceStore.shared.end(displaySpan, outcome: .cancelled) }
        displaySpan = BiliPerformanceStore.shared.begin(.dynamicDisplayed, correlationID: requestID)
        // Retained rows during refresh are not the newly fetched first page.
        displayGeneration = nil
        let version = await service.prepareSessionVersion()
        let cacheRevision = await service.snapshotWriteRevision()
        var restoredSnapshot = false
        if retainedCards == nil, !forceRefresh, let cached = await service.cachedSnapshot(),
           isCurrent(requestID, version: version) {
            publishFirstPage(.init(cards: cached.cards, nextOffset: cached.nextOffset))
            loadedSessionVersion = version
            retainedCards = cached.cards
            restoredSnapshot = true
            isRefreshing = true
            displayGeneration = requestID
        }
        defer {
            if generation == requestID { isRefreshing = false; task = nil; requestPreservesReadingPosition = false }
        }
        do {
            let page = if forceRefresh || restoredSnapshot {
                try await service.refreshFollowingFeedPage()
            } else {
                try await service.fetchFollowingFeedPage()
            }
            guard isCurrent(requestID, version: version) else {
                BiliPerformanceStore.shared.end(span, outcome: .stale)
                BiliPerformanceStore.shared.end(firstPage, outcome: .stale)
                return
            }
            let cards = mergeCards([], with: page.cards)
            loadedSessionVersion = version
            if restoredSnapshot || preservesReadingPosition {
                pendingPage = page
                pendingPageSessionVersion = version
                applyPendingPageIfPossible()
                displayGeneration = requestID
            } else {
                publishFirstPage(page)
                displayGeneration = requestID
            }
            do { try await service.saveSnapshot(cards: cards, nextOffset: page.nextOffset, version: version, revision: cacheRevision) }
            catch { if isCurrent(requestID, version: version) { cacheMessage = "动态缓存保存失败：\(error.localizedDescription)" } }
            BiliPerformanceStore.shared.end(firstPage, count: cards.count)
            BiliPerformanceStore.shared.end(span)
            // Pagination is deliberately not awaited here. Actual visible-row
            // callbacks or the explicit continuation button request later pages.
        } catch {
            let outcome: BiliPerformanceOutcome = error is CancellationError ? .cancelled : .failure
            BiliPerformanceStore.shared.end(span, outcome: outcome)
            BiliPerformanceStore.shared.end(firstPage, outcome: outcome)
            guard generation == requestID, !Task.isCancelled else { return }
            if let displaySpan { BiliPerformanceStore.shared.end(displaySpan, outcome: outcome) }
            displaySpan = nil
            if case DynamicFeedService.ServiceError.loginRequired = error,
               service.sessionReadiness == .expired || version == service.sessionVersion {
                nextOffset = nil
                knownAuthors = []
                state = .loginRequired(error.localizedDescription)
            } else if version == service.sessionVersion {
                if retainedCards != nil { refreshErrorMessage = error.localizedDescription }
                else { state = .failed(error.localizedDescription) }
            }
        }
    }

    private func mergeCards(_ existingCards: [DynamicCard], with newCards: [DynamicCard]) -> [DynamicCard] {
        var mergedCards = existingCards
        var seen = Set(existingCards.map(\.id))

        for card in newCards where seen.insert(card.id).inserted {
            mergedCards.append(card)
        }

        return mergedCards
    }

    private func publishFirstPage(_ page: DynamicFeedService.FeedPage) {
        let cards = mergeCards([], with: page.cards)
        pendingPage = nil
        pendingPageSessionVersion = nil
        consumedOffsets.removeAll()
        nextOffset = validNextOffset(page.nextOffset)
        knownAuthors = []
        authorKeys.removeAll()
        mergeAdditionalAuthors(from: cards)
        let ids = Set(cards.map(\.id))
        expansionStates = expansionStates.filter { ids.contains($0.key) }
        expansionOrder.removeAll { !ids.contains($0) }
        dataRevision &+= 1
        state = .loaded(cards)
    }

    private func mergeAdditionalAuthors(from cards: [DynamicCard]) {
        var additions: [DynamicCard.Author] = []
        for card in cards {
            let key = card.author.mid > 0 ? "mid:\(card.author.mid)" : "name:\(card.author.name)"
            if authorKeys.insert(key).inserted { additions.append(card.author) }
        }
        if !additions.isEmpty { knownAuthors += additions }
    }
}

struct FocusDynamicFeedView: View {
    @ObservedObject var viewModel: FocusDynamicFeedViewModel
    @ObservedObject var settingsStore: FocusSettingsStore
    let isActive: Bool
    let searchPrompt: String
    let onOpenCard: (DynamicCard) -> Void
    let onOpenUser: (Int64) -> Void
    let onOpenLogin: () -> Void
    let onSearch: () -> Void
    @State private var galleryRequest: FocusImageGalleryRequest?
    private var scrollAnchor: FocusDynamicFeedVisualAnchor { viewModel.scrollAnchor }
    @State private var prefetchCardID: String?
    var body: some View {
        content
            .task(id: isActive) {
                scrollAnchor.onVisibleCard = { [weak viewModel] in viewModel?.markDisplayed() }
                scrollAnchor.onInteractionEnded = { [weak viewModel] in viewModel?.markDisplayed() }
#if DEBUG
                if FocusTestRuntime.isRunningFixtures { viewModel.fixtureAnchor = scrollAnchor }
#endif
            }
            .onChange(of: viewModel.dataRevision) { _ in scrollAnchor.clear() }
            .onChange(of: galleryRequest != nil) { covered in
                viewModel.setVisibility(isActive && !covered)
                if isActive && !covered { viewModel.loadIfNeeded() }
            }
            .fullScreenCover(item: $galleryRequest) { request in
                FocusImageGalleryView(request: request)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载关注动态…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .loaded(cards):
            let filteredCards = visibleCards(from: cards)
            ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 12) {
                    FocusSearchQueryButton(
                        title: searchPrompt,
                        inactiveAccessorySystemImage: "chevron.right",
                        action: onSearch
                    )

                    Picker(
                        "动态分类",
                        selection: Binding(
                            get: { viewModel.selectedFilter },
                            set: { filter in
                                viewModel.selectFilter(filter)
                            }
                        )
                    ) {
                        ForEach(FocusDynamicFilterKind.allCases, id: \.self) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    if filteredCards.isEmpty {
                        VStack(spacing: 12) {
                            Text("暂无可显示的关注动态")
                                .font(.headline)

                            Text("当前筛选条件下没有可显示的动态。你可以切换分类，或在设置里调整每个 UP 主的显示类别。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            if viewModel.hasMore {
                                Button("继续加载", action: viewModel.loadMore)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(viewModel.isLoadingMore || !isActive)
                            } else {
                                Button("重新加载", action: viewModel.reload)
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                    } else {
                        ForEach(filteredCards) { card in
                            FocusDynamicCardView(
                                card: card,
                                areImagesExpanded: viewModel.expansionBinding(for: card, images: true),
                                isTextExpanded: viewModel.expansionBinding(for: card, images: false),
                                onOpenCard: {
                                    scrollAnchor.capture(preferredID: card.id)
                                    onOpenCard(card)
                                },
                                onOpenUser: { mid in
                                    scrollAnchor.capture()
                                    onOpenUser(mid)
                                },
                                onOpenImage: { index in
                                    galleryRequest = FocusImageGalleryRequest(
                                        urls: card.coverURLs,
                                        initialIndex: index,
                                        referer: card.targetURL.absoluteString
                                    )
                                }
                            )
                            .overlay(alignment: .topLeading) {
                                Color.clear
                                    .frame(width: 1, height: FocusDynamicFeedVisualAnchor.materializationMarkerHeight)
                                    .id(card.id)
                                    .allowsHitTesting(false)
                            }
                            .focusDynamicFeedAnchor(id: card.id, anchor: scrollAnchor)
                            .onAppear {
                                if viewModel.isActuallyVisible {
                                    prefetchCardID = card.id
                                    viewModel.loadMoreIfNeeded(currentCardID: card.id)
                                }
                            }
                        }

                    }
                    if viewModel.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    if let message = viewModel.appendErrorMessage {
                        VStack(spacing: 6) {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                            Button("重试加载更多", action: viewModel.loadMore)
                        }
                    } else if viewModel.hasMore && !viewModel.isLoadingMore && !filteredCards.isEmpty {
                        Button("加载更多", action: viewModel.loadMore).disabled(!isActive)
                    }
                    if let message = viewModel.refreshErrorMessage {
                        Text("刷新失败：\(message)；下拉可重试")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 126)
                .coordinateSpace(name: FocusDynamicFeedVisualAnchor.coordinateSpace)
                .background {
                    FocusDynamicFeedScrollBridge(
                        offsetY: viewModel.scrollOffsetY,
                        restorationRevision: viewModel.scrollRestorationRevision,
                        isActive: isActive,
                        visualAnchor: scrollAnchor,
                        onOffsetChange: { offsetY in
                            viewModel.updateScrollOffset(offsetY)
                        }
                    )
                    .frame(width: 1, height: 1)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .id("dynamic-feed-scroll")
            .refreshable {
                await viewModel.refresh()
            }
            .task(id: ImageWorkID(active: isActive, ids: prefetchCards(from: filteredCards).map(\.id))) {
                guard viewModel.isActuallyVisible else { return }
                await prefetchImages(for: prefetchCards(from: filteredCards))
            }
            .onAppear {
                scrollAnchor.updateData(ids: Set(filteredCards.map(\.id)), revision: viewModel.dataRevision)
                scrollAnchor.materialize = { id, point in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    // The tiny top marker expresses the same saved position as
                    // UIKit, independent of a long or newly measured row height.
                    withTransaction(transaction) {
                        reader.scrollTo(id, anchor: point)
                    }
                }
            }
            .onChange(of: filteredCards.map(\.id)) { ids in
                scrollAnchor.updateData(ids: Set(ids), revision: viewModel.dataRevision)
            }
            }

        case let .loginRequired(message):
            FocusLoginRequiredView(
                title: "需要登录",
                message: "\(message)\n先点“去登录”，网页登录完成后再回来刷新。",
                reloadTitle: "重新检测登录态",
                reloadAction: viewModel.reload,
                loginAction: onOpenLogin
            )

        case let .failed(message):
            FocusStateView(
                title: "动态加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )
        }
    }

    private struct ImageWorkID: Hashable { let active: Bool; let ids: [String] }

    private func prefetchCards(from cards: [DynamicCard]) -> [DynamicCard] {
        let index = prefetchCardID.flatMap { id in cards.firstIndex { $0.id == id } } ?? 0
        return Array(cards.dropFirst(index).prefix(8))
    }

    private func prefetchImages(for cards: [DynamicCard]) async {
        let urls = cards.flatMap { card in
            ([card.author.avatarURL] + Array(card.coverURLs.prefix(2))).compactMap { $0 }
        }
        await FocusRemoteImageLoader.prefetch(urls: urls, referer: "https://t.bilibili.com/")
    }

    private func visibleCards(from cards: [DynamicCard]) -> [DynamicCard] {
        cards.filter { card in
            let authorKinds = settingsStore.dynamicKinds(for: card.author)
            let normalizedKind = normalizedFilterKind(for: card)
            guard authorKinds.contains(normalizedKind) else {
                return false
            }
            switch viewModel.selectedFilter {
            case .all:
                return true
            case .video:
                return normalizedKind == .video
            case .articleLike:
                return normalizedKind == .articleLike
            }
        }
    }

    private func normalizedFilterKind(for card: DynamicCard) -> FocusDynamicFilterKind {
        switch card.kind {
        case .video:
            return .video
        case .text, .image, .articleLike:
            return .articleLike
        }
    }
}

enum FocusDynamicFeedScrollRestorationPolicy {
    struct Placement: Equatable {
        let contentOffsetY: CGFloat
        let normalizedOffsetY: CGFloat
        let reachedTarget: Bool
    }

    static func shouldPersistObservedOffset(
        isTracking: Bool,
        isDragging: Bool,
        isDecelerating: Bool,
        isPanActive: Bool
    ) -> Bool {
        isTracking || isDragging || isDecelerating || isPanActive
    }

    static func normalizedOffset(contentOffsetY: CGFloat, minimumY: CGFloat) -> CGFloat {
        max(contentOffsetY - minimumY, 0)
    }

    static func placement(
        requestedOffsetY: CGFloat,
        minimumY: CGFloat,
        maximumY: CGFloat
    ) -> Placement {
        let normalizedRequest = max(requestedOffsetY, 0)
        let maximumOffsetY = max(maximumY - minimumY, 0)
        let restoredOffsetY = min(normalizedRequest, maximumOffsetY)
        return Placement(
            contentOffsetY: minimumY + restoredOffsetY,
            normalizedOffsetY: restoredOffsetY,
            reachedTarget: normalizedRequest <= maximumOffsetY + 1
        )
    }
}

/// Keeps the selected card at the same distance from the unobscured viewport top.
/// Card positions are measured in the content coordinate space, so scrolling
/// itself does not invalidate them. Layout updates replace them before restoring.
enum FocusDynamicReturnOutcome: Equatable {
    case preserved, aligned, anchorMissing, timedOut, scopeChanged, clamped, gesture, userOverride, cancelled, unavailable
}

@MainActor
final class FocusDynamicFeedVisualAnchor {
    nonisolated static let coordinateSpace = "focus-dynamic-feed-content"
    nonisolated static let materializationMarkerHeight: CGFloat = 1

    nonisolated static func materializationPoint(viewportY: CGFloat, viewportHeight: CGFloat) -> UnitPoint? {
        guard viewportHeight > materializationMarkerHeight else { return nil }
        return UnitPoint(x: 0, y: viewportY / (viewportHeight - materializationMarkerHeight))
    }

    struct Snapshot {
        let id: String
        let viewportY: CGFloat
        let dataRevision: Int
        let geometryVersion: UInt64
    }

    private var frames: [String: CGRect] = [:]
    private var frameOwners: [String: UUID] = [:]
    private struct Surface { weak var view: FocusDynamicAnchorSurfaceView? }
    private var surfaces: [String: Surface] = [:]
    private var usesLiveSurfaces = false
    private var surfaceSerial = 0
    private(set) var geometryVersion: UInt64 = 0
    private(set) var dataRevision = 0
    private var validIDs: Set<String>?
    var prepareReturn: ((@escaping (FocusDynamicReturnOutcome) -> Void) -> Void)?
    var freezeForDetails: (() -> Void)?
    var cancelReturn: (() -> Void)?
    var forceReturn: (() -> Void)?
    var invalidateReturnScope: (() -> Void)?
    var userWillChangeLayout: (() -> Void)?
    var applyContentUpdate: ((() -> Void) -> Bool)?
    var onInteractionEnded: (() -> Void)?
    var prepareLayoutForReturn: (() -> Bool)?
    var finishLayoutForReturn: (() -> Void)?
    var isReturnLayoutReady = true
    var materialize: ((String, UnitPoint) -> Void)?

    var targetIsInData: Bool {
        guard let snapshot else { return false }
        return snapshot.dataRevision == dataRevision && (validIDs?.contains(snapshot.id) ?? true)
    }

    func updateData(ids: Set<String>, revision: Int) {
        validIDs = ids
        dataRevision = revision
        geometryDidChange()
    }

    func invalidateGeometry() {
        geometryVersion &+= 1
        // An old CGRect never qualifies as a measurement of this layout.
        surfaces.values.forEach { $0.view?.setNeedsLayout() }
        geometryDidChange()
    }

    fileprivate func nextSurfaceSerial() -> Int { surfaceSerial += 1; return surfaceSerial }
    fileprivate func registerSurface(_ view: FocusDynamicAnchorSurfaceView) {
        guard !view.retired, view.window != nil else { return }
        usesLiveSurfaces = true
        if let existing = surfaces[view.dynamicID]?.view, existing !== view {
            guard existing.serial < view.serial else { return }
            existing.retired = true
        }
        surfaces[view.dynamicID] = Surface(view: view)
    }
    fileprivate func removeSurface(_ view: FocusDynamicAnchorSurfaceView) {
        guard surfaces[view.dynamicID]?.view === view else { return }
        surfaces[view.dynamicID] = nil
        geometryDidChange()
    }
    private(set) var snapshot: Snapshot?
    weak var scrollView: UIScrollView?
    var onGeometryChange: (() -> Void)?
    var onVisibleCard: (() -> Void)?
    private var geometryUpdatePending = false
#if DEBUG
    weak var fixtureCoordinator: FocusDynamicFeedScrollBridge.Coordinator?
#endif

    func updateFrame(_ frame: CGRect, id: String) {
        frames[id] = frame
        if let scrollView, scrollView.window != nil {
            let top = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            let bottom = scrollView.bounds.maxY - scrollView.adjustedContentInset.bottom
            if frame.height > 0, frame.maxY > top, frame.minY < bottom { onVisibleCard?() }
        }
        geometryDidChange()
    }

    func registerFrame(_ frame: CGRect, id: String, owner: UUID) {
        frameOwners[id] = owner
        updateFrame(frame, id: id)
    }

    func updateFrame(_ frame: CGRect, id: String, owner: UUID) {
        // Geometry may arrive after onDisappear while a platform view remains
        // cached. Only onAppear can re-activate an owner. The marker retains
        // pre-appearance measurements and registers that latest sample itself.
        guard frameOwners[id] == owner else { return }
        updateFrame(frame, id: id)
    }

    func removeFrame(id: String, owner: UUID) {
        // A LazyVStack replacement can appear before the former row disappears.
        // Late cleanup/geometry from the former instance must not delete or
        // overwrite the replacement's measurement for the same stable ID.
        guard frameOwners[id] == owner else { return }
        removeFrame(id: id)
    }

    func removeFrame(id: String) {
        frames.removeValue(forKey: id)
        frameOwners.removeValue(forKey: id)
    }

    func frame(for id: String) -> CGRect? {
        guard usesLiveSurfaces else { return frames[id] } // Injectable UIKit test geometry.
        guard frameOwners[id] != nil, let view = surfaces[id]?.view, !view.retired,
              let scrollView, view.window != nil, view.window === scrollView.window,
              view.isDescendant(of: scrollView), view.bounds.height > 0, view.bounds.width > 0,
              view.layoutGeneration == geometryVersion else { return nil }
        // A lazy row's UIKit host can be hidden instead of removed from its
        // window (observed on iOS 26). Window membership is not layout presence.
        // Stop at the feed scroll view: the separate detail cover must not
        // invalidate otherwise active rows underneath it.
        var ancestor: UIView? = view
        while let current = ancestor, current !== scrollView {
            guard !current.isHidden, current.alpha > 0 else { return nil }
            ancestor = current.superview
        }
        return view.convert(view.bounds, to: scrollView)
    }

    func capture(preferredID: String? = nil) {
        guard let scrollView, scrollView.window != nil else { return }
        let top = scrollView.bounds.minY + scrollView.adjustedContentInset.top
        let bottom = scrollView.bounds.maxY - scrollView.adjustedContentInset.bottom
        let visible: [(String, CGRect)] = Set(frames.keys).union(surfaces.keys).compactMap { id in
            guard let frame = frame(for: id), frame.height > 0, frame.maxY > top, frame.minY < bottom,
                  validIDs?.contains(id) ?? true else { return nil }
            return (id, frame)
        }
        let selected = visible.first { $0.0 == preferredID }
            ?? visible.min { $0.1.minY < $1.1.minY }
        guard let (id, frame) = selected else { return }
        snapshot = Snapshot(id: id, viewportY: frame.minY - top,
                            dataRevision: dataRevision, geometryVersion: geometryVersion)
        trace("capture", frameY: frame.minY - top)
    }

    func clear() {
        snapshot = nil
    }

    var targetNormalizedOffset: CGFloat? {
        guard let snapshot, targetIsInData, let frame = frame(for: snapshot.id), frame.height > 0 else { return nil }
        // normalized offset = contentOffset.y + adjustedContentInset.top
        return frame.minY - snapshot.viewportY
    }

    func geometryDidChange() {
        guard !geometryUpdatePending else { return }
        geometryUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.geometryUpdatePending = false
            self.onGeometryChange?()
        }
    }

    func trace(_ event: String, frameY: CGFloat? = nil) {
        guard let scrollView else { return }
        let y = frameY ?? targetNormalizedOffset.map {
            $0 + (snapshot?.viewportY ?? 0) - scrollView.contentOffset.y - scrollView.adjustedContentInset.top
        } ?? 0
        Logger(subsystem: "BilibiliFocus", category: "DynamicScroll").debug(
            "\(event, privacy: .public) y=\(Double(y)) offset=\(Double(scrollView.contentOffset.y)) height=\(Double(scrollView.contentSize.height)) inset=\(Double(scrollView.adjustedContentInset.top))"
        )
    }
}

extension View {
    func focusDynamicFeedAnchor(id: String, anchor: FocusDynamicFeedVisualAnchor) -> some View {
        background { FocusDynamicFeedAnchorMarker(id: id, anchor: anchor) }
            .background { FocusDynamicLiveAnchorMarker(id: id, anchor: anchor) }
#if DEBUG
            .background {
                if FocusTestRuntime.isRunningFixtures { FocusDynamicFixtureCardProbe(id: id) }
            }
#endif
    }
}

#if DEBUG
/// An independent UIKit surface for tests; it does not supply recovery geometry.
private struct FocusDynamicFixtureCardProbe: UIViewRepresentable {
    let id: String
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = "focus-fixture-card:" + id
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        view.accessibilityIdentifier = "focus-fixture-card:" + id
    }
}
#endif

/// Live UIKit geometry is independent of LazyVStack's estimated content-space
/// CGRect preferences. Only weak references to mounted rows are retained.
private struct FocusDynamicLiveAnchorMarker: UIViewRepresentable {
    let id: String
    let anchor: FocusDynamicFeedVisualAnchor
    func makeUIView(context: Context) -> FocusDynamicAnchorSurfaceView {
        FocusDynamicAnchorSurfaceView(id: id, anchor: anchor)
    }
    func updateUIView(_ view: FocusDynamicAnchorSurfaceView, context: Context) { view.setNeedsLayout() }
    static func dismantleUIView(_ view: FocusDynamicAnchorSurfaceView, coordinator: ()) {
        view.retired = true
        view.anchor?.removeSurface(view)
    }
}

@MainActor
private final class FocusDynamicAnchorSurfaceView: UIView {
    let dynamicID: String
    let serial: Int
    weak var anchor: FocusDynamicFeedVisualAnchor?
    var retired = false
    var layoutGeneration: UInt64 = .max
    private var reportedFrame: CGRect?

    init(id: String, anchor: FocusDynamicFeedVisualAnchor) {
        dynamicID = id; self.anchor = anchor; serial = anchor.nextSurfaceSerial()
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { anchor?.removeSurface(self) }
        else { anchor?.registerSurface(self); setNeedsLayout() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let anchor, !retired, window != nil else { return }
        let previousGeneration = layoutGeneration
        layoutGeneration = anchor.geometryVersion
        anchor.registerSurface(self)
        let current = anchor.scrollView.map { convert(bounds, to: $0) }
        if reportedFrame != current || previousGeneration != layoutGeneration {
            reportedFrame = current
            anchor.geometryDidChange()
        }
    }
}

private struct FocusDynamicFeedAnchorMarker: View {
    let id: String
    let anchor: FocusDynamicFeedVisualAnchor
    @State private var owner = UUID()
    @State private var latestFrame: CGRect?

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    // Reappearing at an unchanged position still needs registration.
                    anchor.registerFrame(
                        latestFrame ?? geometry.frame(in: .named(FocusDynamicFeedVisualAnchor.coordinateSpace)),
                        id: id, owner: owner
                    )
                }
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(FocusDynamicFeedVisualAnchor.coordinateSpace))
                } action: { frame in
                    // Geometry can arrive before onAppear. Preserve that layout
                    // sample rather than register a captured earlier proxy later.
                    latestFrame = frame
                    anchor.updateFrame(frame, id: id, owner: owner)
                }
                .onDisappear { anchor.removeFrame(id: id, owner: owner) }
        }
    }
}

struct FocusDynamicFeedScrollBridge: UIViewRepresentable {
    let offsetY: CGFloat
    let restorationRevision: Int
    let isActive: Bool
    var visualAnchor: FocusDynamicFeedVisualAnchor? = nil
    let onOffsetChange: @MainActor (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> FocusDynamicFeedScrollProbeView {
        let view = FocusDynamicFeedScrollProbeView()
        view.isUserInteractionEnabled = false
        context.coordinator.update(
            probe: view,
            offsetY: offsetY,
            restorationRevision: restorationRevision,
            isActive: isActive,
            visualAnchor: visualAnchor,
            onOffsetChange: onOffsetChange
        )
        return view
    }

    func updateUIView(_ uiView: FocusDynamicFeedScrollProbeView, context: Context) {
        context.coordinator.update(
            probe: uiView,
            offsetY: offsetY,
            restorationRevision: restorationRevision,
            isActive: isActive,
            visualAnchor: visualAnchor,
            onOffsetChange: onOffsetChange
        )
    }

    static func dismantleUIView(
        _ uiView: FocusDynamicFeedScrollProbeView,
        coordinator: Coordinator
    ) {
        uiView.onDidMoveToWindow = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var contentSizeObservation: NSKeyValueObservation?
        private var insetObservation: NSKeyValueObservation?
        private var restorationWorkItem: DispatchWorkItem?
        private var maintainsRestorationTarget = false
        private var hasReachedTarget = false
        private var isApplyingRestoration = false
        private var appliedRestorationRevision: Int?
        private var requestedOffsetY: CGFloat = 0
        private var restorationRevision = 0
        private var restorationGeneration = 0
        private var isActive = false
        private var onOffsetChange: (@MainActor (CGFloat) -> Void)?
        private var visualAnchor: FocusDynamicFeedVisualAnchor?
        private var restoreSpan: BiliPerformanceSpan?
        private var correlationID = UUID()
        private var expirationWorkItem: DispatchWorkItem?
        private var localCompensationPending = false
        private var localCompensationLink: CADisplayLink?
        private var localCompensationGeneration = 0
        private var correctionDeadline: CFTimeInterval = 0
        private var corrections = 0
        private(set) var fullRestorationCount = 0
        private(set) var layoutCompensationCount = 0
        private let maximumCorrections = 24
        private let correctionWindow: CFTimeInterval = 8
        private struct Viewport: Equatable {
            let size: CGSize
            let insets: UIEdgeInsets
            @MainActor init(_ scroll: UIScrollView) { size = scroll.bounds.size; insets = scroll.adjustedContentInset }
        }
        private var frozenViewport: Viewport?
        private var hasFrozenPosition = false
        private var boundsObservation: NSKeyValueObservation?
        private var observedViewport: Viewport?
        private var returnCompletion: ((FocusDynamicReturnOutcome) -> Void)?
        private var returnSpan: BiliPerformanceSpan?
        private var returnDisplayLink: CADisplayLink?
        private var returnTimeout: DispatchWorkItem?
        private var visibleDisplayLink: CADisplayLink?
        private var pendingUpdateIdleLink: CADisplayLink?
        private var visibleSpan: BiliPerformanceSpan?
        private var visibleDeadline: CFTimeInterval = 0
        private var visibleTargetID: String?
        private var maximumVisibleError: Double?
        private var missingVisibleFrames = 0
        private var returnDeadline: CFTimeInterval = 0
        private var returnAwaitingLayout = false
        private var returnGeneration = 0
        private var stableReturnFrames = 0
        private var stableReturnSample: StableReturnSample?
        private var materializationScheduled = false
        private var materializationAttempts = 0
        private var returnFrameIndex = 0
        private var nextMaterializationFrame = 0
        private var didRecordResolvedAnchor = false
        private(set) var materializationCount = 0
        private(set) var offsetCorrectionCount = 0
        private(set) var normalReturnCount = 0
        private(set) var lastReturnOutcome: FocusDynamicReturnOutcome?
        var hasPendingReturn: Bool { returnCompletion != nil }
        private var canOperate: Bool { isActive || hasPendingReturn }

        private struct StableReturnSample: Equatable {
            let viewport: Viewport
            let contentSize: CGSize
            let target: CGRect
            let offset: CGPoint
            let geometryVersion: UInt64
        }

        private func record(_ stage: BiliPerformanceStage, outcome: BiliPerformanceOutcome = .success,
                            count: Int = 0, error: Double? = nil) {
            let span = BiliPerformanceStore.shared.begin(stage, correlationID: correlationID)
            BiliPerformanceStore.shared.end(span, outcome: outcome, count: count, positionErrorPoints: error)
        }

        private func viewportDidChange() {
            guard let scrollView else { return }
            let current = Viewport(scrollView)
            guard observedViewport != current else { return }
            let wasInitialized = observedViewport != nil
            observedViewport = current
            if wasInitialized {
                visualAnchor?.invalidateGeometry()
                stableReturnFrames = 0
                stableReturnSample = nil
                record(.layoutChanged, count: Int(clamping: visualAnchor?.geometryVersion ?? 0))
            }
        }

        /// Called while the actual detail still covers the feed. A preserved
        /// viewport returns synchronously; only changed layout takes the gate.
        func prepareForReturn(_ completion: @escaping (FocusDynamicReturnOutcome) -> Void) {
            finishPendingReturn(.cancelled)
            guard let scrollView, scrollView.window != nil else { completion(.unavailable); return }
            scrollView.superview?.layoutIfNeeded()
            scrollView.layoutIfNeeded()
            viewportDidChange()
            let layoutIsReady = visualAnchor?.prepareLayoutForReturn?() ?? true
            if layoutIsReady, canPreservePosition(scrollView) {
                normalReturnCount += 1
                lastReturnOutcome = .preserved
                correlationID = UUID()
                record(.normalReturnPreserved, error: anchorError)
                visualAnchor?.finishLayoutForReturn?()
                completion(.preserved)
                return
            }
            guard visualAnchor?.snapshot != nil else {
                visualAnchor?.finishLayoutForReturn?()
                completion(.unavailable)
                return
            }
            returnCompletion = completion
            returnGeneration &+= 1
            returnDeadline = CACurrentMediaTime() + 0.8 // Maximum budget, never a fixed visibility delay.
            stableReturnFrames = 0
            stableReturnSample = nil
            returnFrameIndex = 0
            returnAwaitingLayout = !layoutIsReady
            if layoutIsReady {
                startRestoration()
            } else {
                cancelRestoration()
                correlationID = UUID()
            }
            guard returnCompletion != nil else { return }
            returnSpan = BiliPerformanceStore.shared.begin(.scrollReturn, correlationID: correlationID)
            let link = CADisplayLink(target: self, selector: #selector(returnFrame))
            returnDisplayLink = link
            link.add(to: .main, forMode: .common)
            let generation = returnGeneration
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.returnGeneration == generation else { return }
                self.finishPendingReturn(.timedOut)
            }
            returnTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: timeout)
        }

        func cancelPendingReturn() { finishPendingReturn(.cancelled) }

        @objc private func returnFrame() {
            guard hasPendingReturn, let scrollView, let anchor = visualAnchor else { return }
            returnFrameIndex += 1
            guard CACurrentMediaTime() < returnDeadline else { finishPendingReturn(.timedOut); return }
            guard let snapshot = anchor.snapshot else { finishPendingReturn(.scopeChanged); return }
            guard snapshot.dataRevision == anchor.dataRevision else { finishPendingReturn(.scopeChanged); return }
            guard anchor.targetIsInData else { record(.anchorMissing, outcome: .fallback); finishPendingReturn(.anchorMissing); return }
            guard anchor.isReturnLayoutReady else {
                stableReturnFrames = 0
                stableReturnSample = nil
                return
            }
            if returnAwaitingLayout {
                returnAwaitingLayout = false
                scrollView.superview?.layoutIfNeeded()
                scrollView.layoutIfNeeded()
                viewportDidChange()
                if canPreservePosition(scrollView) {
                    normalReturnCount += 1
                    record(.normalReturnPreserved, error: anchorError)
                    finishPendingReturn(.preserved)
                    return
                }
                startRestoration()
            }
            viewportDidChange()
            restoreOffset(attempt: 30, generation: restorationGeneration)
            guard hasPendingReturn else { return }
            guard let frame = anchor.frame(for: snapshot.id), let error = anchorError else {
                stableReturnFrames = 0; stableReturnSample = nil
                return
            }
            let sample = StableReturnSample(viewport: Viewport(scrollView), contentSize: scrollView.contentSize,
                                            target: frame, offset: scrollView.contentOffset,
                                            geometryVersion: anchor.geometryVersion)
            stableReturnFrames = sample == stableReturnSample ? stableReturnFrames + 1 : 1
            stableReturnSample = sample
            // Consecutive rendered layout opportunities, not sleeps or a timer
            // masquerading as layout completion. Root geometry is isolated, so
            // removing the detail cannot change the successful feed proposal.
            guard stableReturnFrames >= 2 else { return }
            if abs(error) <= 1 {
                finishPendingReturn(.aligned)
            } else if let target = anchor.targetNormalizedOffset {
                let maximum = max(0, scrollView.contentSize.height - scrollView.bounds.height
                                  + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom)
                if target < -1 || target > maximum + 1 { finishPendingReturn(.clamped) }
            }
        }

        private func finishPendingReturn(_ result: FocusDynamicReturnOutcome) {
            guard let completion = returnCompletion else { return }
            returnCompletion = nil
            returnGeneration &+= 1
            returnAwaitingLayout = false
            returnDisplayLink?.invalidate(); returnDisplayLink = nil
            returnTimeout?.cancel(); returnTimeout = nil
            lastReturnOutcome = result
            let outcome: BiliPerformanceOutcome = result == .aligned || result == .preserved ? .success
                : result == .timedOut ? .timedOut
                : result == .gesture || result == .userOverride || result == .cancelled ? .cancelled : .fallback
            if let returnSpan {
                BiliPerformanceStore.shared.end(returnSpan, outcome: outcome, count: corrections, positionErrorPoints: anchorError)
            }
            returnSpan = nil
            if outcome != .success { record(.restorationFallback, outcome: outcome, count: materializationAttempts, error: anchorError) }
            if result == .scopeChanged { record(.restorationScopeChanged, outcome: .fallback) }
            if result == .clamped { record(.restorationClamped, outcome: .fallback, error: anchorError) }
            cancelRestoration()
            if result == .aligned || result == .preserved, let scrollView {
                frozenViewport = Viewport(scrollView)
                hasFrozenPosition = true
            } else if result == .cancelled {
                // Another detail may be opened before this return finishes.
                // Cancel its work, not the root's original reading identity.
                hasFrozenPosition = true
            } else {
                visualAnchor?.clear()
                hasFrozenPosition = false
                if result == .timedOut || result == .clamped || result == .anchorMissing || result == .userOverride, let scrollView {
                    // A bounded fallback is final. Do not reveal and then start
                    // another numeric-offset recovery behind the user's gesture.
                    requestedOffsetY = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
                    onOffsetChange?(requestedOffsetY)
                    frozenViewport = Viewport(scrollView)
                    hasFrozenPosition = true
                }
            }
            visualAnchor?.finishLayoutForReturn?()
            completion(result)
            if isActive {
                // The hosted feed may already be active for layout underneath
                // the detail. Its pending return is the only recovery owner;
                // activation must not start a second numeric-offset restore.
                appliedRestorationRevision = restorationRevision
                if outcome == .success {
                    hasFrozenPosition = false
                    beginPreservationWatch()
                    beginVisibleSampling()
                }
            }
        }

        private func requestMaterialization(id: String, generation: Int) {
            guard !materializationScheduled, materializationAttempts < 3,
                  !hasPendingReturn || returnFrameIndex >= nextMaterializationFrame,
                  let anchor = visualAnchor, anchor.materialize != nil,
                  let snapshot = anchor.snapshot, let scrollView,
                  let point = FocusDynamicFeedVisualAnchor.materializationPoint(
                    viewportY: snapshot.viewportY,
                    viewportHeight: scrollView.bounds.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom
                  ) else { return }
            // A scrollTo can emit several geometry callbacks before SwiftUI
            // consumes its layout transaction. Give that request a rendered
            // layout opportunity before spending another of the three slots.
            // This is render-event backpressure, not a fixed-time sleep.
            nextMaterializationFrame = returnFrameIndex + 2
            materializationScheduled = true
            materializationAttempts += 1; materializationCount += 1
            record(.anchorMaterializationRequested, count: materializationAttempts)
            let scope = anchor.dataRevision
            DispatchQueue.main.async { [weak self, weak anchor] in
                guard let self, let anchor, generation == restorationGeneration else { return }
                materializationScheduled = false
                guard canOperate, maintainsRestorationTarget, anchor.snapshot?.id == id,
                      anchor.dataRevision == scope, anchor.targetIsInData else { return }
                anchor.materialize?(id, point)
            }
        }


        private func canPreservePosition(_ scroll: UIScrollView) -> Bool {
            guard hasFrozenPosition, frozenViewport == Viewport(scroll) else { return false }
            if let anchor = visualAnchor, anchor.snapshot != nil {
                guard let error = anchorError else { return false }
                return abs(error) <= 1
            }
            return abs(scroll.contentOffset.y + scroll.adjustedContentInset.top - requestedOffsetY) <= 1
        }

        func update(
            probe: FocusDynamicFeedScrollProbeView,
            offsetY: CGFloat,
            restorationRevision: Int,
            isActive: Bool,
            visualAnchor: FocusDynamicFeedVisualAnchor? = nil,
            onOffsetChange: @escaping @MainActor (CGFloat) -> Void
        ) {
            let shouldFreezeCurrentPosition = self.isActive && !isActive
            let shouldRestoreSavedPosition = !self.isActive && isActive
            if self.restorationRevision != restorationRevision {
                finishPendingReturn(.scopeChanged)
                visualAnchor?.clear()
                hasFrozenPosition = false
            }
            self.visualAnchor = visualAnchor
            requestedOffsetY = max(offsetY, 0)
            self.restorationRevision = restorationRevision
            self.isActive = isActive
            self.onOffsetChange = onOffsetChange
            if shouldFreezeCurrentPosition {
                freezeCurrentPosition()
            }
            if shouldRestoreSavedPosition {
                appliedRestorationRevision = nil
            }
            probe.onDidMoveToWindow = { [weak self] probe in
                guard probe.window != nil else {
                    self?.detach()
                    return
                }
                self?.attachIfPossible(from: probe)
            }
            DispatchQueue.main.async { [weak self, weak probe] in
                guard let self, let probe, probe.window != nil else {
                    return
                }
                self.attachIfPossible(from: probe)
            }
        }

        private func attachIfPossible(from probe: UIView) {
            guard probe.window != nil,
                  let resolvedScrollView = probe.enclosingScrollView
            else {
                return
            }
            if scrollView !== resolvedScrollView {
                detach()
                scrollView = resolvedScrollView
                visualAnchor?.scrollView = resolvedScrollView
                observedViewport = Viewport(resolvedScrollView)
                visualAnchor?.freezeForDetails = { [weak self] in self?.freezeCurrentPosition() }
                visualAnchor?.prepareReturn = { [weak self] completion in
                    guard let self else { completion(.unavailable); return }
                    self.prepareForReturn(completion)
                }
                visualAnchor?.cancelReturn = { [weak self] in self?.cancelPendingReturn() }
                visualAnchor?.forceReturn = { [weak self] in self?.finishPendingReturn(.userOverride) }
                visualAnchor?.invalidateReturnScope = { [weak self] in
                    self?.finishPendingReturn(.scopeChanged)
                    self?.cancelRestoration()
                }
                visualAnchor?.userWillChangeLayout = { [weak self] in
                    guard let self, let scrollView = self.scrollView else { return }
                    self.observeOffset(contentOffsetY: scrollView.contentOffset.y, isUserDriven: true)
                }
                visualAnchor?.applyContentUpdate = { [weak self] update in
                    guard let self else { return false }
                    return self.applyContentUpdate(update)
                }
#if DEBUG
                if FocusTestRuntime.isRunningFixtures { visualAnchor?.fixtureCoordinator = self }
#endif
                visualAnchor?.onGeometryChange = { [weak self] in
                    guard let self, self.canOperate, self.maintainsRestorationTarget else { return }
                    self.viewportDidChange()
                    self.scheduleLayoutCompensation()
                }
                resolvedScrollView.panGestureRecognizer.addTarget(self, action: #selector(panDidChange(_:)))
                appliedRestorationRevision = nil
                observation = resolvedScrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, change in
                    // UIKit scroll geometry changes on the main thread. Cancel in
                    // this callback, before a queued layout correction can run.
                    MainActor.assumeIsolated {
                        guard let self, let scrollView = self.scrollView,
                              self.canOperate, !self.isApplyingRestoration else { return }
                        if self.isUserScrolling(scrollView) {
                            self.observeOffset(contentOffsetY: change.newValue?.y ?? scrollView.contentOffset.y,
                                               isUserDriven: true)
                        } else if self.maintainsRestorationTarget {
                            self.scheduleLayoutCompensation()
                        }
                    }
                }
                boundsObservation = resolvedScrollView.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.viewportDidChange()
                        if self.canOperate && self.maintainsRestorationTarget { self.scheduleLayoutCompensation() }
                    }
                }
                contentSizeObservation = resolvedScrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.canOperate, self.maintainsRestorationTarget else { return }
                    self.viewportDidChange()
                        self.scheduleLayoutCompensation()
                    }
                }
                insetObservation = resolvedScrollView.observe(\.adjustedContentInset, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.canOperate, self.maintainsRestorationTarget else { return }
                    self.viewportDidChange()
                        self.scheduleLayoutCompensation()
                    }
                }
            }
            guard isActive, !hasPendingReturn, appliedRestorationRevision != restorationRevision else {
                return
            }
            appliedRestorationRevision = restorationRevision
            if canPreservePosition(resolvedScrollView) {
                hasFrozenPosition = false
                // Observe only actual late geometry/offset changes. This does
                // not start a full restore or move an unchanged scroll view.
                beginPreservationWatch()
                beginVisibleSampling()
                return
            }
            hasFrozenPosition = false
            visualAnchor?.trace("activate")
            startRestoration()
        }

        func detach() {
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panDidChange(_:)))
            finishPendingReturn(.cancelled)
            boundsObservation?.invalidate(); boundsObservation = nil
            visualAnchor?.prepareReturn = nil
            visualAnchor?.freezeForDetails = nil
            visualAnchor?.cancelReturn = nil
            visualAnchor?.forceReturn = nil
            visualAnchor?.invalidateReturnScope = nil
            visualAnchor?.userWillChangeLayout = nil
            visualAnchor?.applyContentUpdate = nil
            pendingUpdateIdleLink?.invalidate(); pendingUpdateIdleLink = nil
            stopVisibleSampling(outcome: .cancelled)
            observedViewport = nil
            cancelRestoration()
            observation?.invalidate()
            observation = nil
            contentSizeObservation?.invalidate()
            contentSizeObservation = nil
            insetObservation?.invalidate()
            insetObservation = nil
            visualAnchor?.onGeometryChange = nil
            visualAnchor?.scrollView = nil
            scrollView = nil
            appliedRestorationRevision = nil
        }

        private func beginPreservationWatch() {
            cancelRestoration()
            maintainsRestorationTarget = true
            hasReachedTarget = true
            corrections = 0
            correctionDeadline = CACurrentMediaTime() + correctionWindow
            let generation = restorationGeneration
            let expiration = DispatchWorkItem { [weak self] in
                guard let self, self.restorationGeneration == generation else { return }
                self.maintainsRestorationTarget = false
                self.expirationWorkItem = nil
            }
            expirationWorkItem = expiration
            DispatchQueue.main.asyncAfter(deadline: .now() + correctionWindow, execute: expiration)
        }

        private func applyContentUpdate(_ update: () -> Void) -> Bool {
            guard canOperate, !hasPendingReturn, let scrollView else { return false }
            guard scrollView.contentOffset.y + scrollView.adjustedContentInset.top <= 1 else { return false }
            guard !isUserScrolling(scrollView) else {
                if pendingUpdateIdleLink == nil {
                    let link = CADisplayLink(target: self, selector: #selector(applyAfterInteraction))
                    pendingUpdateIdleLink = link
                    link.add(to: .main, forMode: .common)
                }
                return false
            }
            cancelRestoration()
            visualAnchor?.clear()
            UIView.performWithoutAnimation {
                update()
            }
            return true
        }

        @objc private func applyAfterInteraction() {
            guard canOperate, let scrollView else {
                pendingUpdateIdleLink?.invalidate(); pendingUpdateIdleLink = nil
                return
            }
            guard !isUserScrolling(scrollView) else { return }
            pendingUpdateIdleLink?.invalidate(); pendingUpdateIdleLink = nil
            visualAnchor?.onInteractionEnded?()
        }

        private func beginVisibleSampling() {
            stopVisibleSampling(outcome: .cancelled)
            guard isActive, let target = visualAnchor?.snapshot?.id else { return }
            visibleTargetID = target
            maximumVisibleError = nil; missingVisibleFrames = 0
            visibleDeadline = CACurrentMediaTime() + 1.6
            visibleSpan = BiliPerformanceStore.shared.begin(.visiblePositionError, correlationID: correlationID)
            let link = CADisplayLink(target: self, selector: #selector(sampleVisiblePosition))
            visibleDisplayLink = link
            link.add(to: .main, forMode: .common)
        }

        @objc private func sampleVisiblePosition() {
            guard isActive, visualAnchor?.snapshot?.id == visibleTargetID else {
                stopVisibleSampling(outcome: .cancelled); return
            }
            if let error = anchorError { maximumVisibleError = max(maximumVisibleError ?? 0, abs(error)) }
            else { missingVisibleFrames += 1 }
            if CACurrentMediaTime() >= visibleDeadline {
                stopVisibleSampling(outcome: missingVisibleFrames == 0 && (maximumVisibleError ?? .infinity) <= 2 ? .success : .failure)
            }
        }

        private func stopVisibleSampling(outcome: BiliPerformanceOutcome) {
            visibleDisplayLink?.invalidate(); visibleDisplayLink = nil
            if let visibleSpan {
                BiliPerformanceStore.shared.end(visibleSpan, outcome: outcome, count: missingVisibleFrames,
                                                positionErrorPoints: maximumVisibleError)
            }
            visibleSpan = nil; visibleTargetID = nil
        }

        private func startRestoration() {
            cancelRestoration()
            maintainsRestorationTarget = true
            hasReachedTarget = false
            corrections = 0
            fullRestorationCount += 1
            materializationAttempts = 0
            materializationScheduled = false
            nextMaterializationFrame = 0
            didRecordResolvedAnchor = false
            correlationID = UUID()
            restoreSpan = BiliPerformanceStore.shared.begin(.scrollRestore, correlationID: correlationID)
            correctionDeadline = CACurrentMediaTime() + correctionWindow
            restorationGeneration &+= 1
            let currentGeneration = restorationGeneration
            let expiration = DispatchWorkItem { [weak self] in
                guard let self, restorationGeneration == currentGeneration else { return }
                finishFullRestoration(outcome: isAnchorAligned ? .success : .fallback)
                maintainsRestorationTarget = false
                restorationWorkItem?.cancel(); restorationWorkItem = nil
                expirationWorkItem = nil
            }
            expirationWorkItem = expiration
            DispatchQueue.main.asyncAfter(deadline: .now() + correctionWindow, execute: expiration)
            restoreOffset(attempt: 0, generation: currentGeneration)
        }

        private func cancelRestoration() {
            finishFullRestoration(outcome: .cancelled)
            maintainsRestorationTarget = false
            restorationGeneration &+= 1
            restorationWorkItem?.cancel(); restorationWorkItem = nil
            expirationWorkItem?.cancel(); expirationWorkItem = nil
            localCompensationLink?.invalidate(); localCompensationLink = nil
            localCompensationPending = false
        }

        private var isAnchorAligned: Bool {
            guard visualAnchor?.snapshot != nil, visualAnchor?.targetIsInData == true,
                  let error = anchorError else { return false }
            return abs(error) <= 1
        }

        private var anchorError: Double? {
            guard let target = visualAnchor?.targetNormalizedOffset, let scrollView else { return nil }
            return Double(target - scrollView.contentOffset.y - scrollView.adjustedContentInset.top)
        }

        private func finishFullRestoration(outcome: BiliPerformanceOutcome) {
            guard let span = restoreSpan else { return }
            BiliPerformanceStore.shared.end(span, outcome: outcome, count: corrections, positionErrorPoints: anchorError)
            restoreSpan = nil
        }

        /// Geometry never creates a new return-restoration session. At most one
        /// local correction is scheduled per run-loop, inside the original
        /// bounded window and correction budget. Late LazyVStack materialization
        /// still works, including the existing two-second delayed-height case.
        private var needsLayoutCompensation: Bool {
            guard let scrollView else { return false }
            if visualAnchor?.snapshot != nil {
                // Missing/invalid identity must still follow the bounded recovery
                // path, but an unchanged real card needs no compensation pass.
                guard let error = anchorError else { return true }
                return abs(error) > 0.5
            }
            return abs(scrollView.contentOffset.y + scrollView.adjustedContentInset.top - requestedOffsetY) > 0.5
        }

        private func scheduleLayoutCompensation() {
            guard canOperate, maintainsRestorationTarget, !localCompensationPending else { return }
            if let scrollView, isUserScrolling(scrollView) {
                observeOffset(contentOffsetY: scrollView.contentOffset.y, isUserDriven: true)
                return
            }
            // The covered return already has a single frame-synchronized owner.
            // Do not race a second KVO-driven writer against returnFrame().
            guard !hasPendingReturn, needsLayoutCompensation else { return }
            guard CACurrentMediaTime() <= correctionDeadline, corrections < maximumCorrections else {
                finishFullRestoration(outcome: isAnchorAligned ? .success : .fallback)
                maintainsRestorationTarget = false
                return
            }
            localCompensationPending = true
            localCompensationGeneration = restorationGeneration
            let link = CADisplayLink(target: self, selector: #selector(applyScheduledCompensation))
            localCompensationLink = link
            link.add(to: .main, forMode: .common)
        }

        @objc private func applyScheduledCompensation() {
            localCompensationLink?.invalidate(); localCompensationLink = nil
            defer { localCompensationPending = false }
            let generation = localCompensationGeneration
            guard generation == restorationGeneration, canOperate, maintainsRestorationTarget,
                  !hasPendingReturn, let scrollView else { return }
            // A content-coordinate rebase can send offset KVO before row layout.
            // Let that rendering opportunity finish, then consult live geometry.
            // Coupled content/offset changes with zero screen error are ignored.
            scrollView.layoutIfNeeded()
            guard generation == restorationGeneration, needsLayoutCompensation else { return }
            let span = BiliPerformanceStore.shared.begin(.layoutCompensation, correlationID: correlationID)
            let before = corrections
            restorationWorkItem?.cancel(); restorationWorkItem = nil
            restoreOffset(attempt: 30, generation: generation)
            layoutCompensationCount += 1
            BiliPerformanceStore.shared.end(span, count: corrections - before, positionErrorPoints: anchorError)
        }

        @objc private func panDidChange(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed, let scrollView else { return }
            observeOffset(contentOffsetY: scrollView.contentOffset.y, isUserDriven: true)
        }

        func observeOffset(contentOffsetY: CGFloat, isUserDriven: Bool) {
            // A real pan can arrive after the route commits but before
            // SwiftUI delivers its new isActive input. Never lose that input.
            // KVO callers still filter hidden/non-user events before entering.
            guard isUserDriven, let scrollView else { return }
            let awaitingActivation = !isActive || hasPendingReturn
            let minimumY = -scrollView.adjustedContentInset.top
            let normalizedOffsetY = FocusDynamicFeedScrollRestorationPolicy.normalizedOffset(
                contentOffsetY: contentOffsetY,
                minimumY: minimumY
            )
            // A real gesture wins over a pending delayed restoration.
            cancelRestoration()
            record(.restorationCancelledByGesture, outcome: .cancelled)
            stopVisibleSampling(outcome: .cancelled)
            finishPendingReturn(.gesture)
            visualAnchor?.clear()
            requestedOffsetY = normalizedOffsetY
            onOffsetChange?(normalizedOffsetY)
            if awaitingActivation {
                frozenViewport = Viewport(scrollView)
                hasFrozenPosition = true
            }
        }

        private func isUserScrolling(_ scrollView: UIScrollView) -> Bool {
            let panState = scrollView.panGestureRecognizer.state
            return FocusDynamicFeedScrollRestorationPolicy.shouldPersistObservedOffset(
                isTracking: scrollView.isTracking,
                isDragging: scrollView.isDragging,
                isDecelerating: scrollView.isDecelerating,
                isPanActive: panState == .began || panState == .changed
            )
        }

        private func freezeCurrentPosition() {
            guard let scrollView else {
                return
            }
            // Ignore the delayed inactive ACK for a synchronous push. A new
            // push while still active (open/back within one render transaction)
            // must refresh the viewport rather than reuse the former freeze.
            guard !hasFrozenPosition || isActive else { return }
            stopVisibleSampling(outcome: .cancelled)

            let keepSavedTarget = maintainsRestorationTarget
            if visualAnchor?.snapshot == nil, !keepSavedTarget || hasReachedTarget {
                visualAnchor?.capture()
            }
            visualAnchor?.trace("freeze")
            cancelRestoration()
            let contentOffset = scrollView.contentOffset
            frozenViewport = Viewport(scrollView)
            hasFrozenPosition = true
            if scrollView.isDecelerating {
                // Only stop genuine residual user momentum before covering it.
                scrollView.setContentOffset(contentOffset, animated: false)
            }
            // A first-entry layout can still be clamped. Never replace the saved
            // target with that temporary position when leaving the page again.
            if keepSavedTarget {
                maintainsRestorationTarget = true
                return
            }
            let minimumY = -scrollView.adjustedContentInset.top
            let normalizedOffsetY = FocusDynamicFeedScrollRestorationPolicy.normalizedOffset(
                contentOffsetY: contentOffset.y,
                minimumY: minimumY
            )
            requestedOffsetY = normalizedOffsetY
            onOffsetChange?(normalizedOffsetY)
        }

        private func restoreOffset(attempt: Int, generation: Int) {
            guard generation == restorationGeneration,
                  canOperate,
                  let scrollView,
                  scrollView.window != nil
            else {
                return
            }

            // A gesture may begin before it produces an offset KVO callback.
            if isUserScrolling(scrollView) {
                observeOffset(contentOffsetY: scrollView.contentOffset.y, isUserDriven: true)
                return
            }
            scrollView.layoutIfNeeded()
            guard generation == restorationGeneration else { return }
            viewportDidChange()
            if let anchor = visualAnchor, let snapshot = anchor.snapshot {
                guard snapshot.dataRevision == anchor.dataRevision else {
                    finishFullRestoration(outcome: .fallback)
                    finishPendingReturn(.scopeChanged)
                    maintainsRestorationTarget = false
                    return
                }
                guard anchor.targetIsInData else {
                    record(.anchorMissing, outcome: .fallback)
                    finishFullRestoration(outcome: .fallback)
                    finishPendingReturn(.anchorMissing)
                    maintainsRestorationTarget = false
                    return
                }
                guard anchor.frame(for: snapshot.id) != nil else {
                    hasReachedTarget = false
                    requestMaterialization(id: snapshot.id, generation: generation)
                    return
                }
                if !didRecordResolvedAnchor {
                    didRecordResolvedAnchor = true
                    record(.anchorResolved)
                }
            }
            if let anchoredOffset = visualAnchor?.targetNormalizedOffset {
                requestedOffsetY = max(anchoredOffset, 0)
            }
            let minimumY = -scrollView.adjustedContentInset.top
            let maximumY = max(
                minimumY,
                scrollView.contentSize.height
                    - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom
            )
            let placement = FocusDynamicFeedScrollRestorationPolicy.placement(
                requestedOffsetY: requestedOffsetY,
                minimumY: minimumY,
                maximumY: maximumY
            )
            hasReachedTarget = placement.reachedTarget
            if abs(scrollView.contentOffset.y - placement.contentOffsetY) > 0.5 {
                guard corrections < maximumCorrections, CACurrentMediaTime() <= correctionDeadline else {
                    finishFullRestoration(outcome: .fallback)
                    maintainsRestorationTarget = false
                    return
                }
                corrections += 1
                isApplyingRestoration = true
                offsetCorrectionCount += 1
                record(.preciseAlignment, count: corrections, error: anchorError)
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: placement.contentOffsetY),
                    animated: false
                )
                isApplyingRestoration = false
                visualAnchor?.trace("restore")
            }
            if placement.reachedTarget, visualAnchor?.snapshot != nil {
                onOffsetChange?(requestedOffsetY)
            }

            guard !placement.reachedTarget else {
                restorationWorkItem = nil
                // An absent lazy row is not proof that its visual anchor has
                // settled; keep only bounded geometry compensation eligible.
                if isAnchorAligned {
                    finishFullRestoration(outcome: .success)
                } else if visualAnchor?.snapshot == nil {
                    finishFullRestoration(outcome: .fallback)
                }
                return
            }

            // LazyVStack initially reports only a partial content height. Keep the
            // original target intact while it materializes instead of saving the
            // temporary clamped offset and jumping to it on the next update.
            guard attempt < 30 else {
                restorationWorkItem = nil
                // Preserve the target for actual geometry events within the
                // original eight-second window; do not reset the poll budget.
                return
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else {
                    return
                }
                self.restoreOffset(attempt: attempt + 1, generation: generation)
            }
            restorationWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }
    }
}

final class FocusDynamicFeedScrollProbeView: UIView {
    var onDidMoveToWindow: ((FocusDynamicFeedScrollProbeView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onDidMoveToWindow?(self)
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var candidate = superview
        while let current = candidate {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            candidate = current.superview
        }
        return nil
    }
}

struct FocusDynamicCardView: View {
    let card: DynamicCard
    @Binding var areImagesExpanded: Bool
    @Binding var isTextExpanded: Bool
    let onOpenCard: () -> Void
    let onOpenUser: (Int64) -> Void
    let onOpenImage: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    guard card.author.mid > 0 else {
                        return
                    }
                    onOpenUser(card.author.mid)
                } label: {
                    avatar
                }
                .buttonStyle(.plain)
                .disabled(card.author.mid <= 0)
                .accessibilityLabel("打开\(card.author.name)的个人主页")

                Button(action: onOpenCard) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.author.name)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            HStack(spacing: 8) {
                                if !card.publishTime.isEmpty {
                                    Text(card.publishTime)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                FocusKindBadge(kind: card.kind)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !card.text.isEmpty {
                FocusExpandableDynamicText(
                    text: card.text,
                    onOpenCard: onOpenCard,
                    isExpanded: $isTextExpanded
                )
            }

            if !card.coverURLs.isEmpty {
                covers
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var covers: some View {
        let canFoldImages = card.kind == .image && card.coverURLs.count > 4
        let visibleCoverURLs = canFoldImages && !areImagesExpanded
            ? Array(card.coverURLs.prefix(4))
            : card.coverURLs

        if let firstURL = visibleCoverURLs.first, visibleCoverURLs.count == 1 {
            FocusDynamicMediaCover(
                url: firstURL,
                referer: card.targetURL.absoluteString,
                height: 176
            )
            .contentShape(Rectangle())
            .onTapGesture {
                card.kind == .image ? onOpenImage(0) : onOpenCard()
            }
        } else {
            LazyVGrid(columns: coverColumns(for: visibleCoverURLs.count), spacing: 10) {
                ForEach(Array(visibleCoverURLs.enumerated()), id: \.offset) { item in
                    FocusDynamicMediaCover(
                        url: item.element,
                        referer: card.targetURL.absoluteString,
                        height: coverHeight(for: visibleCoverURLs.count, index: item.offset)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        card.kind == .image ? onOpenImage(item.offset) : onOpenCard()
                    }
                }
            }
        }

        if canFoldImages {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    areImagesExpanded.toggle()
                }
            } label: {
                Label(
                    areImagesExpanded ? "收起图片" : "展开全部 \(card.coverURLs.count) 张图片",
                    systemImage: areImagesExpanded ? "chevron.up" : "chevron.down"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(FocusDesign.primary)
        }
    }

    private func coverColumns(for count: Int) -> [GridItem] {
        let columnCount = count == 1 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

    private func coverHeight(for count: Int, index _: Int) -> CGFloat {
        count == 1 ? 176 : 132
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = card.author.avatarURL {
            FocusRemoteImage(url: avatarURL, referer: card.targetURL.absoluteString) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Circle()
                        .fill(Color(uiColor: .secondarySystemFill))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                case .empty:
                    Circle()
                        .fill(Color(uiColor: .secondarySystemFill))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                )
        }
    }
}

/// Size the text AND its fold control in the same proposal. No geometry
/// preference writes back into SwiftUI state after LazyVStack has sized a row.
/// Only this text component is UIKit-backed; the feed and card stay SwiftUI.
struct FocusExpandableDynamicText: UIViewRepresentable {
    let text: String
    let onOpenCard: () -> Void
    @Binding var isExpanded: Bool
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> FocusDynamicTextContentView { FocusDynamicTextContentView() }

    func updateUIView(_ view: FocusDynamicTextContentView, context: Context) {
        let traits = UITraitCollection(preferredContentSizeCategory: uiContentSizeCategory)
        var bodyFont = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        if legibilityWeight == .bold, let bold = bodyFont.fontDescriptor.withSymbolicTraits(.traitBold) {
            bodyFont = UIFont(descriptor: bold, size: bodyFont.pointSize)
        }
        let buttonFont = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .semibold), compatibleWith: traits)
        view.configure(text: text, expanded: isExpanded, bodyFont: bodyFont, buttonFont: buttonFont,
                       scale: displayScale, rightToLeft: layoutDirection == .rightToLeft)
        view.onOpen = onOpenCard
        view.onToggle = {
            if reduceMotion { isExpanded.toggle() }
            else { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FocusDynamicTextContentView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        return uiView.measuredSize(width: max(0, width))
    }

    private var uiContentSizeCategory: UIContentSizeCategory {
        switch sizeCategory {
        case .extraSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .extraLarge: .extraLarge
        case .extraExtraLarge: .extraExtraLarge
        case .extraExtraExtraLarge: .extraExtraExtraLarge
        case .accessibilityMedium: .accessibilityMedium
        case .accessibilityLarge: .accessibilityLarge
        case .accessibilityExtraLarge: .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

@MainActor
final class FocusDynamicTextContentView: UIView {
    private final class OpeningLabel: UILabel {
        var onOpen: (() -> Void)?
        override func accessibilityActivate() -> Bool {
            guard let onOpen else { return false }
            onOpen(); return true
        }
    }
    private let textLabel = OpeningLabel()
    let foldButton = UIButton(type: .system)
    private let fullMeasurer = UILabel()
    private let collapsedMeasurer = UILabel()
    private var expanded = false
    private var scale: CGFloat = 1
    private var rightToLeft = false
    var onOpen: (() -> Void)? { didSet { textLabel.onOpen = onOpen } }
    var onToggle: (() -> Void)?

    private struct Measurement {
        let textHeight: CGFloat
        let buttonSize: CGSize
        let showsButton: Bool
        var height: CGFloat { textHeight + (showsButton ? 2 + buttonSize.height : 0) }
    }
    // Instance-local and bounded. A changed text/font/expansion invalidates all
    // entries; exact effective width is used (no coarse width/height cache).
    private var measurements: [CGFloat: Measurement] = [:]
    private(set) var measurementCount = 0
    var cachedMeasurementCount: Int { measurements.count }

    init() {
        super.init(frame: .zero)
        textLabel.textColor = .label
        textLabel.isUserInteractionEnabled = true
        textLabel.accessibilityTraits = [.staticText, .button]
        textLabel.accessibilityHint = "打开动态详情"
        textLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openText)))
        foldButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        foldButton.titleLabel?.numberOfLines = 1
        foldButton.contentHorizontalAlignment = .leading
        fullMeasurer.numberOfLines = 0
        collapsedMeasurer.numberOfLines = 6
        for label in [textLabel, fullMeasurer, collapsedMeasurer] { label.lineBreakMode = .byTruncatingTail }
        addSubview(textLabel); addSubview(foldButton)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, expanded: Bool, bodyFont: UIFont, buttonFont: UIFont,
                   scale: CGFloat, rightToLeft: Bool) {
        let scale = max(scale, 1)
        guard textLabel.text != text || self.expanded != expanded || textLabel.font != bodyFont
                || foldButton.titleLabel?.font != buttonFont || self.scale != scale || self.rightToLeft != rightToLeft else { return }
        self.expanded = expanded; self.scale = scale; self.rightToLeft = rightToLeft
        for label in [textLabel, fullMeasurer, collapsedMeasurer] {
            label.text = text; label.font = bodyFont
            label.textAlignment = rightToLeft ? .right : .left
        }
        textLabel.numberOfLines = expanded ? 0 : 6
        textLabel.isAccessibilityElement = !text.isEmpty
        foldButton.titleLabel?.font = buttonFont
        foldButton.setTitle(expanded ? "收起文本" : "展开全文", for: .normal)
        foldButton.accessibilityLabel = expanded ? "收起文本" : "展开全文"
        semanticContentAttribute = rightToLeft ? .forceRightToLeft : .forceLeftToRight
        measurements.removeAll(keepingCapacity: true)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func measurement(width: CGFloat) -> Measurement {
        if let cached = measurements[width] { return cached }
        measurementCount += 1
        let proposal = CGSize(width: width, height: .greatestFiniteMagnitude)
        let full = fullMeasurer.sizeThatFits(proposal).height
        let collapsed = collapsedMeasurer.sizeThatFits(proposal).height
        let showsButton = !(textLabel.text ?? "").isEmpty && (expanded || full > collapsed + 0.5)
        let buttonSize = foldButton.titleLabel?.sizeThatFits(proposal) ?? .zero
        func rounded(_ value: CGFloat) -> CGFloat { ceil(value * scale) / scale }
        let result = Measurement(textHeight: rounded(expanded ? full : collapsed),
            buttonSize: CGSize(width: min(width, rounded(buttonSize.width)), height: rounded(buttonSize.height)),
            showsButton: showsButton)
        if measurements.count >= 4 { measurements.removeAll(keepingCapacity: true) }
        measurements[width] = result
        return result
    }

    func measuredSize(width: CGFloat) -> CGSize {
        guard width.isFinite, width > 0 else { return .zero }
        return CGSize(width: width, height: measurement(width: width).height)
    }

    override var intrinsicContentSize: CGSize {
        guard bounds.width > 0 else { return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
        return CGSize(width: UIView.noIntrinsicMetric, height: measuredSize(width: bounds.width).height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let layout = measurement(width: bounds.width)
        textLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: layout.textHeight)
        foldButton.isHidden = !layout.showsButton
        foldButton.isAccessibilityElement = layout.showsButton
        foldButton.isEnabled = layout.showsButton
        foldButton.frame = layout.showsButton
            ? CGRect(x: rightToLeft ? bounds.width - layout.buttonSize.width : 0,
                     y: layout.textHeight + 2, width: layout.buttonSize.width, height: layout.buttonSize.height)
            : .zero
    }

    @objc private func openText() { onOpen?() }
    @objc private func toggle() { guard !foldButton.isHidden else { return }; onToggle?() }
}

private struct FocusDynamicMediaCover: View {
    let url: URL?
    let referer: String
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            FocusRemoteImage(url: url, referer: referer) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                case .failure:
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill))
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemFill))
                        ProgressView()
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color(uiColor: .secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FocusKindBadge: View {
    let kind: DynamicCard.Kind

    private var title: String {
        switch kind {
        case .text:
            return "文本"
        case .image:
            return "图文"
        case .video:
            return "视频"
        case .articleLike:
            return "专栏"
        }
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(FocusDesign.primary.opacity(0.12))
            .foregroundStyle(FocusDesign.primary)
            .clipShape(Capsule())
    }
}
#endif

