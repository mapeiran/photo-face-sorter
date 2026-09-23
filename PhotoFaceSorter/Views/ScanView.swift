import SwiftUI
import Photos

struct ScanView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var coordinator = ScanCoordinator()
    @State private var authorized = false

    @State private var pendingRules: [ClassifyRule] = []
    @State private var showRunConfirm = false
    @State private var runMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if authorized {
                    scanContent
                } else {
                    permissionContent
                }
            }
            .padding()
            .navigationTitle("扫描")
            .task { await requestAuthorization() }
            .onChange(of: coordinator.state) { newState in
                if newState == .finished {
                    model.reload()
                    model.loadSamplesAsync()
                    prepareRules()
                }
            }
            .confirmationDialog("执行自动归类规则？", isPresented: $showRunConfirm, titleVisibility: .visible) {
                Button("执行") { executePendingRules() }
                Button("稍后", role: .cancel) { pendingRules = [] }
            } message: {
                let moveCount = pendingRules.filter { $0.action == .move }.count
                Text(moveCount > 0
                     ? "共 \(pendingRules.count) 条规则，含 \(moveCount) 条「移动」（原相簿不再保留，不可逆）。"
                     : "共 \(pendingRules.count) 条规则，将把匹配照片复制到目标相簿。")
            }
            .alert("完成", isPresented: Binding(
                get: { runMessage != nil },
                set: { if !$0 { runMessage = nil } })) {
                Button("好", role: .cancel) { runMessage = nil }
            } message: {
                Text(runMessage ?? "")
            }
        }
    }

    private var permissionContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("需要相册访问权限").font(.headline)
            Text("所有识别在本地完成，图片不会上传。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("申请权限") {
                Task { await requestAuthorization() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var scanContent: some View {
        VStack(spacing: 20) {
            ProgressView(value: coordinator.progress)
                .frame(maxWidth: .infinity)
            Text("\(coordinator.state.title) · \(Int(coordinator.progress * 100))%")
                .font(.headline)

            HStack(spacing: 24) {
                stat("待扫描", "\(coordinator.total)")
                stat("已扫描", "\(coordinator.scanned)")
                stat("含人像", "\(coordinator.facePhotos)")
                stat("人脸数", "\(coordinator.faceCount)")
            }

            HStack(spacing: 12) {
                if coordinator.state == .scanning {
                    Button("暂停") { coordinator.pause() }.buttonStyle(.bordered)
                    Button("终止") { coordinator.stop() }.buttonStyle(.bordered).tint(.red)
                } else if coordinator.state == .paused {
                    Button("继续") { coordinator.resume() }.buttonStyle(.borderedProminent)
                    Button("终止") { coordinator.stop() }.buttonStyle(.bordered).tint(.red)
                } else {
                    Button("开始扫描") {
                        coordinator.start(store: model.store)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3).bold()
            Text(title).font(.caption).foregroundColor(.secondary)
        }
    }

    private func requestAuthorization() async {
        let status = await PhotoLibraryService().requestAuthorization()
        authorized = (status == .authorized || status == .limited)
    }

    // MARK: - 规则

    private func prepareRules() {
        let enabled = model.rules.filter { $0.enabled }
        guard !enabled.isEmpty else { return }
        pendingRules = enabled
        showRunConfirm = true
    }

    private func executePendingRules() {
        let rules = pendingRules
        pendingRules = []
        Task {
            let outcome = await RuleRunner().runAll(rules: rules,
                                                    samples: model.samples,
                                                    records: model.store.records,
                                                    store: model.store)
            await MainActor.run {
                outcome.logs.forEach { model.appendLog($0) }
                runMessage = "已执行 \(outcome.logs.count) 条规则：复制 \(outcome.copiedCount) 张，移动 \(outcome.movedCount) 张"
            }
        }
    }
}
