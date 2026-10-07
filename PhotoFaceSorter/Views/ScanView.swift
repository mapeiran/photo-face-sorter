import SwiftUI
import Photos

struct ScanView: View {
    @EnvironmentObject var model: AppModel
    /// 全 App 共享的扫描协调器（由 PhotoFaceSorterApp 注入）
    @EnvironmentObject var coordinator: ScanCoordinator
    @State private var authorized = false

    @State private var showFullRescanConfirm = false
    @State private var showAlbumRescanConfirm = false
    /// 已有扫描在跑，或状态刚好变了 —— 提示用户而不是静默失败
    @State private var showScanBusyAlert = false
    /// 扫描页相簿结构里被展开的文件夹（默认折叠）
    @State private var expandedFolders: Set<String> = []

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
            .alert("正在扫描", isPresented: $showScanBusyAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text("已经有一个扫描任务在跑（可能是后台自动扫描）。"
                     + "等它结束、或先在上面终止它，再试一次。")
            }
            .task {
                await requestAuthorization()
                model.refreshFolderGrouping()
                coordinator.refreshLibraryCounts()
            }
            .onChange(of: coordinator.state) { _, newState in
                if newState == .finished {
                    model.reload()
                    model.loadSamplesAsync()
                }
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
                     + "（它会连相簿内的照片一起重认；注意人物命名会被重置）。")
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

            if coordinator.state == .scanning {
                Text("识别到的分组会实时出现在「人物」页，不必等整批扫完。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
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
                            startScan(limit: scanLimit, scope: .loosePhotos)
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
                                // 先确认能启动，再清缓存：否则会「数据清了、扫描没跑起来」
                                guard coordinator.canStartScan else {
                                    showScanBusyAlert = true
                                    return
                                }
                                model.clearFaceCache()
                                startScan(limit: scanLimit, scope: .allPhotos)
                            }
                            Button("取消", role: .cancel) {}
                        } message: {
                            Text("所有人脸样本与人物分组（含已命名的人物）都会被删除，"
                                 + "并重新识别全部照片（含相簿内的），此操作无法撤销。")
                        }

                        // 相簿内照片默认不参与识别（视为已归类）。换了识别方式、或在「照片」里
                        // 新整理过相簿之后，用这个按钮把它们的脸重新认一遍，人物命名才有依据。
                        Button("重新识别相簿内照片") {
                            showAlbumRescanConfirm = true
                        }
                        .font(.footnote)
                        .disabled(needsFullRescan)
                        .confirmationDialog("重新识别相簿内的照片？",
                                            isPresented: $showAlbumRescanConfirm,
                                            titleVisibility: .visible) {
                            Button("开始重新识别") {
                                // 刻意不设数量上限：一次把**所有相簿**的照片重新识别完。
                                // 清旧样本由扫描计划内部完成（原子），这里不做破坏性准备。
                                startScan(limit: .max, scope: .albumPhotos)
                            }
                            Button("取消", role: .cancel) {}
                        } message: {
                            Text("会丢弃**所有相簿**（含系统相簿）里照片的旧人脸特征并重新识别，"
                                 + "让「按相簿给人物命名」重新有据可依。只读相簿，不会修改任何相簿内容。"
                                 + "共 \(coordinator.allAlbumPhotoCount) 张，本次不设数量上限。")
                        }
                    }
                }
            }

            Text(scanLimitDescription)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if coordinator.state == .finished && coordinator.total == 0 {
                Text("没有待扫描的照片（散图都已扫描；相簿内的照片默认不参与识别，"
                     + "要用「重新识别相簿内照片」；也可能被排除相簿过滤或未授权）")
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

            if coordinator.state == .finished && coordinator.scanned > 0 {
                Text("识别完成，去「归类」页确认这些散图写到哪本相簿。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            libraryStructure
        }
    }

    /// 启动一次扫描。起不来（已有任务在跑 / 暂停中）就提示，而不是静默失败 ——
    /// 界面上的破坏性准备（清空缓存等）都必须在 `coordinator.canStartScan` 为真时才做。
    private func startScan(limit: Int, scope: ScanCoordinator.Scope) {
        if !coordinator.start(store: model.store, limit: limit, scope: scope) {
            showScanBusyAlert = true
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
                // 文件夹可以逐个展开/折叠，也可以一键全部展开或折叠
                Menu {
                    Button("展开全部") { expandedFolders = Set(structureFolderTitles) }
                    Button("折叠全部") { expandedFolders.removeAll() }
                } label: {
                    Image(systemName: "rectangle.expand.vertical")
                }
                .font(.footnote)
                Button {
                    model.refreshFolderGrouping()
                    coordinator.refreshLibraryCounts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .font(.footnote)
            }

            // 三个动作**各自**会识别多少张，必须分开写清楚。
            // 之前只标了「散图会被识别」，而「全量重扫」现在连相簿内的照片一起扫，
            // 于是按散图数量选了 1000 上限、实际却扫了 1000 —— 看起来像没按实际数量扫。
            VStack(alignment: .leading, spacing: 2) {
                Text("照片总数 \(totalPhotoCount) 张")
                Text("· 增量扫描：「开始扫描（增量）」只识别散图 \(coordinator.loosePhotoCount) 张"
                     + "（其余 \(coordinator.albumPhotoCount) 张在默认跳过的相簿里）")
                Text("· 全量重扫：「清空并重扫」识别全部 \(totalPhotoCount) 张（含相簿内照片）")
                Text("· 重新识别：「重新识别相簿内照片」识别所有相簿内的 \(coordinator.allAlbumPhotoCount) 张")
            }
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

    /// 结构里全部可展开的文件夹标题（含「未分组」）
    private var structureFolderTitles: [String] {
        var titles = model.folderStructure.folderOrder
        if !model.folderStructure.ungroupedAlbumTitles.isEmpty { titles.append("未分组") }
        return titles
    }

    private func folderDisclosure(title: String, albums: [String]) -> some View {
        let isExpanded = Binding(
            get: { expandedFolders.contains(title) },
            set: { expanded in
                if expanded { expandedFolders.insert(title) } else { expandedFolders.remove(title) }
            })
        return DisclosureGroup(isExpanded: isExpanded) {
            VStack(spacing: 0) {
                ForEach(albums, id: \.self) { album in
                    NavigationLink {
                        AlbumDetailView(albumTitle: album)
                    } label: {
                        albumRow(album)
                    }
                    .buttonStyle(.plain)
                    // 长按即可手动切换「是否排除此相簿」
                    .contextMenu {
                        Button {
                            model.setAlbumExcludedFromScan(!model.isAlbumExcludedFromScan(title: album),
                                                           title: album)
                            coordinator.refreshLibraryCounts()
                        } label: {
                            if model.isAlbumExcludedFromScan(title: album) {
                                Label("取消排除，参与扫描", systemImage: "eye")
                            } else {
                                Label("从扫描中排除", systemImage: "eye.slash")
                            }
                        }
                    }
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
            if model.isAlbumExcludedFromScan(title: title) {
                Image(systemName: "eye.slash")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
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

    /// 相册里的照片总数。默认跳过的相簿内 + 散图 = 全部（见 `LibraryPhotoCountPolicy`），
    /// 也就是「全量重扫」实际会识别的张数。
    private var totalPhotoCount: Int {
        coordinator.albumPhotoCount + coordinator.loosePhotoCount
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
        return "单次最多扫描 \(limit) 张。这只是上限：实际待识别不足 \(limit) 张时只扫实际数量。"
             + "扫完自动结束（进度已保存），可再次点「开始扫描」接着扫。"
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

}
