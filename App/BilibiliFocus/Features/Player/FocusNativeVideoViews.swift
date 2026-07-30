#if canImport(UIKit)
import AVFoundation
import AVKit
import FocusCore
import Foundation
import SwiftUI
import UIKit

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
                FocusNativeSubtitleOverlay(viewModel: viewModel, isFullscreen: false)
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
                Text("评论 · \(viewModel.displayedCommentCount)")
                    .font(.headline)
                ForEach(viewModel.comments) { comment in
                    FocusNativeVideoCommentRow(
                        viewModel: viewModel,
                        comment: comment,
                        onOpenURL: onOpenURL
                    )
                }
                if viewModel.hasMoreComments {
                    Button(action: viewModel.loadMoreComments) {
                        HStack(spacing: 8) {
                            if viewModel.isLoadingMoreComments {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(viewModel.isLoadingMoreComments ? "正在加载…" : "加载更多评论")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingMoreComments)
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
            FocusNativeSubtitleControl(viewModel: viewModel)
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

private struct FocusNativeSubtitleControl: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: FocusNativeVideoViewModel

    var body: some View {
        Menu {
            if viewModel.isSubtitleEnabled {
                Button {
                    viewModel.disableSubtitles()
                } label: {
                    Label("关闭字幕", systemImage: "captions.bubble")
                }
            } else {
                Button {
                    viewModel.enableSubtitles()
                } label: {
                    Label("开启字幕", systemImage: "captions.bubble.fill")
                }
            }

            if !viewModel.subtitleTracks.isEmpty {
                Divider()
                ForEach(viewModel.subtitleTracks) { track in
                    Button {
                        viewModel.selectSubtitleTrack(track)
                    } label: {
                        if viewModel.isSubtitleEnabled,
                           viewModel.selectedSubtitleTrackID == track.id
                        {
                            Label(track.displayName, systemImage: "checkmark")
                        } else {
                            Text(track.displayName)
                        }
                    }
                    .disabled(track.isLocked)
                }
            }

            switch viewModel.subtitleLoadState {
            case .failed:
                Divider()
                Button("重新加载字幕", action: viewModel.retrySubtitles)
            case .unavailable:
                Text("当前分集暂无字幕")
            case .idle, .loadingTracks, .loadingDocument, .ready:
                EmptyView()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: viewModel.isSubtitleEnabled
                    ? "captions.bubble.fill"
                    : "captions.bubble")
                    .font(.system(size: 15, weight: .semibold))
                Text(viewModel.subtitleControlTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(
                viewModel.isSubtitleEnabled
                    ? FocusSharedDesign.primary
                    : FocusSharedDesign.videoControlForeground
            )
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        viewModel.isSubtitleEnabled
                            ? FocusSharedDesign.primary.opacity(0.16)
                            : FocusSharedDesign.chromeButtonBackground.opacity(
                                colorScheme == .dark ? 0.86 : 0.92
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            viewModel.isSubtitleEnabled
                ? "字幕已开启，\(viewModel.selectedSubtitleTrack?.displayName ?? "正在加载")"
                : "字幕已关闭"
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
    @ObservedObject var viewModel: FocusNativeVideoViewModel
    let comment: FocusVideoComment
    let onOpenURL: (URL) -> Void

    var body: some View {
        let thread = viewModel.commentThreadState(for: comment.id)
        let isExpanded = thread?.isExpanded == true

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

                if !viewModel.replies(for: comment).isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(viewModel.replies(for: comment)) { reply in
                            FocusNativeVideoReplyRow(
                                viewModel: viewModel,
                                reply: reply,
                                onOpenURL: onOpenURL
                            )
                        }
                    }
                    .padding(10)
                    .background(
                        Color(uiColor: .tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }

                if isExpanded {
                    if let errorMessage = thread?.errorMessage {
                        Button {
                            viewModel.retryCommentReplies(for: comment)
                        } label: {
                            Label(
                                "\(errorMessage) · 重试",
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    } else if thread?.nextCursor != nil {
                        Button {
                            viewModel.loadMoreCommentReplies(for: comment)
                        } label: {
                            HStack(spacing: 6) {
                                if thread?.isLoading == true {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                                Text(
                                    thread?.isLoading == true
                                        ? "正在加载回复…"
                                        : "加载更多回复"
                                )
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(FocusSharedDesign.primary)
                        .disabled(thread?.isLoading == true)
                    }
                }

                HStack(spacing: 16) {
                    FocusNativeCommentLikeButton(
                        viewModel: viewModel,
                        comment: comment
                    )
                    if comment.replies > 0 {
                        Button {
                            viewModel.toggleCommentReplies(comment)
                        } label: {
                            HStack(spacing: 5) {
                                if thread?.isLoading == true,
                                   thread?.hasLoadedFirstPage == false
                                {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: isExpanded
                                        ? "chevron.up"
                                        : "bubble.left")
                                }
                                Text(
                                    isExpanded
                                        ? "收起回复"
                                        : "\(FocusNativeVideoFormatting.count(comment.replies)) 回复"
                                )
                            }
                        }
                        .buttonStyle(.plain)
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

private struct FocusNativeVideoReplyRow: View {
    @ObservedObject var viewModel: FocusNativeVideoViewModel
    let reply: FocusVideoComment
    let onOpenURL: (URL) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            FocusRemoteImage(
                url: reply.avatarURL,
                referer: "https://www.bilibili.com/"
            ) { phase in
                Group {
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(reply.authorName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FocusSharedDesign.primary)
                    Text(FocusNativeVideoFormatting.relativeDate(reply.publishedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 4)
                    FocusNativeCommentLikeButton(
                        viewModel: viewModel,
                        comment: reply
                    )
                }
                FocusInlineRichText(
                    runs: reply.contentRuns,
                    font: .caption,
                    foreground: .secondary,
                    onOpenURL: onOpenURL
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FocusNativeCommentLikeButton: View {
    @ObservedObject var viewModel: FocusNativeVideoViewModel
    let comment: FocusVideoComment

    var body: some View {
        let state = viewModel.commentLikeState(for: comment)
        let isLoading = viewModel.commentLikeActionsInFlight.contains(comment.id)

        Button {
            viewModel.toggleCommentLike(comment)
        } label: {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: state.isLiked
                        ? "hand.thumbsup.fill"
                        : "hand.thumbsup")
                }
                if state.likes > 0 {
                    Text(FocusNativeVideoFormatting.count(state.likes))
                }
            }
            .foregroundStyle(state.isLiked ? FocusSharedDesign.primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(
            state.isLiked
                ? "取消点赞评论，当前 \(state.likes) 个赞"
                : "点赞评论，当前 \(state.likes) 个赞"
        )
    }
}

private struct FocusNativeSubtitleOverlay: View {
    @ObservedObject var viewModel: FocusNativeVideoViewModel
    let isFullscreen: Bool

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 0.1,
                paused: !viewModel.isPlaying
            )
        ) { _ in
            let content = viewModel.subtitleText(
                at: viewModel.subtitlePlaybackPositionMilliseconds
            )
            VStack {
                Spacer(minLength: 0)
                if !content.isEmpty {
                    Text(content)
                        .font(
                            .system(
                                size: isFullscreen ? 22 : 17,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            .black.opacity(0.72),
                            in: RoundedRectangle(
                                cornerRadius: 8,
                                style: .continuous
                            )
                        )
                        .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                        .frame(maxWidth: isFullscreen ? 860 : 620)
                        .padding(.horizontal, isFullscreen ? 36 : 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, isFullscreen ? 64 : 14)
        }
        .accessibilityHidden(true)
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
            if viewModel.hasPreparedPlayer, !viewModel.isLoadingPlayback {
                FocusNativePlayerSurface(player: viewModel.player, showsPlaybackControls: true)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.15)
            }
            FocusNativeDanmakuOverlay(viewModel: viewModel)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            FocusNativeSubtitleOverlay(viewModel: viewModel, isFullscreen: true)
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
#endif
