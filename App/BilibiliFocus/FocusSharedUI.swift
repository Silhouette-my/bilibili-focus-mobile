#if canImport(UIKit)
import SwiftUI
import UIKit
import WebKit
import ImageIO

enum FocusSharedDesign {
    static let primary = Color(red: 0.984, green: 0.447, blue: 0.600)
    static let videoControlForeground = Color(uiColor: .label)
    static let chromeButtonBackground = Color(uiColor: .secondarySystemBackground)
    static let chromePanelBackground = Color(uiColor: .systemBackground)
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

    @StateObject private var loader = FocusRemoteImageLoader()

    init(
        url: URL?,
        referer: String = "https://www.bilibili.com/",
        @ViewBuilder content: @escaping (FocusRemoteImagePhase) -> Content
    ) {
        self.url = url
        self.referer = referer
        self.content = content
    }

    var body: some View {
        content(displayPhase)
            .task(id: url) {
                await loader.load(url: url, referer: referer)
            }
    }

    private var displayPhase: FocusRemoteImagePhase {
        return loader.phase
    }
}

actor FocusImageRepository {
    static let shared = FocusImageRepository()

    private struct InFlightRequest {
        let task: Task<UIImage, Error>
        var consumers: Set<UUID>
    }

    private let cache: NSCache<NSURL, UIImage>
    private let session: URLSession
    private var inFlight: [URL: InFlightRequest] = [:]

    init() {
        let cache = NSCache<NSURL, UIImage>()
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
        configuration.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: configuration)
    }

    func image(for url: URL, preferredReferer: String) async throws -> UIImage {
        let canonicalURL = Self.canonicalImageURL(url)
        if let cached = cache.object(forKey: canonicalURL as NSURL) {
            return cached
        }

        let cookieHeader = await Self.cookieHeaderValue()
        if let cached = cache.object(forKey: canonicalURL as NSURL) {
            return cached
        }

        let consumerID = UUID()
        let fetchTask: Task<UIImage, Error>
        if var request = inFlight[canonicalURL] {
            request.consumers.insert(consumerID)
            inFlight[canonicalURL] = request
            fetchTask = request.task
        } else {
            let session = self.session
            fetchTask = Task.detached(priority: .utility) {
                try await Self.fetchImage(
                    from: canonicalURL,
                    preferredReferer: preferredReferer,
                    cookieHeader: cookieHeader,
                    session: session
                )
            }
            inFlight[canonicalURL] = InFlightRequest(
                task: fetchTask,
                consumers: [consumerID]
            )
        }

        return try await withTaskCancellationHandler {
            do {
                let image = try await fetchTask.value
                try Task.checkCancellation()
                cache.setObject(image, forKey: canonicalURL as NSURL, cost: Self.cacheCost(for: image))
                releaseConsumer(consumerID, for: canonicalURL)
                return image
            } catch {
                releaseConsumer(consumerID, for: canonicalURL)
                throw error
            }
        } onCancel: {
            Task {
                await self.releaseConsumer(consumerID, for: canonicalURL)
            }
        }
    }

    private func releaseConsumer(_ consumerID: UUID, for url: URL) {
        guard var request = inFlight[url], request.consumers.remove(consumerID) != nil else {
            return
        }
        guard !request.consumers.isEmpty else {
            request.task.cancel()
            inFlight[url] = nil
            return
        }
        inFlight[url] = request
    }

    private static func fetchImage(
        from url: URL,
        preferredReferer: String,
        cookieHeader: String?,
        session: URLSession
    ) async throws -> UIImage {
        let referers = [preferredReferer, "https://t.bilibili.com/", "https://www.bilibili.com/", ""]
            .reduce(into: [String]()) { values, referer in
                if !values.contains(referer) {
                    values.append(referer)
                }
            }

        for referer in referers {
            for candidate in imageURLCandidates(for: url) {
                try Task.checkCancellation()
                do {
                    var request = URLRequest(url: candidate)
                    request.timeoutInterval = 20
                    if !referer.isEmpty {
                        request.setValue(referer, forHTTPHeaderField: "Referer")
                    }
                    if let cookieHeader, !cookieHeader.isEmpty {
                        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                    }
                    request.httpShouldHandleCookies = true
                    request.setValue(
                        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                        forHTTPHeaderField: "User-Agent"
                    )
                    request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
                    request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                    request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")

                    let (data, response) = try await session.data(for: request)
                    guard
                        let response = response as? HTTPURLResponse,
                        (200 ..< 300).contains(response.statusCode),
                        let image = downsampledImage(from: data, maxPixelSize: 1_600)
                    else {
                        continue
                    }
                    return image
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    continue
                }
            }
        }

        throw URLError(.cannotDecodeContentData)
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private static func canonicalImageURL(_ url: URL) -> URL {
        URL(string: url.absoluteString.replacingOccurrences(of: "http://", with: "https://")) ?? url
    }

    private static func imageURLCandidates(for url: URL) -> [URL] {
        let cleaned = url.absoluteString.replacingOccurrences(of: "http://", with: "https://")
        let stripped = cleaned.replacingOccurrences(of: #"@[^/?#]+"#, with: "", options: .regularExpression)
        return [cleaned, stripped]
            .compactMap(URL.init(string:))
            .reduce(into: [URL]()) { values, candidate in
                if !values.contains(candidate) {
                    values.append(candidate)
                }
            }
    }

    private static func cacheCost(for image: UIImage) -> Int {
        guard let image = image.cgImage else {
            return Int(image.size.width * image.size.height * image.scale * image.scale)
        }
        return image.bytesPerRow * image.height
    }

    @MainActor
    private static func cookieHeaderValue() async -> String? {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        guard !cookies.isEmpty else {
            return nil
        }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }
}

@MainActor
final class FocusRemoteImageLoader: ObservableObject {
    @Published fileprivate var phase: FocusRemoteImagePhase = .empty

    private var requestID: UUID?

    func load(url: URL?, referer: String) async {
        let requestID = UUID()
        self.requestID = requestID

        guard let url else {
            phase = .failure
            return
        }

        phase = .empty
        do {
            let image = try await FocusImageRepository.shared.image(
                for: url,
                preferredReferer: referer
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

    nonisolated static func prefetch(urls: [URL], referer: String) async {
        for url in urls {
            guard !Task.isCancelled else {
                return
            }
            _ = try? await FocusImageRepository.shared.image(
                for: url,
                preferredReferer: referer
            )
        }
    }
}

struct FocusVideoControlButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemImage: String
    var title: String? = nil
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
            .foregroundStyle(FocusSharedDesign.videoControlForeground)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FocusSharedDesign.chromeButtonBackground.opacity(colorScheme == .dark ? 0.86 : 0.92))
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
