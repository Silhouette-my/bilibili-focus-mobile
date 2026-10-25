#if canImport(UIKit)
import Combine
import FocusCore
import Foundation
import SwiftUI
import UIKit

@MainActor
final class FocusSearchResultsViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded([SearchResultSection])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var selectedFilter: SearchResultFilter = .all
    @Published private(set) var selectedVideoSort: SearchVideoSortOption = .default
    @Published private(set) var currentQuery: SearchQuery?
    @Published private(set) var isLoadingMore = false

    let availableFilters = SearchResultFilter.defaultOrder
    let availableVideoSortOptions = SearchVideoSortOption.allCases

    private let service: SearchResultService
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var cache: [SearchResultFilter: SearchResultPage] = [:]
    private var nextPageByFilter: [SearchResultFilter: Int] = [:]

    init(service: SearchResultService) {
        self.service = service
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
    }

    func loadIfNeeded() {
        guard currentQuery != nil, case .idle = state else {
            return
        }
        reload()
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

    func search(_ query: SearchQuery) {
        currentQuery = query
        selectedFilter = .all
        selectedVideoSort = .default
        cache.removeAll()
        nextPageByFilter.removeAll()
        reload()
    }

    func reload() {
        suspend()
        guard let query = currentQuery, !query.keyword.isEmpty else {
            state = .idle
            return
        }

        let filter = selectedFilter
        let videoSort = filter == .video ? selectedVideoSort : .default
        state = .loading
        task = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let page = try await service.fetchPage(
                    for: query,
                    filter: filter,
                    page: 1,
                    videoSort: videoSort
                )
                guard !Task.isCancelled else {
                    return
                }

                cachePage(page, for: filter)
                state = .loaded(page.sections)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func refresh() async {
        cache[selectedFilter] = nil
        nextPageByFilter[selectedFilter] = nil
        reload()
        await task?.value
    }

    func selectFilter(_ filter: SearchResultFilter) {
        guard selectedFilter != filter else {
            return
        }

        suspend()
        selectedFilter = filter
        if let cachedPage = cache[filter] {
            cachePage(cachedPage, for: filter)
            state = .loaded(cachedPage.sections)
            return
        }

        reload()
    }

    func selectVideoSort(_ sort: SearchVideoSortOption) {
        guard selectedVideoSort != sort else {
            return
        }

        selectedVideoSort = sort
        cache[.video] = nil
        nextPageByFilter[.video] = nil

        if selectedFilter == .video {
            reload()
        }
    }

    func loadMoreIfNeeded(currentItemID: String, in section: SearchResultSection) {
        guard
            let query = currentQuery,
            case let .loaded(sections) = state,
            let activeSection = sections.first(where: { $0.id == section.id }),
            shouldLoadMore(after: currentItemID, in: activeSection.items),
            !isLoadingMore
        else {
            return
        }

        let pagingFilter = selectedFilter == .all ? section.filter : selectedFilter
        guard pagingFilter == .video,
              let nextPage = nextPageByFilter[pagingFilter]
        else {
            return
        }

        isLoadingMore = true
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let currentVideoSort = pagingFilter == .video ? selectedVideoSort : .default
                let extraPage = try await service.fetchPage(
                    for: query,
                    filter: pagingFilter,
                    page: nextPage,
                    videoSort: currentVideoSort
                )
                guard !Task.isCancelled else {
                    return
                }

                let mergedSections = merge(
                    currentSections: sections,
                    extraSections: extraPage.sections,
                    targetFilter: pagingFilter
                )
                let mergedVideoSections = mergedSectionsForCache(
                    existing: cache[pagingFilter]?.sections ?? [],
                    incoming: extraPage.sections,
                    targetFilter: pagingFilter
                )
                cachePage(
                    SearchResultPage(
                        sections: mergedVideoSections,
                        nextPage: extraPage.nextPage
                    ),
                    for: pagingFilter
                )

                if selectedFilter == .all {
                    cachePage(
                        SearchResultPage(
                            sections: mergedSections,
                            nextPage: extraPage.nextPage
                        ),
                        for: .all
                    )
                }
                state = .loaded(mergedSections)
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

    private func shouldLoadMore(after currentItemID: String, in items: [SearchResultItem]) -> Bool {
        guard let currentIndex = items.firstIndex(where: { $0.id == currentItemID }) else {
            return false
        }

        return currentIndex >= max(items.count - 4, 0)
    }

    private func merge(
        currentSections: [SearchResultSection],
        extraSections: [SearchResultSection],
        targetFilter: SearchResultFilter
    ) -> [SearchResultSection] {
        currentSections.map { section in
            guard section.filter == targetFilter,
                  let incomingSection = extraSections.first(where: { $0.filter == targetFilter })
            else {
                return section
            }

            return SearchResultSection(
                filter: section.filter,
                items: mergeItems(existing: section.items, incoming: incomingSection.items)
            )
        }
    }

    private func mergedSectionsForCache(
        existing: [SearchResultSection],
        incoming: [SearchResultSection],
        targetFilter: SearchResultFilter
    ) -> [SearchResultSection] {
        if existing.isEmpty {
            return incoming
        }

        return merge(currentSections: existing, extraSections: incoming, targetFilter: targetFilter)
    }

    private func mergeItems(existing: [SearchResultItem], incoming: [SearchResultItem]) -> [SearchResultItem] {
        var merged = existing
        var seen = Set(existing.map(\.id))

        for item in incoming where seen.insert(item.id).inserted {
            merged.append(item)
        }

        return merged
    }

    private func cachePage(_ page: SearchResultPage, for filter: SearchResultFilter) {
        cache[filter] = page
        nextPageByFilter[filter] = page.nextPage

        guard filter == .all,
              let videoSection = page.sections.first(where: { $0.filter == .video })
        else {
            return
        }

        let videoPage = SearchResultPage(
            sections: [videoSection],
            nextPage: page.nextPage
        )
        cache[.video] = videoPage
        nextPageByFilter[.video] = page.nextPage
    }
}

struct FocusSearchResultsView: View {
    @ObservedObject var viewModel: FocusSearchResultsViewModel
    let onOpenItem: (SearchResultItem) -> Void
    let onOpenPreview: (SearchResultItem.PreviewVideo) -> Void
    let onEditQuery: () -> Void

    var body: some View {
        content
            .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            FocusStateView(
                title: "还没有搜索内容",
                message: "点底栏里的“搜索”输入关键词。",
                buttonTitle: "开始搜索",
                action: onEditQuery
            )

        case .loading:
            ProgressView("加载搜索结果…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .loaded(sections):
            if sections.isEmpty {
                FocusStateView(
                    title: "没有找到结果",
                    message: "换个关键词试试，或者稍后再搜一次。",
                    buttonTitle: "重新搜索",
                    action: onEditQuery
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        FocusSearchQueryButton(
                            title: viewModel.currentQuery?.keyword ?? "搜索",
                            isVideoSortEnabled: viewModel.selectedFilter == .video,
                            selectedVideoSort: viewModel.selectedVideoSort,
                            availableVideoSortOptions: viewModel.availableVideoSortOptions,
                            onSelectVideoSort: viewModel.selectVideoSort,
                            action: onEditQuery
                        )

                        FocusSearchFilterStrip(
                            filters: viewModel.availableFilters,
                            selectedFilter: viewModel.selectedFilter,
                            onSelect: viewModel.selectFilter
                        )

                        ForEach(sections) { section in
                            FocusSearchSectionView(
                                section: section,
                                isLoadingMore: viewModel.isLoadingMore && section.filter == .video,
                                onOpenItem: onOpenItem,
                                onOpenPreview: onOpenPreview,
                                onLoadMoreTrigger: { item in
                                    viewModel.loadMoreIfNeeded(currentItemID: item.id, in: section)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 126)
                }
                .refreshable {
                    await viewModel.refresh()
                }
                .task(id: prefetchSignature(for: sections)) {
                    await prefetchImages(for: sections)
                }
            }

        case let .failed(message):
            FocusStateView(
                title: "搜索加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )
        }
    }

    private func prefetchSignature(for sections: [SearchResultSection]) -> String {
        sections
            .flatMap(\.items)
            .prefix(12)
            .map(\.id)
            .joined(separator: "|")
    }

    private func prefetchImages(for sections: [SearchResultSection]) async {
        for item in sections.flatMap(\.items).prefix(10) {
            let urls = ([item.coverURL, item.avatarURL] + item.previews.prefix(3).map(\.coverURL)).compactMap { $0 }
            guard !urls.isEmpty else {
                continue
            }

            await FocusRemoteImageLoader.prefetch(
                urls: urls,
                referer: item.targetURL.absoluteString
            )
        }
    }
}

struct FocusSearchQueryButton: View {
    let title: String
    let isVideoSortEnabled: Bool
    let selectedVideoSort: SearchVideoSortOption
    let availableVideoSortOptions: [SearchVideoSortOption]
    let onSelectVideoSort: (SearchVideoSortOption) -> Void
    var inactiveAccessorySystemImage: String = "slider.horizontal.3"
    let action: () -> Void

    init(
        title: String,
        isVideoSortEnabled: Bool = false,
        selectedVideoSort: SearchVideoSortOption = .default,
        availableVideoSortOptions: [SearchVideoSortOption] = [],
        onSelectVideoSort: @escaping (SearchVideoSortOption) -> Void = { _ in },
        inactiveAccessorySystemImage: String = "slider.horizontal.3",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isVideoSortEnabled = isVideoSortEnabled
        self.selectedVideoSort = selectedVideoSort
        self.availableVideoSortOptions = availableVideoSortOptions
        self.onSelectVideoSort = onSelectVideoSort
        self.inactiveAccessorySystemImage = inactiveAccessorySystemImage
        self.action = action
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: 24)

            if isVideoSortEnabled {
                Menu {
                    ForEach(availableVideoSortOptions) { option in
                        Button {
                            onSelectVideoSort(option)
                        } label: {
                            if option == selectedVideoSort {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    filterLabel(accented: selectedVideoSort != .default)
                }
                .buttonStyle(.plain)
            } else {
                inactiveAccessoryLabel
                    .opacity(0.48)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func filterLabel(accented: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))

            if isVideoSortEnabled {
                Text(selectedVideoSort.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(accented ? FocusDesign.primary : .secondary)
    }

    private var inactiveAccessoryLabel: some View {
        Image(systemName: inactiveAccessorySystemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct FocusSearchFilterStrip: View {
    let filters: [SearchResultFilter]
    let selectedFilter: SearchResultFilter
    let onSelect: (SearchResultFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filters) { filter in
                    Button(filter.title) {
                        onSelect(filter)
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedFilter == filter ? FocusDesign.primary : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(selectedFilter == filter ? FocusDesign.primary.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay {
                        Capsule()
                            .stroke(selectedFilter == filter ? FocusDesign.primary.opacity(0.22) : Color.clear, lineWidth: 1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct FocusSearchSectionView: View {
    let section: SearchResultSection
    let isLoadingMore: Bool
    let onOpenItem: (SearchResultItem) -> Void
    let onOpenPreview: (SearchResultItem.PreviewVideo) -> Void
    let onLoadMoreTrigger: (SearchResultItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 2)

            switch section.filter {
            case .video:
                LazyVGrid(columns: videoColumns, spacing: 10) {
                    ForEach(section.items) { item in
                        Button {
                            onOpenItem(item)
                        } label: {
                            FocusSearchVideoCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            onLoadMoreTrigger(item)
                        }
                    }
                }

            case .users:
                LazyVStack(spacing: 10) {
                    ForEach(section.items) { item in
                        FocusSearchUserCard(
                            item: item,
                            onOpenItem: onOpenItem,
                            onOpenPreview: onOpenPreview
                        )
                    }
                }

            case .live:
                LazyVGrid(columns: videoColumns, spacing: 10) {
                    ForEach(section.items) { item in
                        Button {
                            onOpenItem(item)
                        } label: {
                            FocusSearchLiveCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .bangumi, .film:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(section.items) { item in
                            Button {
                                onOpenItem(item)
                            } label: {
                                FocusSearchMediaCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

            case .all:
                EmptyView()
            }

            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    private var videoColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
    }
}

private struct FocusSearchVideoCard: View {
    let item: SearchResultItem

    var body: some View {
        FocusTwoColumnVideoCard(content: .init(item: item))
    }
}

private struct FocusSearchUserCard: View {
    let item: SearchResultItem
    let onOpenItem: (SearchResultItem) -> Void
    let onOpenPreview: (SearchResultItem.PreviewVideo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                onOpenItem(item)
            } label: {
                HStack(spacing: 12) {
                    avatar

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        if !item.metadataText.isEmpty {
                            Text(item.metadataText)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            if !item.previews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(item.previews) { preview in
                            Button {
                                onOpenPreview(preview)
                            } label: {
                                FocusSearchPreviewCard(preview: preview)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = item.avatarURL {
            FocusRemoteImage(url: avatarURL, referer: item.targetURL.absoluteString) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                case .empty:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
        }
    }
}

private struct FocusSearchPreviewCard: View {
    let preview: SearchResultItem.PreviewVideo

    private let cardWidth: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FocusSearchCover(
                url: preview.coverURL,
                referer: preview.targetURL.absoluteString,
                height: 76,
                badgeText: preview.badgeText,
                cornerRadius: 12
            )
            .frame(width: cardWidth)

            Text(preview.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: cardWidth, alignment: .leading)

            if !preview.metadataText.isEmpty {
                Text(preview.metadataText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cardWidth, alignment: .leading)
    }
}

private struct FocusSearchLiveCard: View {
    let item: SearchResultItem

    var body: some View {
        FocusTwoColumnVideoCard(content: .init(item: item))
    }
}

struct FocusTwoColumnVideoCardContent {
    let title: String
    let subtitle: String
    let metadataText: String
    let badgeText: String
    let coverURL: URL?
    let referer: String

    init(item: SearchResultItem) {
        title = item.title
        subtitle = item.subtitle
        metadataText = item.metadataText
        badgeText = item.badgeText
        coverURL = item.coverURL
        referer = item.targetURL.absoluteString
    }

    init(video: FocusUserSpaceVideo) {
        title = video.title
        let combinedSubtitle: String
        switch (video.playText.isEmpty, video.publishText.isEmpty) {
        case (false, false):
            combinedSubtitle = "\(video.playText) · \(video.publishText)"
        case (false, true):
            combinedSubtitle = video.playText
        case (true, false):
            combinedSubtitle = video.publishText
        case (true, true):
            combinedSubtitle = ""
        }
        subtitle = combinedSubtitle
        metadataText = ""
        badgeText = video.durationText
        coverURL = video.coverURL
        referer = video.targetURL?.absoluteString ?? "https://space.bilibili.com/"
    }

    init(history item: FocusMyHistoryItem) {
        title = item.title
        subtitle = item.authorName
        metadataText = FocusHistoryCardFormatter.metadataText(for: item)
        badgeText = FocusHistoryCardFormatter.durationText(progress: item.progress, duration: item.duration)
        coverURL = item.coverURL
        referer = item.videoURL?.absoluteString ?? "https://www.bilibili.com/"
    }

    init(favorite item: FocusMyFavoriteItem) {
        title = item.title
        subtitle = item.authorName
        metadataText = item.playText
        badgeText = item.durationText
        coverURL = item.coverURL
        referer = item.videoURL?.absoluteString ?? "https://www.bilibili.com/"
    }
}

enum FocusHistoryCardFormatter {
    static func metadataText(for item: FocusMyHistoryItem) -> String {
        let parts = [progressText(for: item), viewAtText(item.viewAt)]
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    static func durationText(progress: Int64, duration: Int64) -> String {
        guard duration > 0 else {
            return ""
        }
        let effectiveProgress = progress > 0 ? min(progress, duration) : duration
        return "\(formatDuration(effectiveProgress))/\(formatDuration(duration))"
    }

    private static func progressText(for item: FocusMyHistoryItem) -> String {
        guard item.duration > 0 else {
            return ""
        }
        if item.progress <= 0 {
            return "未开始"
        }
        if item.progress >= max(0, item.duration - 5) {
            return "已看完"
        }
        return "看到 \(formatDuration(item.progress))"
    }

    private static func viewAtText(_ timestamp: Int64) -> String {
        guard timestamp > 0 else {
            return ""
        }

        let interval = Int64(Date().timeIntervalSince1970) - timestamp
        switch interval {
        case ..<0:
            return ""
        case 0 ..< 3600:
            return "\(max(1, interval / 60)) 分钟前"
        case 3600 ..< 86_400:
            return "\(interval / 3600) 小时前"
        case 86_400 ..< 604_800:
            return "\(interval / 86_400) 天前"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
        }
    }

    private static func formatDuration(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return "00:00"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%lld:%02lld:%02lld", hours, minutes, remainingSeconds)
        }
        return String(format: "%02lld:%02lld", minutes, remainingSeconds)
    }
}

struct FocusTwoColumnVideoCard: View {
    let content: FocusTwoColumnVideoCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FocusSearchCover(
                url: content.coverURL,
                referer: content.referer,
                height: 104,
                badgeText: content.badgeText,
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(content.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 44, alignment: .topLeading)

                Text(content.subtitle.isEmpty ? " " : content.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 16, alignment: .topLeading)

                Text(content.metadataText.isEmpty ? " " : content.metadataText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 14, alignment: .topLeading)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct FocusSearchMediaCard: View {
    let item: SearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FocusSearchCover(
                url: item.coverURL,
                referer: item.targetURL.absoluteString,
                height: 186,
                badgeText: item.badgeText,
                cornerRadius: 14
            )
            .frame(width: 138)

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !item.metadataText.isEmpty || !item.descriptionText.isEmpty {
                Text(!item.metadataText.isEmpty ? item.metadataText : item.descriptionText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: 138, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FocusSearchCover: View {
    let url: URL?
    let referer: String
    let height: CGFloat
    let badgeText: String
    let cornerRadius: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url {
                    FocusRemoteImage(url: url, referer: referer) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Rectangle()
                                .fill(Color(uiColor: .tertiarySystemFill))
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 0)
                                    .fill(Color(uiColor: .tertiarySystemFill))
                                ProgressView()
                            }
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()

            if !badgeText.isEmpty {
                Text(badgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.62))
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct FocusSearchEntryView: View {
    @Binding var keyword: String
    let onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("关键词") {
                    TextField("输入搜索内容", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            onSubmit()
                        }
                }

                Section {
                    Button("搜索") {
                        onSubmit()
                    }
                    .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("搜索")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .task {
                isTextFieldFocused = true
            }
        }
    }
}
#endif
