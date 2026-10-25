#if canImport(UIKit)
import FocusCore
import SwiftUI
import UIKit

enum FocusDesign {
    static var primary: Color { .accentColor }
    static var primaryLight: Color { primary.opacity(0.12) }
    static var primaryStroke: Color { primary.opacity(0.22) }
    static let tabInactive = Color(red: 0.55, green: 0.58, blue: 0.63) // #8C94A1
    static let videoControlForeground = Color(uiColor: .label)
    static let chromeButtonBackground = Color(uiColor: .secondarySystemBackground)
    static let chromePanelBackground = Color(uiColor: .systemBackground)
}

struct FocusBrowserView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var settingsStore: FocusSettingsStore
    @StateObject private var viewModel: FocusAppViewModel
    /// The last reading viewport. Covered details must not reflow the feed.
    @State private var dynamicFeedLayoutSize: CGSize?
    @State private var isPreparingDynamicFeedReturn = false
    private let appGraph: FocusAppGraph

    init(appGraph: FocusAppGraph, appViewModel: FocusAppViewModel? = nil) {
        self.appGraph = appGraph
        _settingsStore = StateObject(wrappedValue: appGraph.settingsStore)
        _viewModel = StateObject(wrappedValue: appViewModel ?? appGraph.makeAppViewModel())
    }

    init(settingsStore store: FocusSettingsStore) {
        self.init(appGraph: FocusAppGraph(settingsStore: store))
    }

    var body: some View {
        NavigationStack {
            // Detail ideal sizes no longer participate in the feed's layout.
            // The proposal comes from the navigation viewport, not a sibling
            // player, error state, control dock or web view. Safe areas remain
            // system supplied; no screen height or inset is frozen/hard-coded.
            GeometryReader { viewport in
                ZStack(alignment: .topLeading) {
                    Color(uiColor: .systemGroupedBackground)
                    persistentDynamicFeedLayer(viewportSize: viewport.size)
                }
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
                .onAppear { recordDynamicFeedLayoutSize(viewport.size) }
                .onChange(of: viewport.size) { recordDynamicFeedLayoutSize($0) }
                .onChange(of: viewModel.isDynamicFeedActive) { _ in
                    recordDynamicFeedLayoutSize(viewport.size)
                }
                .overlay {
                    ZStack {
                        browserLayer
                        activeNativeContentLayer
                    }
                    .padding(
                        .bottom,
                        (viewModel.isBrowserActive || viewModel.isNativeVideoActive)
                            ? bottomChromeContentInset(safeAreaBottom: viewport.safeAreaInsets.bottom)
                            : 0
                    )
                    .frame(width: viewport.size.width, height: viewport.size.height)
                    .background {
                        if !viewModel.isDynamicFeedActive {
                            Color(uiColor: .systemGroupedBackground)
#if DEBUG
                                .background {
                                    if FocusTestRuntime.isRunningFixtures { FocusDetailCoverFixtureProbe() }
                                }
#endif
                        }
                    }
                    .allowsHitTesting(!viewModel.isDynamicFeedActive)
                    .accessibilityHidden(viewModel.isDynamicFeedActive)
                }
            }
            .overlay(alignment: .leading) {
                if viewModel.showsBackButton {
                    FocusEdgeSwipeBackArea {
                        viewModel.handleTopLevelBack()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                bottomChrome(safeAreaBottom: FocusWindowMetrics.safeAreaBottom)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.showsBackButton {
                        Button {
                            viewModel.handleTopLevelBack()
                        } label: {
                            Label("返回", systemImage: "chevron.left")
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text(viewModel.navigationTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if viewModel.isBrowserActive || viewModel.isNativeVideoActive {
                            Button {
                                viewModel.reloadCurrent()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }

                        Button {
                            viewModel.showSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSettings) {
                FocusSettingsView(
                    appGraph: appGraph,
                    dynamicAuthors: viewModel.dynamicFeedViewModel.knownAuthors
                )
            }
            .sheet(isPresented: $viewModel.showSearch) {
                FocusSearchEntryView(
                    keyword: $viewModel.searchKeyword,
                    onSubmit: viewModel.submitSearch
                )
            }
            .onAppear {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                if viewModel.isBrowserActive {
                    viewModel.browserViewModel.handleDeviceOrientationChange(UIDevice.current.orientation)
                }
            }
            .onDisappear {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                guard viewModel.isBrowserActive else {
                    return
                }
                viewModel.browserViewModel.handleDeviceOrientationChange(UIDevice.current.orientation)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                viewModel.handleAppDidBecomeActive()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                viewModel.handleAppDidEnterBackground()
            }
            .onChange(of: settingsStore.settings.nativeDanmakuEnabled) { enabled in
                viewModel.applyNativeDanmakuPreference(enabled)
            }
            .onChange(of: settingsStore.settings.nativeSubtitleEnabled) { enabled in
                viewModel.applyNativeSubtitlePreference(
                    enabled: enabled,
                    languageCode: settingsStore.settings.nativeSubtitleLanguageCode
                )
            }
            .task {
                viewModel.handleLaunchEntryIfNeeded()
            }
            .task(id: viewModel.isDynamicFeedActive) {
                // Network visibility is not an input to the isolated feed's
                // layout. Its prepared subtree stays identical when uncovered.
                viewModel.dynamicFeedViewModel.setVisibility(viewModel.isDynamicFeedActive)
                if viewModel.isDynamicFeedActive { viewModel.dynamicFeedViewModel.loadIfNeeded() }
            }
        }
    }

    private var browserLayer: some View {
        Group {
            if viewModel.hasInstantiatedBrowser {
                ZStack {
                    FocusWebView(viewModel: viewModel.browserViewModel, settingsStore: settingsStore)
                        .background(colorScheme == .dark ? Color(red: 0.06, green: 0.07, blue: 0.09) : Color(red: 0.965, green: 0.969, blue: 0.98))

                    if let message = viewModel.browserViewModel.webContentFailureMessage {
                        FocusStateView(
                            title: "网页加载失败",
                            message: message,
                            buttonTitle: "重新加载",
                            action: viewModel.browserViewModel.retryAfterWebContentFailure
                        )
                        .background(colorScheme == .dark ? Color(red: 0.06, green: 0.07, blue: 0.09) : Color(red: 0.965, green: 0.969, blue: 0.98))
                    } else if viewModel.browserViewModel.isLoadingPage && !viewModel.browserViewModel.showsNativeVideoControls {
                        (colorScheme == .dark ? Color(red: 0.06, green: 0.07, blue: 0.09) : Color(red: 0.965, green: 0.969, blue: 0.98))
                            .ignoresSafeArea()
                            .overlay {
                                ProgressView()
                                    .scaleEffect(1.2)
                            }
                    }
                }
                .opacity(viewModel.isBrowserActive ? 1 : 0)
                .allowsHitTesting(viewModel.isBrowserActive)
                .accessibilityHidden(!viewModel.isBrowserActive)
            }
        }
    }

    private func recordDynamicFeedLayoutSize(_ size: CGSize) {
        guard viewModel.isDynamicFeedActive, size.width > 0, size.height > 0,
              dynamicFeedLayoutSize != size else { return }
        dynamicFeedLayoutSize = size
    }

    /// Landscape fullscreen rotates the whole scene while the feed is covered.
    /// Both dimensions matter: changing the covered ScrollView's height also
    /// changes lazy-row materialization and can clamp its offset. Only an active
    /// feed adopts a new viewport; a detail's orientation is not a feed resize.
    private func coveredDynamicFeedSize(viewportSize: CGSize) -> CGSize? {
        guard !viewModel.isDynamicFeedActive, !isPreparingDynamicFeedReturn, let size = dynamicFeedLayoutSize,
              size != viewportSize else { return nil }
        return size
    }

    @ViewBuilder
    private func persistentDynamicFeedLayer(viewportSize: CGSize) -> some View {
        let frozenSize = coveredDynamicFeedSize(viewportSize: viewportSize)
        if viewModel.hasDynamicFeedRoot {
            FocusDynamicFeedViewport(
                anchor: viewModel.dynamicFeedViewModel.scrollAnchor,
                returnViewportSize: viewportSize,
                isPreparingReturn: isPreparingDynamicFeedReturn,
                onPrepareReturn: { isPreparingDynamicFeedReturn = true },
                onFinishReturn: { isPreparingDynamicFeedReturn = false },
                content: FocusDynamicFeedView(
                viewModel: viewModel.dynamicFeedViewModel,
                settingsStore: settingsStore,
                // Prepare the exact active subtree under the existing detail
                // cover. Revealing it must not trigger a second lazy layout.
                isActive: viewModel.isDynamicFeedActive || isPreparingDynamicFeedReturn,
                searchPrompt: viewModel.searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "搜索视频、UP主、直播"
                    : viewModel.searchKeyword,
                onOpenCard: { card in
                    viewModel.open(card: card)
                },
                onOpenUser: { mid in
                    guard mid > 0,
                          let url = URL(string: "https://space.bilibili.com/\(mid)")
                    else {
                        return
                    }
                    viewModel.openNativeUserSpace(url)
                },
                onOpenLogin: viewModel.openLogin,
                onSearch: {
                    viewModel.presentSearchEntry()
                }
            ))
            // Use the same explicit proposal while active and covered. Switching
            // from an unconstrained ScrollView to a fixed height changes how its
            // safe-area extension is laid out, even when the numbers look equal.
            .frame(width: frozenSize?.width ?? viewportSize.width,
                   height: frozenSize?.height ?? viewportSize.height,
                   alignment: .topLeading)
            // Retain the rendered list underneath the opaque detail overlay.
            // Visibility changes must not rematerialize the lazy feed itself.
            .allowsHitTesting(viewModel.isDynamicFeedActive)
            .accessibilityHidden(!viewModel.isDynamicFeedActive)
        }
    }

    @ViewBuilder
    private var activeNativeContentLayer: some View {
        switch viewModel.route {
        case .dynamicFeed:
            EmptyView()
        case .searchResults:
            FocusSearchResultsView(
                viewModel: viewModel.searchResultsViewModel,
                onOpenItem: { item in
                    viewModel.open(searchItem: item)
                },
                onOpenPreview: { preview in
                    viewModel.open(searchPreview: preview)
                },
                onEditQuery: {
                    viewModel.presentSearchEntry()
                }
            )
        case .my:
            FocusMyView(
                viewModel: viewModel.myViewModel,
                onOpenLogin: viewModel.openLogin,
                onOpenHistory: viewModel.openHistory,
                onOpenFavoriteFolder: { folder in
                    viewModel.openFavoriteFolder(folder)
                },
                onOpenVideo: { url in
                    viewModel.openMyVideo(url)
                }
            )
        case .history:
            FocusHistoryView(
                viewModel: viewModel.historyViewModel,
                onOpenVideo: { url in
                    viewModel.openMyVideo(url)
                }
            )
        case .favoriteFolder:
            FocusFavoriteFolderView(
                viewModel: viewModel.favoriteFolderViewModel,
                onOpenVideo: { url in
                    viewModel.openMyVideo(url)
                }
            )
        case let .userSpace(routeID, _):
            FocusUserSpaceView(
                viewModel: viewModel.userSpaceViewModel(for: routeID),
                onOpenVideo: { url in
                    viewModel.openOpusRelatedURL(url)
                },
                onOpenCollection: { collection in
                    viewModel.openUserCollection(collection)
                },
                onOpenArticle: { url in
                    viewModel.openOpusRelatedURL(url)
                }
            )
        case let .userCollection(routeID, _):
            FocusUserCollectionView(
                viewModel: viewModel.userCollectionViewModel(for: routeID),
                onOpenVideo: { url in
                    viewModel.openOpusRelatedURL(url)
                }
            )
        case let .article(routeID, _):
            FocusArticleView(
                viewModel: viewModel.articleViewModel(for: routeID),
                onOpenUser: { mid in
                    guard let url = URL(string: "https://space.bilibili.com/\(mid)") else {
                        return
                    }
                    viewModel.openNativeUserSpace(url)
                },
                onOpenURL: { url in viewModel.openOpusRelatedURL(url) },
                onOpenWeb: { url in viewModel.openArticleInBrowser(url) }
            )
        case let .opus(routeID, _):
            FocusOpusDetailView(
                viewModel: viewModel.opusDetailViewModel(for: routeID),
                onOpenURL: { url in
                    viewModel.openOpusRelatedURL(url)
                }
            )
        case let .video(routeID, _):
            FocusNativeVideoDetailView(
                viewModel: viewModel.videoViewModel(for: routeID),
                onOpenUser: { mid in
                    guard let url = URL(string: "https://space.bilibili.com/\(mid)") else {
                        return
                    }
                    viewModel.openNativeUserSpace(url)
                },
                onOpenVideo: { url in
                    viewModel.openNativeVideo(url)
                },
                onOpenURL: { url in
                    viewModel.openOpusRelatedURL(url)
                },
                onOpenWeb: { url in
                    viewModel.openVideoInBrowser(url)
                },
                accentColor: FocusAccentColor.color(hex: settingsStore.settings.accentColorHex)
            )
        case .browser:
            EmptyView()
        }
    }

    private func bottomChrome(safeAreaBottom: CGFloat) -> some View {
        let tabBottomPadding = bottomTabBarPadding(safeAreaBottom: safeAreaBottom)
        let hasVideoControls = viewModel.isBrowserActive && viewModel.browserViewModel.showsNativeVideoControls
        let tabTopPadding = hasVideoControls ? 2.0 : 3.0

        return VStack(spacing: 0) {
            if viewModel.isBrowserActive, viewModel.browserViewModel.showsNativeVideoControls {
                videoControls
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }

            primaryTabBar
                .padding(.horizontal, 18)
                .padding(.top, tabTopPadding)
                .padding(.bottom, tabBottomPadding)
        }
        .background {
            FocusBottomChromeBackground(
                safeAreaBottom: safeAreaBottom,
                isDarkMode: colorScheme == .dark
            )
        }
        .compositingGroup()
        .frame(maxWidth: .infinity, alignment: .bottom)
        .shadow(color: .black.opacity(0.028), radius: 10, y: -1)
    }

    private func bottomChromeContentInset(safeAreaBottom: CGFloat) -> CGFloat {
        let tabInset = 54 + bottomTabBarPadding(safeAreaBottom: safeAreaBottom)
        if viewModel.isBrowserActive, viewModel.browserViewModel.showsNativeVideoControls {
            return tabInset + 74
        }
        return tabInset
    }

    private func bottomTabBarPadding(safeAreaBottom: CGFloat) -> CGFloat {
        max(0, safeAreaBottom * 0.03)
    }

    private var primaryTabBar: some View {
        HStack(spacing: 2) {
            FocusPrimaryTabButton(
                title: "动态",
                systemImage: "square.stack.3d.up.fill",
                isSelected: viewModel.activePrimaryTab == .dynamic
            ) {
                viewModel.open(.dynamic)
            }

            FocusPrimaryTabButton(
                title: "搜索",
                systemImage: "magnifyingglass",
                isSelected: viewModel.activePrimaryTab == .search
            ) {
                viewModel.presentSearchEntry()
            }

            FocusPrimaryTabButton(
                title: "我的",
                systemImage: "person.crop.circle.fill",
                isSelected: viewModel.activePrimaryTab == .my
            ) {
                viewModel.openMy()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
    }

    private var videoControls: some View {
        HStack(spacing: 8) {
            FocusVideoControlButton(
                systemImage: "playpause.fill",
                accessibilityLabel: "播放或暂停"
            ) {
                viewModel.browserViewModel.togglePlayback()
            }

            FocusVideoControlButton(
                systemImage: "speedometer",
                title: "倍速",
                accessibilityLabel: "切换倍速"
            ) {
                viewModel.browserViewModel.cyclePlaybackRate()
            }

            FocusVideoControlButton(
                systemImage: "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: "切换全屏"
            ) {
                if viewModel.browserViewModel.isImmersiveVideo {
                    viewModel.browserViewModel.exitFullscreen()
                } else {
                    viewModel.browserViewModel.requestFullscreen()
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FocusDesign.chromePanelBackground.opacity(colorScheme == .dark ? 0.18 : 0.32))
        )
    }
}

/// The navigation viewport has already accounted for system safe areas. Give
/// the retained feed its own hosting boundary so a covered scene's new safe-area
/// propagation cannot extend or shrink the ScrollView a second time.
private struct FocusDynamicFeedViewport<Content: View>: UIViewControllerRepresentable {
    let anchor: FocusDynamicFeedVisualAnchor
    let returnViewportSize: CGSize
    let isPreparingReturn: Bool
    let onPrepareReturn: () -> Void
    let onFinishReturn: () -> Void
    let content: Content

    func makeUIViewController(context: Context) -> FocusDynamicFeedHostingController<AnyView> {
        let controller = FocusDynamicFeedHostingController(content: hostedContent(environment: context.environment))
        configure(controller, environment: context.environment)
        return controller
    }

    func updateUIViewController(_ controller: FocusDynamicFeedHostingController<AnyView>, context: Context) {
        configure(controller, environment: context.environment)
    }

    private func configure(_ controller: FocusDynamicFeedHostingController<AnyView>, environment: EnvironmentValues) {
        controller.configure(content: hostedContent(environment: environment), anchor: anchor,
                             returnViewportSize: returnViewportSize, isPreparingReturn: isPreparingReturn,
                             onPrepareReturn: onPrepareReturn, onFinishReturn: onFinishReturn)
    }

    private func hostedContent(environment: EnvironmentValues) -> AnyView {
        // A UIKit hosting boundary must not reset the reader's typography,
        // accessibility, layout direction, theme or other inherited choices.
        // The erased concrete root type stays the same on every update.
        AnyView(content.environment(\.self, environment))
    }
}

private final class FocusDynamicFeedHostingController<Content: View>: UIHostingController<Content> {
    private weak var anchor: FocusDynamicFeedVisualAnchor?
    private var returnViewportSize = CGSize.zero
    private var isPreparingReturn = false
    private var hasUncommittedLayout = true
    private var waitsForReturnLayout = false
    private var hasReturnViewport: Bool {
        // UIKit can round SwiftUI's proposed dimensions to the display grid.
        abs(view.bounds.width - returnViewportSize.width) <= 0.5 &&
            abs(view.bounds.height - returnViewportSize.height) <= 0.5
    }

    init(content: Content) {
        super.init(rootView: content)
        if #available(iOS 16.4, *) { safeAreaRegions = [] }
        view.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(content: Content, anchor: FocusDynamicFeedVisualAnchor, returnViewportSize: CGSize,
                   isPreparingReturn: Bool, onPrepareReturn: @escaping () -> Void,
                   onFinishReturn: @escaping () -> Void) {
        self.anchor = anchor
        self.returnViewportSize = returnViewportSize
        self.isPreparingReturn = isPreparingReturn
        hasUncommittedLayout = true
        if isPreparingReturn {
            // A second resize or environment update may arrive after the first
            // layout acknowledgement but before the guarded return finishes.
            waitsForReturnLayout = true
            anchor.isReturnLayoutReady = false
        }
        rootView = content
        view.setNeedsLayout()
        anchor.prepareLayoutForReturn = { [weak self, weak anchor] in
            guard let self, let anchor else { return true }
            let isReady = !hasUncommittedLayout && hasReturnViewport
            waitsForReturnLayout = !isReady
            anchor.isReturnLayoutReady = isReady
            // Even an initially ready viewport must keep following later root
            // updates until identity recovery has actually finished.
            onPrepareReturn()
            if !isReady { view.setNeedsLayout() }
            return isReady
        }
        anchor.finishLayoutForReturn = { [weak self, weak anchor] in
            self?.waitsForReturnLayout = false
            anchor?.isReturnLayoutReady = true
            onFinishReturn()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        hasUncommittedLayout = false
        guard waitsForReturnLayout, isPreparingReturn, hasReturnViewport else { return }
        waitsForReturnLayout = false
        anchor?.isReturnLayoutReady = true
        anchor?.geometryDidChange()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // iOS 16.0–16.3 has no safeAreaRegions. Consume the inherited insets with
        // the public controller API; once they reach zero no further update runs.
        if #unavailable(iOS 16.4) {
            let inset = view.safeAreaInsets
            guard inset != .zero else { return }
            additionalSafeAreaInsets = UIEdgeInsets(
                top: additionalSafeAreaInsets.top - inset.top,
                left: additionalSafeAreaInsets.left - inset.left,
                bottom: additionalSafeAreaInsets.bottom - inset.bottom,
                right: additionalSafeAreaInsets.right - inset.right
            )
        }
    }
}

#if DEBUG
/// Lets integration tests observe when the opaque detail branch actually
/// leaves the UIKit hierarchy, rather than timing only a model flag change.
private struct FocusDetailCoverFixtureProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = "focus-fixture-detail-cover"
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}
#endif

private struct FocusEdgeSwipeBackArea: View {
    let onBack: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard value.translation.width > 80, abs(value.translation.height) < 80 else {
                            return
                        }

                        onBack()
                    }
            )
    }
}

private struct FocusPrimaryTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(
                isSelected
                    ? FocusDesign.primary
                    : FocusDesign.tabInactive
            )
            .padding(.top, 5)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private enum FocusWindowMetrics {
    static var safeAreaBottom: CGFloat {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }),
            let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first
        else {
            return 0
        }

        return window.safeAreaInsets.bottom
    }
}

private struct FocusBottomChromeBackground: View {
    let safeAreaBottom: CGFloat
    let isDarkMode: Bool

    var body: some View {
        ZStack(alignment: .top) {
            FocusVisualEffectBlur(style: isDarkMode ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
                .ignoresSafeArea(edges: .bottom)

            Rectangle()
                .fill(isDarkMode ? Color.black.opacity(0.14) : Color.white.opacity(0.24))
                .ignoresSafeArea(edges: .bottom)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            isDarkMode ? Color.white.opacity(0.08) : Color.white.opacity(0.24),
                            isDarkMode ? Color.black.opacity(0.04) : Color.white.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .bottom)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            isDarkMode ? Color.black.opacity(0.10) : Color.white.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: safeAreaBottom + 30)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            isDarkMode ? Color.white.opacity(0.02) : Color.white.opacity(0.08),
                            isDarkMode ? Color.white.opacity(0.02) : Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .blur(radius: 18)
                .ignoresSafeArea(edges: .bottom)

            Rectangle()
                .fill(isDarkMode ? Color.white.opacity(0.08) : Color.white.opacity(0.34))
                .frame(height: 0.5)
        }
    }
}

struct FocusScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        DispatchQueue.main.async {
            var candidate: UIView? = view
            while let current = candidate {
                if let scrollView = current.superview?.superview as? UIScrollView {
                    scrollView.bounces = false
                    scrollView.alwaysBounceVertical = false
                    break
                }
                candidate = current.superview
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        DispatchQueue.main.async {
            var candidate: UIView? = uiView
            while let current = candidate {
                if let scrollView = current.superview?.superview as? UIScrollView {
                    scrollView.bounces = false
                    scrollView.alwaysBounceVertical = false
                    break
                }
                candidate = current.superview
            }
        }
    }
}

#endif
