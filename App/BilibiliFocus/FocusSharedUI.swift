#if canImport(UIKit)
import SwiftUI
import UIKit
import ImageIO
import FocusCore

enum FocusSharedDesign {
    static var primary: Color { .accentColor }
    static let videoControlForeground = Color(uiColor: .label)
    static let chromeButtonBackground = Color(uiColor: .secondarySystemBackground)
    static let chromePanelBackground = Color(uiColor: .systemBackground)
}

enum FocusAccentColor {
    static func color(hex rawValue: String) -> Color {
        guard
            let normalized = FocusSettings.normalizedAccentColorHex(rawValue),
            let value = UInt64(normalized.dropFirst(), radix: 16)
        else {
            return color(hex: FocusSettings.defaultAccentColorHex)
        }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    static func hexString(from color: Color) -> String {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return FocusSettings.defaultAccentColorHex
        }
        let channels = [red, green, blue].map { component in
            min(max(Int((component * 255).rounded()), 0), 255)
        }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }
}

private func focusRichTextColor(_ raw: String?) -> Color? {
    guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    if value.hasPrefix("#") { value.removeFirst() }
    if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
    guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
    let alpha: CGFloat
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    if value.count == 8 {
        alpha = CGFloat((number >> 24) & 0xff) / 255
        red = CGFloat((number >> 16) & 0xff) / 255
        green = CGFloat((number >> 8) & 0xff) / 255
        blue = CGFloat(number & 0xff) / 255
    } else {
        alpha = 1
        red = CGFloat((number >> 16) & 0xff) / 255
        green = CGFloat((number >> 8) & 0xff) / 255
        blue = CGFloat(number & 0xff) / 255
    }
    return Color(uiColor: UIColor(red: red, green: green, blue: blue, alpha: alpha))
}

struct FocusStateView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FocusLoginRequiredView: View {
    let title: String
    let message: String
    let reloadTitle: String
    let reloadAction: () -> Void
    let loginAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 16) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 12) {
                        Button(reloadTitle, action: reloadAction)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)

                        Button("去登录", action: loginAction)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom + 132, 156))
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum FocusRemoteImagePhase {
    case empty
    case success(Image)
    case failure
}

struct FocusRemoteImage<Content: View>: View {
    let url: URL?
    let referer: String
    let content: (FocusRemoteImagePhase) -> Content

    @StateObject private var loader: FocusRemoteImageLoader
    @Environment(\.displayScale) private var displayScale
    @State private var measuredPixelSize: Int?

    private struct LoadID: Hashable {
        let url: URL?
        let referer: String
        let pixels: Int?
    }

    init(
        url: URL?,
        referer: String = "https://www.bilibili.com/",
        imageRepository: FocusImageRepository = .shared,
        @ViewBuilder content: @escaping (FocusRemoteImagePhase) -> Content
    ) {
        self.url = url
        self.referer = referer
        self.content = content
        _loader = StateObject(wrappedValue: FocusRemoteImageLoader(repository: imageRepository))
    }

    var body: some View {
        content(displayPhase)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { updateSize(geometry.size) }
                        .onChange(of: geometry.size) { updateSize($0) }
                        .onChange(of: displayScale) { _ in updateSize(geometry.size) }
                }
            }
            .task(id: LoadID(url: url, referer: referer, pixels: measuredPixelSize)) {
                if url == nil { await loader.load(url: nil, referer: referer); return }
                guard let measuredPixelSize else { return }
                await loader.load(url: url, referer: referer, pixelSize: measuredPixelSize)
            }
    }

    private func updateSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        measuredPixelSize = FocusImagePixelSize.bucket(for: size, scale: displayScale)
    }

    private var displayPhase: FocusRemoteImagePhase {
        return loader.phase
    }
}

struct FocusInlineRichText: View {
    let runs: [FocusRichTextRun]
    var font: Font = .body
    var foreground: Color = .primary
    var onOpenURL: (URL) -> Void = { _ in }
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        FocusInlineFlowLayout(spacing: 1) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                switch run {
                case let .text(value, bold, italic, underline, strikethrough, color, linkURL):
                    Text(value)
                        .font(font)
                        .fontWeight(bold ? .semibold : .regular)
                        .italic(italic)
                        .underline(underline)
                        .strikethrough(strikethrough)
                        .foregroundStyle(linkURL == nil ? (focusRichTextColor(color) ?? foreground) : FocusSharedDesign.primary)
                        .onTapGesture {
                            if let linkURL { onOpenURL(linkURL) }
                        }
                case let .emote(alt, url, _, _, _):
                    FocusAnimatedRemoteImage(
                        url: url,
                        alt: alt,
                        pixelSize: FocusImagePixelSize.bucket(for: CGSize(width: 24, height: 24), scale: displayScale)
                    )
                        .frame(width: 24, height: 24)
                        .accessibilityLabel(alt)
                case let .resource(label, url):
                    Text(label)
                        .font(font)
                        .foregroundStyle(FocusSharedDesign.primary)
                        .underline()
                        .onTapGesture { onOpenURL(url) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct FocusInlineFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.init(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += min(size.width, width) + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.init(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .init(width: min(size.width, bounds.width), height: size.height))
            x += min(size.width, bounds.width) + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private final class FocusEmoteImageView: UIView {
    let imageView = UIImageView()
    private let fallbackLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        fallbackLabel.font = .systemFont(ofSize: 10)
        fallbackLabel.textAlignment = .center
        fallbackLabel.adjustsFontSizeToFitWidth = true
        fallbackLabel.minimumScaleFactor = 0.45
        fallbackLabel.numberOfLines = 1
        fallbackLabel.textColor = .label
        addSubview(fallbackLabel)
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        fallbackLabel.frame = bounds
    }

    func prepare(alt: String) {
        accessibilityLabel = alt
        fallbackLabel.text = alt
    }

    func showFallback() {
        imageView.stopAnimating()
        imageView.image = nil
        fallbackLabel.isHidden = false
    }

    func show(_ image: UIImage, animate: Bool) {
        fallbackLabel.isHidden = true
        imageView.image = image
        if animate { imageView.startAnimating() }
    }

    func stopAnimating() {
        imageView.stopAnimating()
    }
}

private struct FocusAnimatedRemoteImage: UIViewRepresentable {
    let url: URL
    let alt: String
    let pixelSize: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FocusEmoteImageView {
        let view = FocusEmoteImageView()
        view.prepare(alt: alt)
        context.coordinator.load(url: url, alt: alt, pixelSize: pixelSize, into: view)
        return view
    }

    func updateUIView(_ uiView: FocusEmoteImageView, context: Context) {
        uiView.prepare(alt: alt)
        context.coordinator.load(url: url, alt: alt, pixelSize: pixelSize, into: uiView)
    }

    static func dismantleUIView(_ uiView: FocusEmoteImageView, coordinator: Coordinator) {
        coordinator.cancel()
        uiView.stopAnimating()
    }

    @MainActor
    final class Coordinator {
        private var task: Task<Void, Never>?
        private var currentRequest: Request?
        private var generation = UUID()

        private struct Request: Equatable {
            let url: URL
            let pixelSize: Int
        }

        func load(url: URL, alt: String, pixelSize: Int, into imageView: FocusEmoteImageView) {
            imageView.prepare(alt: alt)
            let request = Request(url: url, pixelSize: FocusImagePixelSize.normalized(pixelSize))
            guard currentRequest != request else { return }
            currentRequest = request
            generation = UUID()
            let requestGeneration = generation
            task?.cancel()
            imageView.showFallback()
            task = Task { @MainActor [weak imageView] in
                guard
                    let image = try? await FocusImageRepository.shared.image(
                        for: url,
                        preferredReferer: "https://www.bilibili.com/",
                        quality: .emote,
                        pixelSize: request.pixelSize,
                        animated: !UIAccessibility.isReduceMotionEnabled
                    ),
                    !Task.isCancelled,
                    self.generation == requestGeneration
                else { return }
                imageView?.show(
                    image,
                    animate: image.images?.isEmpty == false && !UIAccessibility.isReduceMotionEnabled
                )
            }
        }

        func cancel() {
            generation = UUID()
            task?.cancel()
            task = nil
            currentRequest = nil
        }
    }
}

struct FocusImageGalleryRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
    let initialIndex: Int
    let referer: String
}

struct FocusCommentImageStrip: View {
    let urls: [URL]
    let referer: String
    var imageRepository: FocusImageRepository = .shared
    let onSelect: (Int) -> Void

    var body: some View {
        if !urls.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        Button { onSelect(index) } label: {
                            FocusRemoteImage(url: url, referer: referer, imageRepository: imageRepository) { phase in
                                Group {
                                    if case let .success(image) = phase {
                                        image.resizable().scaledToFill()
                                    } else {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(uiColor: .tertiarySystemFill))
                                            .overlay {
                                                if case .empty = phase { ProgressView().controlSize(.mini) }
                                                else { Image(systemName: "photo").foregroundStyle(.tertiary) }
                                            }
                                    }
                                }
                                .frame(width: 82, height: 82)
                                .clipped()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("评论图片 \(index + 1)")
                    }
                }
            }
            .frame(height: 82)
        }
    }
}

struct FocusImageGalleryView: View {
    let request: FocusImageGalleryRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    init(request: FocusImageGalleryRequest) {
        self.request = request
        _selection = State(initialValue: request.initialIndex.coerce(in: request.urls.indices))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(Array(request.urls.enumerated()), id: \.offset) { index, url in
                    FocusZoomableRemoteImage(url: url, referer: request.referer, resetKey: selection)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    Spacer()
                    Text("\(selection + 1) / \(request.urls.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.45), in: Capsule())
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct FocusZoomableRemoteImage: View {
    let url: URL
    let referer: String
    let resetKey: Int
    @StateObject private var loader = FocusGalleryImageLoader()
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            switch loader.phase {
            case let .success(image):
                galleryImage(image, in: proxy.size)
            case .failure:
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) {
            await loader.load(url: url, referer: referer)
        }
        .onChange(of: resetKey) { _ in
            resetTransform()
        }
    }

    private func galleryImage(_ image: UIImage, in viewport: CGSize) -> some View {
        let imageAspect = max(image.size.width, 1) / max(image.size.height, 1)
        let viewportAspect = max(viewport.width, 1) / max(viewport.height, 1)
        let usesWidthFittedLongLayout = imageAspect < 0.5 && imageAspect < viewportAspect
        let baseScale = usesWidthFittedLongLayout ? viewportAspect / imageAspect : 1
        let isLongImage = baseScale > 1.01
        let totalScale = baseScale * scale
        let topAlignmentOffset = isLongImage
            ? max(0, viewport.height * (totalScale - 1) / 2)
            : 0

        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: viewport.width, height: viewport.height)
            .scaleEffect(totalScale)
            .offset(x: offset.width, y: topAlignmentOffset + offset.height)
            .contentShape(Rectangle())
            .clipped()
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.2)) {
                    scale = scale > 1.1 ? 1 : 2.5
                    lastScale = scale
                    offset = .zero
                    lastOffset = .zero
                }
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value, 1), 5)
                        offset = clampedOffset(
                            offset,
                            viewport: viewport,
                            baseScale: baseScale,
                            userScale: scale,
                            isLongImage: isLongImage
                        )
                    }
                    .onEnded { _ in
                        lastScale = scale
                        offset = clampedOffset(
                            offset,
                            viewport: viewport,
                            baseScale: baseScale,
                            userScale: scale,
                            isLongImage: isLongImage
                        )
                        lastOffset = offset
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard isLongImage || scale > 1.01 else { return }
                        offset = clampedOffset(
                            CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            ),
                            viewport: viewport,
                            baseScale: baseScale,
                            userScale: scale,
                            isLongImage: isLongImage
                        )
                    }
                    .onEnded { value in
                        guard isLongImage || scale > 1.01 else { return }
                        let projected = CGSize(
                            width: lastOffset.width + value.predictedEndTranslation.width,
                            height: lastOffset.height + value.predictedEndTranslation.height
                        )
                        let target = clampedOffset(
                            projected,
                            viewport: viewport,
                            baseScale: baseScale,
                            userScale: scale,
                            isLongImage: isLongImage
                        )
                        withAnimation(.easeOut(duration: 0.22)) {
                            offset = target
                        }
                        lastOffset = target
                    }
            )
    }

    private func clampedOffset(
        _ proposed: CGSize,
        viewport: CGSize,
        baseScale: CGFloat,
        userScale: CGFloat,
        isLongImage: Bool
    ) -> CGSize {
        let totalScale = baseScale * userScale
        let maxHorizontal: CGFloat
        let verticalRange: ClosedRange<CGFloat>

        if isLongImage {
            maxHorizontal = max(0, viewport.width * (userScale - 1) / 2)
            let verticalOverflow = max(0, viewport.height * (totalScale - 1))
            verticalRange = -verticalOverflow ... 0
        } else {
            maxHorizontal = max(0, viewport.width * (totalScale - 1) / 2)
            let maxVertical = max(0, viewport.height * (totalScale - 1) / 2)
            verticalRange = -maxVertical ... maxVertical
        }

        return CGSize(
            width: min(max(proposed.width, -maxHorizontal), maxHorizontal),
            height: min(max(proposed.height, verticalRange.lowerBound), verticalRange.upperBound)
        )
    }

    private func resetTransform() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

private enum FocusGalleryImagePhase {
    case empty
    case success(UIImage)
    case failure
}

@MainActor
private final class FocusGalleryImageLoader: ObservableObject {
    @Published fileprivate var phase: FocusGalleryImagePhase = .empty
    private var requestID: UUID?

    func load(url: URL, referer: String) async {
        let requestID = UUID()
        self.requestID = requestID
        phase = .empty

        let thumbnail = await FocusImageRepository.shared.cachedImage(
            for: url,
            quality: .thumbnail
        )
        guard !Task.isCancelled, self.requestID == requestID else { return }
        if let thumbnail {
            phase = .success(thumbnail)
        }

        do {
            let image = try await FocusImageRepository.shared.image(
                for: url,
                preferredReferer: referer,
                quality: .gallery
            )
            guard !Task.isCancelled, self.requestID == requestID else {
                return
            }
            phase = .success(image)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, self.requestID == requestID else {
                return
            }
            if case .empty = phase {
                phase = .failure
            }
        }
    }
}

private extension Int {
    func coerce(in range: Range<Int>) -> Int {
        guard !range.isEmpty else { return 0 }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound - 1)
    }
}

private final class FocusFixtureOfflineImageProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

enum FocusImagePixelSize {
    static let buckets = [128, 256, 384, 512, 768, 1_024, 1_536, 2_048, 3_072, 4_096]

    static func bucket(for size: CGSize, scale: CGFloat) -> Int {
        let pixels = max(size.width, size.height) * max(scale, 1)
        guard pixels.isFinite, pixels > 0 else { return 128 }
        return buckets.first { CGFloat($0) >= pixels } ?? 4_096
    }

    static func normalized(_ pixels: Int) -> Int {
        buckets.first { $0 >= max(1, pixels) } ?? 4_096
    }
}

enum FocusImageRequestPriority: Sendable {
    case visible, prefetch
}

/// Only prefetchers wait here; visible requests never enter this queue. Two
/// prefetch slots leave the session's remaining host connections for visible
/// images. Pending prefetch has no in-flight repository entry to block a viewer.
actor FocusImagePrefetchLimiter {
    static let shared = FocusImagePrefetchLimiter()
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private let limit: Int
    private var active: Set<UUID> = []
    private var waiters: [Waiter] = []

    init(limit: Int = 2) { precondition(limit > 0); self.limit = limit }

    func acquire(_ id: UUID) async throws {
        try Task.checkCancellation()
        if active.count < limit { active.insert(id); return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiting(id) }
        }
        try Task.checkCancellation()
    }

    private func cancelWaiting(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    func release(_ id: UUID) {
        guard active.remove(id) != nil else { return }
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            active.insert(waiter.id)
            waiter.continuation.resume()
        }
    }

    var activeCount: Int { active.count }
    var waitingCount: Int { waiters.count }
}

enum FocusImageLoadQuality: String, Hashable, Sendable {
    case thumbnail
    case gallery
    case emote
}

actor FocusImageRepository {
    static let shared = FocusImageRepository()

    private struct RequestKey: Hashable {
        let url: URL
        let quality: FocusImageLoadQuality
        let pixelSize: Int
        let animated: Bool

        var cacheKey: NSString {
            "\(url.absoluteString)#focus-\(quality.rawValue)-\(pixelSize)-\(animated)" as NSString
        }
    }

    private struct InFlightRequest {
        let task: Task<UIImage, Error>
        var consumers: Set<UUID>
    }

    private let cache: NSCache<NSString, UIImage>
    private let session: URLSession
    private var inFlight: [RequestKey: InFlightRequest] = [:]

    init(session: URLSession? = nil) {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 192
        cache.totalCostLimit = 64 * 1024 * 1024
        self.cache = cache

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 48 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "FocusRemoteImageCache"
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 6
        if session == nil, FocusTestRuntime.isRunningFixtures {
            configuration.protocolClasses = [FocusFixtureOfflineImageProtocol.self]
        }
        self.session = session ?? URLSession(configuration: configuration)
    }

    var activeConsumerCount: Int { inFlight.values.reduce(0) { $0 + $1.consumers.count } }
    var inFlightRequestCount: Int { inFlight.count }

    func cachedImage(for url: URL, quality: FocusImageLoadQuality, pixelSize: Int = 1_600) -> UIImage? {
        let canonicalURL = Self.canonicalImageURL(url)
        let pixels = quality == .gallery ? 0 : FocusImagePixelSize.normalized(pixelSize)
        return cache.object(forKey: RequestKey(
            url: canonicalURL,
            quality: quality,
            pixelSize: pixels,
            animated: quality == .emote
        ).cacheKey)
    }

    func image(
        for url: URL,
        preferredReferer: String,
        quality: FocusImageLoadQuality = .thumbnail,
        pixelSize: Int = 1_600,
        animated: Bool = true,
        priority: FocusImageRequestPriority = .visible
    ) async throws -> UIImage {
        try Task.checkCancellation()
        let canonicalURL = Self.canonicalImageURL(url)
        let pixels = quality == .gallery ? 0 : FocusImagePixelSize.normalized(pixelSize)
        let shouldAnimate = quality == .emote && animated
        let key = RequestKey(url: canonicalURL, quality: quality, pixelSize: pixels, animated: shouldAnimate)
        if let cached = cache.object(forKey: key.cacheKey) { return cached }

        let consumerID = UUID()
        let fetchTask: Task<UIImage, Error>
        if var request = inFlight[key] {
            request.consumers.insert(consumerID)
            inFlight[key] = request
            fetchTask = request.task
        } else {
            let session = self.session
            fetchTask = Task.detached(priority: priority == .visible ? .userInitiated : .utility) {
                try await Self.fetchImage(
                    from: canonicalURL,
                    preferredReferer: preferredReferer,
                    session: session,
                    quality: quality,
                    pixelSize: pixels,
                    animated: shouldAnimate
                )
            }
            inFlight[key] = InFlightRequest(
                task: fetchTask,
                consumers: [consumerID]
            )
        }

        return try await withTaskCancellationHandler {
            do {
                let image = try await fetchTask.value
                try Task.checkCancellation()
                cache.setObject(image, forKey: key.cacheKey, cost: Self.cacheCost(for: image))
                releaseConsumer(consumerID, for: key)
                return image
            } catch {
                releaseConsumer(consumerID, for: key)
                throw error
            }
        } onCancel: {
            Task {
                await self.releaseConsumer(consumerID, for: key)
            }
        }
    }

    private func releaseConsumer(_ consumerID: UUID, for key: RequestKey) {
        guard var request = inFlight[key], request.consumers.remove(consumerID) != nil else {
            return
        }
        guard !request.consumers.isEmpty else {
            request.task.cancel()
            inFlight[key] = nil
            return
        }
        inFlight[key] = request
    }

    private static func fetchImage(
        from url: URL,
        preferredReferer: String,
        session: URLSession,
        quality: FocusImageLoadQuality,
        pixelSize: Int,
        animated: Bool
    ) async throws -> UIImage {
        let referers = [preferredReferer, "https://t.bilibili.com/", "https://www.bilibili.com/", ""]
            .reduce(into: [String]()) { values, referer in
                if !values.contains(referer) {
                    values.append(referer)
                }
            }

        for referer in referers {
            for candidate in imageURLCandidates(for: url, quality: quality) {
                try Task.checkCancellation()
                do {
                    var request = URLRequest(url: candidate)
                    request.timeoutInterval = 20
                    if !referer.isEmpty {
                        request.setValue(referer, forHTTPHeaderField: "Referer")
                    }
                    request.httpShouldHandleCookies = false
                    request.setValue(
                        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                        forHTTPHeaderField: "User-Agent"
                    )
                    request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
                    request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                    request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")

                    let (data, response) = try await session.data(for: request)
                    try Task.checkCancellation()
                    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    if response.statusCode == 403 || response.statusCode == 404 { continue }
                    guard (200 ..< 300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
                    guard let image = decodedImage(from: data, quality: quality, pixelSize: pixelSize, animated: animated) else { continue }
                    return image
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as URLError where error.code == .cancelled {
                    throw CancellationError()
                } catch {
                    // Offline, timeout, TLS and server errors do not become a
                    // Referer/URL Cartesian-product retry storm.
                    throw error
                }
            }
        }

        throw URLError(.cannotDecodeContentData)
    }

    private static func decodedImage(from data: Data, quality: FocusImageLoadQuality, pixelSize: Int, animated: Bool) -> UIImage? {
        switch quality {
        case .thumbnail:
            return downsampledImage(from: data, maxPixelSize: pixelSize)
        case .gallery:
            return widthFittedGalleryImage(from: data)
        case .emote:
            return animatedEmoteImage(from: data, maxPixelSize: pixelSize, animated: animated)
        }
    }

    private static func animatedEmoteImage(from data: Data, maxPixelSize: Int, animated: Bool) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }
        let count = CGImageSourceGetCount(source)
        guard count > 1, animated else {
            return downsampledImage(from: source, maxPixelSize: maxPixelSize)
        }
        var frames: [UIImage] = []
        var duration: TimeInterval = 0
        for index in 0 ..< min(count, 120) {
            if Task.isCancelled { return nil }
            guard let frame = downsampledImage(from: source, index: index, maxPixelSize: maxPixelSize) else { continue }
            frames.append(UIImage(cgImage: frame))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
                ?? (png?[kCGImagePropertyAPNGDelayTime] as? Double)
                ?? 0.1
            duration += max(delay, 0.02)
        }
        guard let first = frames.first else { return nil }
        return UIImage.animatedImage(with: frames, duration: max(duration, 0.1)) ?? first
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }
        return downsampledImage(from: source, maxPixelSize: maxPixelSize)
    }

    private static func widthFittedGalleryImage(from data: Data) -> UIImage? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false
            ] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            width > 0,
            height > 0
        else {
            return UIImage(data: data)
        }

        let targetPixelWidth = 2_048.0
        let maximumPixelCount = 32_000_000.0
        let maximumPixelHeight = 32_768.0
        let widthScale = targetPixelWidth / width
        let pixelCountScale = sqrt(maximumPixelCount / (width * height))
        let heightScale = maximumPixelHeight / height
        let decodeScale = [1, widthScale, pixelCountScale, heightScale].min() ?? 1
        let maxPixelSize = max(1, Int(ceil(max(width, height) * decodeScale)))
        return downsampledImage(from: source, maxPixelSize: maxPixelSize)
    }

    private static func downsampledImage(
        from source: CGImageSource,
        maxPixelSize: Int
    ) -> UIImage? {
        guard let image = downsampledImage(from: source, index: 0, maxPixelSize: maxPixelSize) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func downsampledImage(
        from source: CGImageSource,
        index: Int,
        maxPixelSize: Int
    ) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    private static func canonicalImageURL(_ url: URL) -> URL {
        URL(string: url.absoluteString.replacingOccurrences(of: "http://", with: "https://")) ?? url
    }

    private static func imageURLCandidates(
        for url: URL,
        quality: FocusImageLoadQuality
    ) -> [URL] {
        let cleaned = url.absoluteString.replacingOccurrences(of: "http://", with: "https://")
        let stripped = cleaned.replacingOccurrences(of: #"@[^/?#]+"#, with: "", options: .regularExpression)
        let orderedCandidates = quality == .gallery ? [stripped, cleaned] : [cleaned, stripped]
        return orderedCandidates
            .compactMap(URL.init(string:))
            .reduce(into: [URL]()) { values, candidate in
                if !values.contains(candidate) {
                    values.append(candidate)
                }
            }
    }

    private static func cacheCost(for image: UIImage) -> Int {
        if let frames = image.images, !frames.isEmpty {
            return frames.reduce(into: 0) { total, frame in
                total += decodedCost(for: frame)
            }
        }
        return decodedCost(for: image)
    }

    private static func decodedCost(for image: UIImage) -> Int {
        guard let image = image.cgImage else {
            return Int(image.size.width * image.size.height * image.scale * image.scale)
        }
        return image.bytesPerRow * image.height
    }

}

@MainActor
final class FocusRemoteImageLoader: ObservableObject {
    @Published fileprivate var phase: FocusRemoteImagePhase = .empty

    private let repository: FocusImageRepository
    private var requestID: UUID?

    init(repository: FocusImageRepository = .shared) {
        self.repository = repository
    }

    func load(url: URL?, referer: String, pixelSize: Int = 1_600) async {
        let requestID = UUID()
        self.requestID = requestID

        guard let url else {
            phase = .failure
            return
        }

        phase = .empty
        do {
            let image = try await repository.image(
                for: url,
                preferredReferer: referer,
                pixelSize: pixelSize
            )
            guard
                !Task.isCancelled,
                self.requestID == requestID
            else {
                return
            }
            phase = .success(Image(uiImage: image))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, self.requestID == requestID else {
                return
            }
            phase = .failure
        }
    }

    nonisolated static func prefetch(
        urls: [URL], referer: String, pixelSize: Int = 768,
        repository: FocusImageRepository = .shared,
        limiter: FocusImagePrefetchLimiter = .shared
    ) async {
        var seen: Set<URL> = []
        var candidates: [URL] = []
        // A LazyFilterCollection may evaluate its predicate repeatedly while
        // calculating prefix indices; a mutating dedup predicate is not pure.
        for url in urls where seen.insert(url).inserted {
            candidates.append(url)
            if candidates.count == 24 { break }
        }
        await withTaskGroup(of: Bool.self) { group in
            var next = 0
            func enqueue(_ url: URL) {
                group.addTask {
                    let lease = UUID()
                    var continueBatch = true
                    do {
                        try await limiter.acquire(lease)
                        try Task.checkCancellation()
                        _ = try await repository.image(for: url, preferredReferer: referer,
                                                       pixelSize: pixelSize, priority: .prefetch)
                    } catch is CancellationError {
                        continueBatch = false
                    } catch let error as URLError {
                        continueBatch = ![.cancelled, .notConnectedToInternet, .timedOut,
                                          .networkConnectionLost, .cannotFindHost, .dnsLookupFailed]
                            .contains(error.code)
                    } catch { /* Other failures remain local to this optional image. */ }
                    await limiter.release(lease)
                    return continueBatch
                }
            }
            for url in candidates.prefix(2) { enqueue(url); next += 1 }
            for await continueBatch in group {
                if Task.isCancelled || !continueBatch { group.cancelAll(); break }
                if next < candidates.count { enqueue(candidates[next]); next += 1 }
            }
        }
    }
}

struct FocusVideoControlButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemImage: String
    var title: String? = nil
    var isActive = false
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: title == nil ? 0 : 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(isActive ? FocusSharedDesign.primary : FocusSharedDesign.videoControlForeground)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isActive
                            ? FocusSharedDesign.primary.opacity(0.16)
                            : FocusSharedDesign.chromeButtonBackground.opacity(colorScheme == .dark ? 0.86 : 0.92)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct FocusVisualEffectBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context _: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ view: UIVisualEffectView, context _: Context) {
        view.effect = UIBlurEffect(style: style)
        view.clipsToBounds = true
        view.backgroundColor = .clear
    }
}
#endif
