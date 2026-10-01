import SwiftUI
import Photos

struct ScanView: View {
    @EnvironmentObject var model: AppModel
    /// 全 App 共享的扫描协调器（由 PhotoFaceSorterApp 注入）
    @EnvironmentObject var coordinator: ScanCoordinator
    @State private var authorized = false

    @State private var pendingRules: [ClassifyRule] = []
    @State private var showRunConfirm = false
    @State private var runMessage: String?
    @State private var showFullRescanConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if authorized {
                    // 扫描控件 + 系统相簿结构都要能滚动查看
                    ScrollView { scanContent.padding() }
                } else {
                    permissionContent.padding()
                }
            }
            .navigationTitle("扫描")
            .task {
                await requestAuthorization()
                model.refreshFolderGrouping()
                coordinator.refreshLibraryCounts()
            }
            .onChange(of: coordinator.state) { _, newState in
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
                     ? "共 \(pendingRules.count) 条规则，含 \(moveCount) 条「移动」：匹配照片会被移出其它相簿（原图不会被删除），可从执行日志回退。"
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
            if needsFullRescan {
                Text("识别方式已更新：现有的 \(model.samples.count) 个人脸特征与新版不兼容，"
                     + "继续聚类会得到错误的分组。请用下面的「全量重扫」重新识别"
                     + "（注意：人物命名会被重置）。")
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }

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
                    VStack(spacing: 10) {
                        scanLimitPicker

                        Button("开始扫描（增量）") {
                            coordinator.start(store: model.store, limit: scanLimit)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("全量重扫") {
                            showFullRescanConfirm = true
                        }
                        .font(.footnote)
                        .confirmationDialog("全量重扫会清空现有识别结果",
                                            isPresented: $showFullRescanConfirm,
                                            titleVisibility: .visible) {
                            Button("清空并重扫", role: .destructive) {
                                model.clearFaceCache()
                                coordinator.start(store: model.store, limit: scanLimit)
                            }
                            Button("取消", role: .cancel) {}
                        } message: {
                            Text("所有人脸样本与人物分组（含已命名的人物）都会被删除并重新识别，此操作无法撤销。")
                        }
                    }
                }
            }

            Text(scanLimitDescription)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if coordinator.state == .finished && coordinator.total == 0 {
                Text("没有待扫描的照片（散图都已扫描；其余照片已在相簿中，或被排除相簿过滤/未授权）")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if coordinator.state == .finished && coordinator.remaining > 0 {
                Text("本轮已达到单次扫描上限，还剩 \(coordinator.remaining) 张待扫描。"
                     + "进度已保存，再次点「开始扫描（增量）」即可接着扫。")
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }

            if coordinator.state == .finished && coordinator.unavailable > 0 {
                Text("有 \(coordinator.unavailable) 张照片暂时读不到（多为尚未从 iCloud 下载）。"
                     + "它们没有被标记为已扫描，下次扫描会自动重试。")
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }

            Divider()

            libraryStructure
        }
    }

    // MARK: - 系统相簿结构（扫描范围一目了然）

    /// 展示当前系统「照片」App 的全部文件夹、文件夹里的相簿，点进相簿看照片；
    /// 顶部说明哪些照片会被扫描跳过、哪些散图会被识别。
    private var libraryStructure: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("系统相簿结构").font(.headline)
                Spacer()
                Button {
                    model.refreshFolderGrouping()
                    coordinator.refreshLibraryCounts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .font(.footnote)
            }

            Text("相簿内 \(coordinator.albumPhotoCount) 张（扫描时跳过识别）"
                 + " · 不在相簿中的散图 \(coordinator.loosePhotoCount) 张（会被识别）")
                .font(.footnote)
                .foregroundColor(.secondary)

            if model.folderStructure.folderOrder.isEmpty
                && model.folderStructure.ungroupedAlbumTitles.isEmpty {
                Text("没有读取到文件夹或相簿")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(model.folderStructure.folderOrder, id: \.self) { folder in
                    folderDisclosure(title: folder,
                                     albums: model.folderStructure.albumsByFolder[folder] ?? [])
                }
                if !model.folderStructure.ungroupedAlbumTitles.isEmpty {
                    folderDisclosure(title: "未分组",
                                     albums: model.folderStructure.ungroupedAlbumTitles)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func folderDisclosure(title: String, albums: [String]) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(albums, id: \.self) { album in
                    NavigationLink {
                        AlbumDetailView(albumTitle: album)
                    } label: {
                        albumRow(album)
                    }
                    .buttonStyle(.plain)
                    if album != albums.last { Divider() }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundColor(.accentColor)
                Text(title).font(.subheadline).bold()
                Spacer()
                Text("\(albums.count) 个相簿")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func albumRow(_ title: String) -> some View {
        let summary = model.folderStructure.summaries[title]
        return HStack(spacing: 10) {
            Group {
                if let cover = summary?.coverLocalIdentifier {
                    AssetThumbnailView(localIdentifier: cover, contentMode: .fill, side: 40)
                } else {
                    Color(.secondarySystemBackground)
                        .overlay(Image(systemName: "rectangle.stack")
                            .font(.caption2)
                            .foregroundColor(.secondary))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(title).font(.subheadline).foregroundColor(.primary)
            Spacer()
            Text("\(summary?.photoCount ?? 0) 张")
                .font(.caption)
                .foregroundColor(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// 特征提取方式变了：缓存的人脸特征与新版不可比
    private var needsFullRescan: Bool {
        if case .needsFullRescan = model.embeddingStatus { return true }
        return false
    }

    // MARK: - 单次扫描上限

    /// 本次扫描允许处理的最大张数（设置里 0 = 不限制）。
    private var scanLimit: Int {
        ScanBatchPolicy.limit(setting: model.maxPhotosPerScan)
    }

    /// 扫描前就能改：大相册先设个上限，避免一次跑太久像卡死。
    private var scanLimitPicker: some View {
        HStack {
            Text("单次扫描上限")
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
            Picker("单次扫描上限", selection: $model.maxPhotosPerScan) {
                Text("不限制").tag(0)
                Text("100 张").tag(100)
                Text("200 张").tag(200)
                Text("500 张").tag(500)
                Text("1000 张").tag(1000)
            }
            .pickerStyle(.menu)
            .font(.footnote)
        }
    }

    private var scanLimitDescription: String {
        let limit = scanLimit
        if limit == Int.max {
            return "当前不限制单次扫描数量。相册很大时建议设个上限，扫完一批自动结束、进度已保存。"
        }
        return "一次最多扫描 \(limit) 张，扫完自动结束（进度已保存），可再次点「开始扫描」接着扫。"
    }

    private func stat(_ title: String, _ value: String) -> some View {        VStack(spacing: 4) {
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
                                                    records: model.store.records)
            await MainActor.run {
                outcome.logs.forEach { model.appendLog($0) }
                runMessage = outcome.summary
            }
        }
    }
}
