#if canImport(UIKit)
import FocusCore
import SwiftUI
import UIKit

struct FocusSettingsView: View {
    @ObservedObject var settingsStore: FocusSettingsStore
    @StateObject private var viewModel: FocusDynamicAuthorSettingsViewModel
    private let loginHealthService: LoginHealthService
    @Environment(\.dismiss) private var dismiss

    init(appGraph: FocusAppGraph, dynamicAuthors: [DynamicCard.Author]) {
        self._viewModel = StateObject(
            wrappedValue: FocusDynamicAuthorSettingsViewModel(
                service: FocusFollowingAuthorsService(cookieProvider: appGraph.cookieProvider),
                fallbackAuthors: dynamicAuthors
            )
        )
        self.settingsStore = appGraph.settingsStore
        self.loginHealthService = appGraph.loginHealthService
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("默认入口", selection: binding(\.defaultEntry)) {
                        ForEach(FocusEntry.allCases, id: \.self) { entry in
                            Text(entry.title).tag(entry)
                        }
                    }

                    Picker("主题", selection: binding(\.themeMode)) {
                        ForEach(FocusThemeMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    ColorPicker(
                        "强调色",
                        selection: accentColorBinding,
                        supportsOpacity: false
                    )

                    LabeledContent("颜色值") {
                        Text(settingsStore.settings.accentColorHex)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Button("恢复 B 站粉") {
                        settingsStore.settings.accentColorHex = FocusSettings.defaultAccentColorHex
                    }
                    .disabled(
                        settingsStore.settings.accentColorHex == FocusSettings.defaultAccentColorHex
                    )
                } header: {
                    Text("入口与主题")
                }

                Section {
                    Toggle("首页重定向", isOn: binding(\.redirectEnabled))
                    Toggle("动态详情页去干扰", isOn: binding(\.dynamicMaskEnabled))
                    Toggle("搜索结果页去干扰", isOn: binding(\.searchMaskEnabled))
                    Toggle("播放页去干扰", isOn: binding(\.playerMaskEnabled))
                } header: {
                    Text("规则")
                }

                Section {
                    Toggle("原生播放器默认显示弹幕", isOn: binding(\.nativeDanmakuEnabled))
                    Toggle("有字幕时默认显示字幕", isOn: binding(\.nativeSubtitleEnabled))
                } header: {
                    Text("播放")
                }

                Section {
                    NavigationLink("关注 UP 主动态配置") {
                        FocusDynamicAuthorSettingsListView(viewModel: viewModel, settingsStore: settingsStore)
                    }
                } header: {
                    Text("动态分类")
                }

                Section {
#if DEBUG
                    Toggle("调试日志", isOn: binding(\.debugMode))
                    NavigationLink("登录与网络诊断") {
                        FocusDiagnosticsView(loginHealthService: loginHealthService)
                    }
#endif
                    Button("恢复默认设置", role: .destructive) {
                        settingsStore.reset()
                    }
                } header: {
                    Text("高级")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.loadIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<FocusSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: {
                FocusAccentColor.color(hex: settingsStore.settings.accentColorHex)
            },
            set: { color in
                settingsStore.settings.accentColorHex = FocusAccentColor.hexString(from: color)
            }
        )
    }
}

private struct FocusDynamicAuthorSettingsListView: View {
    @ObservedObject var viewModel: FocusDynamicAuthorSettingsViewModel
    @ObservedObject var settingsStore: FocusSettingsStore

    var body: some View {
        content
            .navigationTitle("UP 主动态配置")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载关注列表…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            FocusStateView(
                title: "关注列表加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )
        case let .loaded(authors):
            List(authors, id: \.filterIdentity) { author in
                NavigationLink(author.name) {
                    FocusDynamicAuthorFilterView(author: author, settingsStore: settingsStore)
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

private struct FocusDynamicAuthorFilterView: View {
    let author: DynamicCard.Author
    @ObservedObject var settingsStore: FocusSettingsStore

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    if let avatarURL = author.avatarURL {
                        FocusRemoteImage(url: avatarURL, referer: "https://space.bilibili.com/\(author.mid)") { phase in
                            switch phase {
                            case let .success(image):
                                image.resizable().scaledToFill()
                            default:
                                Circle().fill(Color(uiColor: .tertiarySystemFill))
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(author.name)
                            .font(.headline.weight(.semibold))
                        Text("选择要保留的动态类型")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("显示内容") {
                ForEach([FocusDynamicFilterKind.video, .articleLike], id: \.self) { kind in
                    Toggle(kind.title, isOn: binding(for: kind))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(author.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for kind: FocusDynamicFilterKind) -> Binding<Bool> {
        Binding(
            get: { settingsStore.dynamicKinds(for: author).contains(kind) },
            set: { isEnabled in
                var kinds = settingsStore.dynamicKinds(for: author)
                if isEnabled {
                    kinds.insert(kind)
                } else {
                    kinds.remove(kind)
                }
                if kinds.isEmpty {
                    kinds = [kind]
                }
                settingsStore.setDynamicKinds(kinds, for: author)
            }
        )
    }
}
#endif
