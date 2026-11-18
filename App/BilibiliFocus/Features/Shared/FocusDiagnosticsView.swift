#if canImport(UIKit) && DEBUG
import FocusCore
import SwiftUI

struct FocusDiagnosticsView: View {
    let loginHealthService: LoginHealthService
    let eventStore: BiliNetworkEventStore

    @State private var loginHealth = LoginHealth.unknown
    @State private var snapshot: BiliDiagnosticSnapshot?
    @State private var exportText: String?
    @State private var isLoading = false

    init(
        loginHealthService: LoginHealthService,
        eventStore: BiliNetworkEventStore = BiliAPINetwork.events
    ) {
        self.loginHealthService = loginHealthService
        self.eventStore = eventStore
    }

    var body: some View {
        List {
            Section("登录健康") {
                Label(loginHealth.focusTitle, systemImage: loginHealth.focusSymbol)
                    .foregroundStyle(loginHealth.focusColor)
                Text(loginHealth.focusDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if isLoading {
                    ProgressView("正在执行只读检测…")
                }
            }

            Section {
                if let snapshot, !snapshot.events.isEmpty {
                    ForEach(
                        Array(snapshot.events.suffix(50).reversed().enumerated()),
                        id: \.offset
                    ) { _, event in
                        FocusDiagnosticEventRow(event: event)
                    }
                } else {
                    Text("暂无网络事件")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("脱敏网络事件")
            } footer: {
                Text("仅保留方法、无查询参数的目标、状态码、耗时、大小和有限错误类别。")
            }

            Section {
                if let snapshot, !snapshot.performanceEvents.isEmpty {
                    ForEach(Array(snapshot.performanceEvents.suffix(60).reversed()), id: \.id) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(event.stage.rawValue) · \(event.outcome.rawValue)")
                                .font(.caption.monospaced())
                            Text(String(format: "%.1f ms · count %d", event.durationMilliseconds, event.count))
                                .font(.caption2)
                            if let error = event.positionErrorPoints {
                                Text(String(format: "锚点误差 %.2f pt", error)).font(.caption2)
                            }
                            Text(String(event.correlationID.uuidString.prefix(8)))
                                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("暂无阶段计时").foregroundStyle(.secondary)
                }
            } header: {
                Text("本地阶段计时")
            } footer: {
                Text("最多保留 256 条；关联标记随机生成，与账号和内容无关。数据、readyToPlay 和可显示首帧分别记录。")
            }

            Section {
                if let exportText {
                    ShareLink(
                        item: exportText,
                        subject: Text("Bilibili Focus 脱敏诊断"),
                        message: Text("此摘要不含 Cookie、查询参数或响应正文。")
                    ) {
                        Label("导出脱敏摘要", systemImage: "square.and.arrow.up")
                    }
                }

                Button {
                    Task {
                        await eventStore.clear()
                        BiliPerformanceStore.shared.clear()
                        await reload()
                    }
                } label: {
                    Label("清除本地事件", systemImage: "trash")
                }
                .disabled(isLoading)
            } footer: {
                Text("诊断仅保存在内存中；关闭进程后自动清除。")
            }
        }
        .navigationTitle("诊断")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await reload()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    @MainActor
    private func reload() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer {
            isLoading = false
        }

        let health = await loginHealthService.check()
        let snapshot = await BiliDiagnostics.snapshot(
            loginHealth: health,
            eventStore: eventStore
        )
        loginHealth = health
        self.snapshot = snapshot
        exportText = (try? snapshot.jsonData(prettyPrinted: true))
            .flatMap { String(data: $0, encoding: .utf8) }
    }
}

private struct FocusDiagnosticEventRow: View {
    let event: BiliDiagnosticEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(event.method)
                    .font(.caption.monospaced().weight(.semibold))
                Spacer()
                Text(event.statusCode.map(String.init) ?? event.failureType ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(event.target)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("\(event.durationMilliseconds) ms · \(event.responseBytes.map(String.init) ?? "—") bytes")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private extension LoginHealth {
    var focusTitle: String {
        switch self {
        case .notLoggedIn:
            return "未登录"
        case .sessionExpired:
            return "Cookie 已过期"
        case .missingCSRF:
            return "缺少 CSRF Cookie"
        case .wbiRiskControlled:
            return "WBI / 风控拦截"
        case .networkUnavailable:
            return "网络不可用"
        case .healthy:
            return "登录正常"
        case .unknown:
            return "状态未知"
        }
    }

    var focusDetail: String {
        switch self {
        case .notLoggedIn:
            return "当前 Cookie 快照中没有有效登录会话。"
        case .sessionExpired:
            return "服务端不再接受当前会话，请重新登录。"
        case .missingCSRF:
            return "只读接口可用，但点赞、收藏和历史上报等写操作不可用。"
        case .wbiRiskControlled:
            return "请求被 B 站风控拦截，建议稍后重试。"
        case .networkUnavailable:
            return "无法连接接口；Cookie 内容没有被写入诊断。"
        case .healthy:
            return "登录会话和 CSRF Cookie 均可用。"
        case .unknown:
            return "接口返回无法安全分类的状态。"
        }
    }

    var focusSymbol: String {
        switch self {
        case .healthy:
            return "checkmark.circle.fill"
        case .notLoggedIn, .sessionExpired, .missingCSRF:
            return "person.crop.circle.badge.exclamationmark"
        case .wbiRiskControlled:
            return "shield.lefthalf.filled"
        case .networkUnavailable:
            return "wifi.slash"
        case .unknown:
            return "questionmark.circle"
        }
    }

    var focusColor: Color {
        switch self {
        case .healthy:
            return .green
        case .notLoggedIn, .unknown:
            return .secondary
        case .sessionExpired, .missingCSRF, .wbiRiskControlled:
            return .orange
        case .networkUnavailable:
            return .red
        }
    }
}
#endif
