#if canImport(UIKit)
import Combine
import FocusCore
import Foundation
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

    private(set) var scrollOffsetY: CGFloat = 0
    private(set) var scrollRestorationRevision = 0

    private let service: DynamicFeedService
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var nextOffset: String?

    init(service: DynamicFeedService) {
        self.service = service
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
    }

    func suspend() {
        task?.cancel()
        task = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
        if case .loading = state {
            state = .idle
        }
    }

    func loadIfNeeded() {
        guard case .idle = state else {
            return
        }

        startReload(forceRefresh: false)
    }

    func reload() {
        resetScrollPosition()
        startReload(forceRefresh: true)
    }

    private func startReload(forceRefresh: Bool) {
        task?.cancel()
        task = Task { [weak self] in
            await self?.performReload(forceRefresh: forceRefresh)
        }
    }

    func refresh() async {
        resetScrollPosition()
        task?.cancel()
        task = nil
        await performReload(forceRefresh: true)
    }

    func loadMoreIfNeeded(currentCardID: String) {
        guard
            case let .loaded(cards) = state,
            shouldLoadMore(after: currentCardID, in: cards),
            !isLoadingMore,
            let nextOffset,
            !nextOffset.isEmpty
        else {
            return
        }

        isLoadingMore = true
        let currentCards = cards

        loadMoreTask?.cancel()
        loadMoreTask = Task { [service] in
            do {
                let page = try await service.fetchFollowingFeedPage(offset: nextOffset)
                guard !Task.isCancelled else {
                    return
                }

                let mergedCards = mergeCards(currentCards, with: page.cards)
                self.nextOffset = page.nextOffset
                self.knownAuthors = mergeAuthors(from: mergedCards)
                state = .loaded(mergedCards)
            } catch let error as DynamicFeedService.ServiceError {
                guard !Task.isCancelled else {
                    return
                }

                if error == .loginRequired {
                    self.nextOffset = nil
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
            }

            if !Task.isCancelled {
                isLoadingMore = false
            }
        }
    }

    func selectFilter(_ filter: FocusDynamicFilterKind) {
        guard selectedFilter != filter else {
            return
        }
        selectedFilter = filter
        resetScrollPosition()
    }

    func updateScrollOffset(_ offsetY: CGFloat) {
        scrollOffsetY = max(offsetY, 0)
    }

    private func resetScrollPosition() {
        scrollOffsetY = 0
        scrollRestorationRevision &+= 1
    }

    private func shouldLoadMore(after currentCardID: String, in cards: [DynamicCard]) -> Bool {
        guard let currentIndex = cards.firstIndex(where: { $0.id == currentCardID }) else {
            return false
        }

        return currentIndex >= max(cards.count - 4, 0)
    }

    private func performReload(forceRefresh: Bool) async {
        loadMoreTask?.cancel()
        nextOffset = nil
        isLoadingMore = false
        state = .loading

        do {
            let page = if forceRefresh {
                try await service.refreshFollowingFeedPage()
            } else {
                try await service.fetchFollowingFeedPage()
            }
            guard !Task.isCancelled else {
                return
            }

            var mergedCards = page.cards
            var finalNextOffset = page.nextOffset

            if let secondOffset = page.nextOffset, !secondOffset.isEmpty {
                do {
                    let secondPage = if forceRefresh {
                        try await service.refreshFollowingFeedPage(offset: secondOffset)
                    } else {
                        try await service.fetchFollowingFeedPage(offset: secondOffset)
                    }
                    guard !Task.isCancelled else {
                        return
                    }

                    mergedCards = mergeCards(mergedCards, with: secondPage.cards)
                    finalNextOffset = secondPage.nextOffset
                } catch {
                    finalNextOffset = page.nextOffset
                }
            }

            nextOffset = finalNextOffset
            knownAuthors = mergeAuthors(from: mergedCards)
            state = .loaded(mergedCards)
        } catch let error as DynamicFeedService.ServiceError {
            guard !Task.isCancelled else {
                return
            }

            switch error {
            case .loginRequired:
                state = .loginRequired(error.localizedDescription)
            default:
                state = .failed(error.localizedDescription)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
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

    private func mergeAuthors(from cards: [DynamicCard]) -> [DynamicCard.Author] {
        var seen = Set<String>()
        return cards.compactMap { card in
            let key = card.author.mid > 0 ? "mid:\(card.author.mid)" : "name:\(card.author.name)"
            guard seen.insert(key).inserted else {
                return nil
            }
            return card.author
        }
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
    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
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

                            Button("重新加载", action: viewModel.reload)
                                .buttonStyle(.borderedProminent)
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
                                onOpenCard: { onOpenCard(card) },
                                onOpenUser: onOpenUser,
                                onOpenImage: { index in
                                    galleryRequest = FocusImageGalleryRequest(
                                        urls: card.coverURLs,
                                        initialIndex: index,
                                        referer: card.targetURL.absoluteString
                                    )
                                }
                            )
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentCardID: card.id)
                            }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 126)
                .background {
                    FocusDynamicFeedScrollBridge(
                        offsetY: viewModel.scrollOffsetY,
                        restorationRevision: viewModel.scrollRestorationRevision,
                        isActive: isActive,
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
            .task(id: filteredCards.map(\.id)) {
                await prefetchImages(for: filteredCards)
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

    private func prefetchImages(for cards: [DynamicCard]) async {
        for card in cards.prefix(8) {
            let urls = ([card.author.avatarURL] + Array(card.coverURLs.prefix(2))).compactMap { $0 }
            guard !urls.isEmpty else {
                continue
            }
            await FocusRemoteImageLoader.prefetch(urls: urls, referer: card.targetURL.absoluteString)
        }
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

private struct FocusDynamicFeedScrollBridge: UIViewRepresentable {
    let offsetY: CGFloat
    let restorationRevision: Int
    let isActive: Bool
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
    final class Coordinator {
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var restorationWorkItem: DispatchWorkItem?
        private var appliedRestorationRevision: Int?
        private var requestedOffsetY: CGFloat = 0
        private var restorationRevision = 0
        private var restorationGeneration = 0
        private var isActive = false
        private var onOffsetChange: (@MainActor (CGFloat) -> Void)?

        func update(
            probe: FocusDynamicFeedScrollProbeView,
            offsetY: CGFloat,
            restorationRevision: Int,
            isActive: Bool,
            onOffsetChange: @escaping @MainActor (CGFloat) -> Void
        ) {
            let shouldFreezeCurrentPosition = self.isActive && !isActive
            requestedOffsetY = max(offsetY, 0)
            self.restorationRevision = restorationRevision
            self.isActive = isActive
            self.onOffsetChange = onOffsetChange
            if shouldFreezeCurrentPosition {
                freezeCurrentPosition()
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
                appliedRestorationRevision = nil
                observation = resolvedScrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, change in
                    let observedOffsetY = change.newValue?.y
                    Task { @MainActor [weak self] in
                        guard let self, let scrollView = self.scrollView else {
                            return
                        }
                        guard self.isActive else {
                            return
                        }
                        // SwiftUI may change contentOffset while removing the hierarchy
                        // or recalculating safe-area insets. Only a gesture-driven change
                        // is a position the user intentionally chose and is safe to persist.
                        let panState = scrollView.panGestureRecognizer.state
                        let isUserDriven = FocusDynamicFeedScrollRestorationPolicy.shouldPersistObservedOffset(
                            isTracking: scrollView.isTracking,
                            isDragging: scrollView.isDragging,
                            isDecelerating: scrollView.isDecelerating,
                            isPanActive: panState == .began || panState == .changed
                        )
                        guard isUserDriven else {
                            return
                        }
                        let contentOffsetY = observedOffsetY ?? scrollView.contentOffset.y
                        let minimumY = -scrollView.adjustedContentInset.top
                        let normalizedOffsetY = FocusDynamicFeedScrollRestorationPolicy.normalizedOffset(
                            contentOffsetY: contentOffsetY,
                            minimumY: minimumY
                        )
                        // A real gesture wins over a pending delayed restoration.
                        self.cancelRestoration()
                        self.requestedOffsetY = normalizedOffsetY
                        self.onOffsetChange?(normalizedOffsetY)
                    }
                }
            }
            guard appliedRestorationRevision != restorationRevision else {
                return
            }
            appliedRestorationRevision = restorationRevision
            startRestoration()
        }

        func detach() {
            cancelRestoration()
            observation?.invalidate()
            observation = nil
            scrollView = nil
            appliedRestorationRevision = nil
        }

        private func startRestoration() {
            cancelRestoration()
            restorationGeneration &+= 1
            restoreOffset(attempt: 0, generation: restorationGeneration)
        }

        private func cancelRestoration() {
            restorationGeneration &+= 1
            restorationWorkItem?.cancel()
            restorationWorkItem = nil
        }

        private func freezeCurrentPosition() {
            guard let scrollView else {
                return
            }

            cancelRestoration()
            let contentOffset = scrollView.contentOffset
            scrollView.setContentOffset(contentOffset, animated: false)
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
                  let scrollView,
                  scrollView.window != nil
            else {
                return
            }

            scrollView.layoutIfNeeded()
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
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: placement.contentOffsetY),
                animated: false
            )

            guard !placement.reachedTarget else {
                restorationWorkItem = nil
                return
            }

            // LazyVStack initially reports only a partial content height. Keep the
            // original target intact while it materializes instead of saving the
            // temporary clamped offset and jumping to it on the next update.
            guard attempt < 30 else {
                restorationWorkItem = nil
                requestedOffsetY = placement.normalizedOffsetY
                onOffsetChange?(placement.normalizedOffsetY)
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

private final class FocusDynamicFeedScrollProbeView: UIView {
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

private struct FocusDynamicCardView: View {
    let card: DynamicCard
    let onOpenCard: () -> Void
    let onOpenUser: (Int64) -> Void
    let onOpenImage: (Int) -> Void
    @State private var areImagesExpanded = false

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
                    onOpenCard: onOpenCard
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

private struct FocusExpandableDynamicText: View {
    let text: String
    let onOpenCard: () -> Void
    @State private var isExpanded = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var canFold: Bool {
        fullHeight > collapsedHeight + 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(isExpanded ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenCard)
                .background {
                    FocusDynamicTextMeasurement(text: text)
                }
                .onPreferenceChange(FocusCollapsedDynamicTextHeightKey.self) { height in
                    collapsedHeight = height
                }
                .onPreferenceChange(FocusFullDynamicTextHeightKey.self) { height in
                    fullHeight = height
                }

            if canFold || isExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "收起文本" : "展开全文")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FocusDesign.primary)
            }
        }
    }
}

private struct FocusDynamicTextMeasurement: View {
    let text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(.body)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: FocusCollapsedDynamicTextHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }

            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: FocusFullDynamicTextHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .allowsHitTesting(false)
    }
}

private struct FocusCollapsedDynamicTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FocusFullDynamicTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
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

