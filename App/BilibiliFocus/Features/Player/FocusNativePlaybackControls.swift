#if canImport(UIKit)
import FocusCore
import Foundation
import SwiftUI
import UIKit

/// Inline and fullscreen use the same controls and the same player state.
/// Visibility never changes the size of the video or the surrounding feed.
struct FocusNativePlaybackControls: View {
    @ObservedObject var viewModel: FocusNativeVideoViewModel
    let isFullscreen: Bool
    var title: String = ""
    var accentColor: Color = FocusSharedDesign.primary
    var safeAreaInsets: EdgeInsets = EdgeInsets()
    var onShowSystemControls: (() -> Void)?
    var onBottomOcclusionChange: (CGFloat) -> Void = { _ in }

    @State private var controlsVisible = true
    @State private var isLocked = false
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var hideTask: Task<Void, Never>?
    @GestureState private var isHolding = false

    private var canControl: Bool {
        viewModel.hasPreparedPlayer && !viewModel.isLoadingPlayback && !viewModel.hasPlaybackEnded
    }
    private var duration: Double { Double(viewModel.playbackDurationMilliseconds) }
    private var position: Double {
        isScrubbing ? scrubPosition : Double(viewModel.playbackPositionMilliseconds)
    }
    private var contentInsets: EdgeInsets {
        Self.contentInsets(isFullscreen: isFullscreen, safeArea: safeAreaInsets)
    }

    /// The fullscreen canvas fills the display; reserve the device cutout and
    /// home indicator once, rather than adding another inset inside its safe area.
    static func contentInsets(isFullscreen: Bool, safeArea: EdgeInsets) -> EdgeInsets {
        guard isFullscreen else { return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12) }
        return EdgeInsets(top: max(safeArea.top, 6), leading: max(safeArea.leading, 12),
                          bottom: max(safeArea.bottom, 6), trailing: max(safeArea.trailing, 12))
    }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    TapGesture(count: 2).onEnded {
                        guard !isLocked, viewModel.hasPreparedPlayer, !viewModel.isLoadingPlayback else { return }
                        viewModel.togglePlayback()
                        showControls()
                    }.exclusively(before: TapGesture().onEnded {
                        guard !isLocked else { return }
                        withAnimation(.easeOut(duration: 0.16)) { controlsVisible.toggle() }
                        scheduleAutoHide()
                    })
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.35, maximumDistance: 30)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .updating($isHolding) { value, state, _ in
                            if case .second(true, _) = value { state = true }
                        }
                )
                .accessibilityLabel("视频画面")
                .accessibilityHint("轻点显示控制，双击播放或暂停，长按临时加速")
                .accessibilityAction(named: "显示播放控制") { showControls() }

            if controlsVisible && !isLocked {
                LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 12)
                    bottomBar
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: PlaybackControlsOcclusionKey.self,
                                                   value: geometry.size.height + contentInsets.bottom)
                        })
                }
                .padding(contentInsets)
                .transition(.opacity)
            }

            if isLocked {
                HStack {
                    iconButton("lock.fill", label: "解锁播放器") {
                        isLocked = false
                        showControls()
                    }
                    .background(.black.opacity(0.55), in: Circle())
                    Spacer()
                }
                .padding(.leading, contentInsets.leading)
            }

            if isHolding && !isLocked && canControl && viewModel.isPlaying {
                VStack {
                    Label("临时倍速播放", systemImage: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.65), in: Capsule())
                    Spacer()
                }
                .padding(.top, isFullscreen ? contentInsets.top + 44 : 12)
                .allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
        .onPreferenceChange(PlaybackControlsOcclusionKey.self, perform: onBottomOcclusionChange)
        .tint(accentColor)
        .onAppear { scheduleAutoHide() }
        .onDisappear {
            hideTask?.cancel()
            viewModel.endTemporaryPlaybackRate()
        }
        .onChange(of: isHolding) { holding in
            if holding && !isLocked && canControl && viewModel.isPlaying {
                hideTask?.cancel()
                viewModel.beginTemporaryPlaybackRate()
            } else {
                viewModel.endTemporaryPlaybackRate()
                scheduleAutoHide()
            }
        }
        .onChange(of: viewModel.isPlaying) { playing in
            if !playing { showControls() } else { scheduleAutoHide() }
        }
        .onChange(of: viewModel.isLoadingPlayback) { loading in
            if loading { showControls() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isFullscreen ? "fullscreen-playback-controls" : "inline-playback-controls")
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            if isFullscreen {
                iconButton("chevron.left", label: "退出全屏") { viewModel.exitFullscreen() }
                Text(title).font(.system(size: 16, weight: .medium)).lineLimit(1)
                Spacer(minLength: 12)
                iconButton("lock.open", label: "锁定播放器") {
                    viewModel.endTemporaryPlaybackRate()
                    hideTask?.cancel()
                    isLocked = true
                }
                if let onShowSystemControls {
                    iconButton("ellipsis", label: "系统播放控件，画中画与 AirPlay", action: onShowSystemControls)
                }
            } else {
                Spacer()
            }
            subtitleMenu
        }
        .frame(height: 40)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(Self.timestamp(position))
                FocusPlaybackSeekSlider(value: Binding(
                    get: { min(max(position, 0), max(duration, 1)) },
                    set: { scrubPosition = $0 }
                ), maximum: max(duration, 1), tint: accentColor, onEditingChanged: { editing in
                    if editing {
                        scrubPosition = Double(viewModel.playbackPositionMilliseconds)
                        isScrubbing = true
                        hideTask?.cancel()
                    } else {
                        viewModel.seek(toMilliseconds: Int64(scrubPosition))
                        isScrubbing = false
                        scheduleAutoHide()
                    }
                })
                .frame(height: 28)
                .disabled(!canControl || duration <= 0)
                .accessibilityLabel("播放进度")
                .accessibilityValue("\(Self.timestamp(position))，总时长 \(Self.timestamp(duration))")
                .accessibilityIdentifier("playback-seek-slider")
                Text(Self.timestamp(duration))
            }
            .font(.system(size: isFullscreen ? 13 : 11, weight: .medium, design: .monospaced))

            HStack(spacing: isFullscreen ? 16 : 4) {
                iconButton(viewModel.hasPlaybackEnded ? "arrow.counterclockwise" : (viewModel.isPlaying ? "pause.fill" : "play.fill"),
                           label: viewModel.hasPlaybackEnded ? "重新播放" : (viewModel.isPlaying ? "暂停视频" : "播放视频")) {
                    viewModel.togglePlayback()
                    showControls()
                }
                .disabled(!viewModel.hasPreparedPlayer || viewModel.isLoadingPlayback)
                .accessibilityIdentifier("playback-toggle")
                Spacer(minLength: 0)
                iconButton(viewModel.isDanmakuEnabled ? "text.bubble.fill" : "text.bubble",
                           label: viewModel.isDanmakuEnabled ? "关闭弹幕" : "开启弹幕") {
                    viewModel.toggleDanmaku()
                    scheduleAutoHide()
                }
                .foregroundStyle(viewModel.isDanmakuEnabled ? accentColor : .white)
                rateMenu
                if !viewModel.availableQualities.isEmpty { qualityMenu }
                iconButton(isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           label: isFullscreen ? "退出全屏" : "进入全屏") {
                    if isFullscreen { viewModel.exitFullscreen() } else { viewModel.requestFullscreen() }
                }
            }
            .frame(height: 40)
        }
    }

    private var rateMenu: some View {
        Menu {
            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2, 3], id: \.self) { rate in
                Button {
                    viewModel.setPlaybackRate(rate)
                    scheduleAutoHide()
                } label: {
                    if viewModel.playbackRate == rate {
                        Label(FocusNativeVideoFormatting.rate(rate), systemImage: "checkmark")
                    } else {
                        Text(FocusNativeVideoFormatting.rate(rate))
                    }
                }
            }
        } label: {
            Text(FocusNativeVideoFormatting.rate(viewModel.playbackRate))
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("播放速度")
        .accessibilityIdentifier("playback-rate-menu")
        .simultaneousGesture(TapGesture().onEnded { hideTask?.cancel() })
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(viewModel.availableQualities, id: \.id) { quality in
                Button {
                    viewModel.selectQuality(quality)
                    scheduleAutoHide()
                } label: {
                    if viewModel.selectedQuality == quality.id {
                        Label(quality.title, systemImage: "checkmark")
                    } else {
                        Text(quality.title)
                    }
                }
            }
        } label: {
            Text(viewModel.qualityDescription)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(minWidth: 44, minHeight: 44)
        }
        .disabled(!canControl)
        .accessibilityLabel("视频清晰度")
        .accessibilityIdentifier("playback-quality-menu")
        .simultaneousGesture(TapGesture().onEnded { hideTask?.cancel() })
    }

    private var subtitleMenu: some View {
        Menu {
            Button(viewModel.isSubtitleEnabled ? "关闭字幕" : "开启字幕") {
                if viewModel.isSubtitleEnabled { viewModel.disableSubtitles() }
                else { viewModel.enableSubtitles() }
                scheduleAutoHide()
            }
            ForEach(viewModel.subtitleTracks) { track in
                Button {
                    viewModel.selectSubtitleTrack(track)
                    scheduleAutoHide()
                } label: {
                    if viewModel.isSubtitleEnabled && viewModel.selectedSubtitleTrackID == track.id {
                        Label(track.displayName, systemImage: "checkmark")
                    } else {
                        Text(track.displayName)
                    }
                }
                .disabled(track.isLocked)
            }
            if case .failed = viewModel.subtitleLoadState {
                Button("重新加载字幕", action: viewModel.retrySubtitles)
            } else if case .unavailable = viewModel.subtitleLoadState {
                Text("当前分集暂无字幕")
            }
        } label: {
            Image(systemName: viewModel.isSubtitleEnabled ? "captions.bubble.fill" : "captions.bubble")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("字幕设置")
        .simultaneousGesture(TapGesture().onEnded { hideTask?.cancel() })
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func showControls() {
        withAnimation(.easeOut(duration: 0.16)) { controlsVisible = true }
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard controlsVisible, viewModel.isPlaying, !isScrubbing, !isHolding, !isLocked,
              !UIAccessibility.isVoiceOverRunning else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false }
        }
    }

    static func timestamp(_ milliseconds: Double) -> String {
        let seconds = Int(max(milliseconds, 0) / 1_000)
        if seconds >= 3_600 { return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct PlaybackControlsOcclusionKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A small video scrubber with UIKit's native accessibility and touch tracking.
struct FocusPlaybackSeekSlider: UIViewRepresentable {
    @Binding var value: Double
    let maximum: Double
    let tint: Color
    let onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> FocusVideoSeekSlider {
        let slider = FocusVideoSeekSlider()
        slider.setThumbImage(Self.thumb(size: 10), for: .normal)
        slider.setThumbImage(Self.thumb(size: 16), for: .highlighted)
        slider.maximumTrackTintColor = .white.withAlphaComponent(0.28)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.begin), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.change), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.end), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return slider
    }

    func updateUIView(_ slider: FocusVideoSeekSlider, context: Context) {
        context.coordinator.parent = self
        slider.minimumValue = 0
        slider.maximumValue = Float(maximum)
        slider.minimumTrackTintColor = UIColor(tint)
        slider.isEnabled = context.environment.isEnabled
        if !context.coordinator.isEditing { slider.value = Float(value) }
    }

    private static func thumb(size: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: FocusPlaybackSeekSlider
        var isEditing = false
        init(_ parent: FocusPlaybackSeekSlider) { self.parent = parent }
        @objc func begin(_ slider: UISlider) {
            isEditing = true
            parent.onEditingChanged(true)
        }
        @objc func change(_ slider: UISlider) {
            // VoiceOver changes the value without a touch-down/up pair.
            let accessibilityAdjustment = !isEditing
            if accessibilityAdjustment { begin(slider) }
            parent.value = Double(slider.value)
            if accessibilityAdjustment { end(slider) }
        }
        @objc func end(_ slider: UISlider) {
            guard isEditing else { return }
            parent.value = Double(slider.value)
            parent.onEditingChanged(false)
            isEditing = false
        }
    }
}

final class FocusVideoSeekSlider: UISlider {
    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        let track = super.trackRect(forBounds: bounds)
        return CGRect(x: track.minX, y: bounds.midY - 1.5, width: track.width, height: 3)
    }
}
#endif
