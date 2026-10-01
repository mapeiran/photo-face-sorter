import SwiftUI

/// 「归类审核」的状态：待确认提议 + 每组的勾选。
@MainActor
final class ClassificationReviewModel: ObservableObject {
    @Published private(set) var items: [PendingClassification] = []
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false
    /// personID -> 勾选的照片
    @Published private(set) var selection: [UUID: Set<String>] = [:]

    func reload(people: [Person], samples: [FaceSample]) async {
        isLoading = true
        defer { isLoading = false }

        let loaded = await Task.detached(priority: .userInitiated) { () -> [PendingClassification] in
            let library = PhotoLibraryService.shared
            let albums = library.fetchUserAlbums()
            let albumedIDs = library.fetchAssetIdentifiers(in: albums)
            let titles = Set(albums.compactMap { $0.localizedTitle })
            return ClassificationProposalPolicy.proposals(people: people,
                                                          samples: samples,
                                                          albumedAssetIDs: albumedIDs,
                                                          existingAlbumTitles: titles)
        }.value

        items = loaded
        selection = Dictionary(uniqueKeysWithValues: loaded.map { ($0.personID, Set($0.assetIDs)) })
        didLoad = true
    }

    func selectedAssetIDs(for item: PendingClassification) -> [String] {
        let selected = selection[item.personID] ?? []
        return item.assetIDs.filter { selected.contains($0) }
    }

    func isSelected(_ assetID: String, in personID: UUID) -> Bool {
        selection[personID]?.contains(assetID) ?? false
    }

    func allSelected(in personID: UUID) -> Bool {
        guard let item = items.first(where: { $0.personID == personID }) else { return false }
        return selectedAssetIDs(for: item).count == item.assetIDs.count
    }

    func toggle(_ assetID: String, in personID: UUID) {
        var set = selection[personID] ?? []
        if set.contains(assetID) { set.remove(assetID) } else { set.insert(assetID) }
        selection[personID] = set
    }

    func selectAll(_ select: Bool, in personID: UUID) {
        guard let item = items.first(where: { $0.personID == personID }) else { return }
        selection[personID] = select ? Set(item.assetIDs) : []
    }

    func updateTarget(_ albumName: String, for personID: UUID) {
        guard let index = items.firstIndex(where: { $0.personID == personID }) else { return }
        let trimmed = albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items[index].targetAlbumName = trimmed
        items[index].albumExists = PhotoLibraryService.shared.album(named: trimmed) != nil
    }

    func updatePersonName(_ name: String, for personID: UUID) {
        guard let index = items.firstIndex(where: { $0.personID == personID }) else { return }
        items[index].personName = name
    }

    func remove(_ personID: UUID) {
        items.removeAll { $0.personID == personID }
        selection.removeValue(forKey: personID)
    }
}

/// 归类审核：AI 把散图识别成人物后，由你逐组确认写到哪本系统相簿。
struct ClassificationReviewView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var review = ClassificationReviewModel()

    @State private var pickerPersonID: UUID?
    @State private var renamePersonID: UUID?
    @State private var renameText = ""
    @State private var busyPersonID: UUID?
    @State private var message: String?
    /// 点缩略图 -> 全屏看图
    @State private var previewTarget: PreviewTarget?
    /// 长按 -> 图片详情
    @State private var detailTarget: PhotoDetailTarget?

    private struct PreviewTarget: Identifiable {
        let id = UUID()
        let assetIDs: [String]
        let index: Int
    }

    var body: some View {
        NavigationStack {
            Group {
                if review.isLoading {
                    ProgressView("正在统计待归类散图…")
                } else if review.items.isEmpty {
                    ContentUnavailableView("没有待归类的散图",
                                           systemImage: "checkmark.circle",
                                           description: Text("先到「扫描」识别。不在任何相簿中的照片会出现在这里，等你确认写到哪本相簿。"))
                } else {
                    List {
                        Section {
                            Text("共 \(review.items.count) 组 · \(totalCount) 张散图待确认。"
                                 + "只有确认后才会写入系统相簿。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Text("点照片看大图，点右上角圆圈勾选 / 取消，长按照片看图片详情。")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        ForEach(review.items) { item in
                            proposal(item)
                        }
                    }
                }
            }
            .navigationTitle("归类审核")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await reload() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(review.isLoading)
                }
            }
            .task { if !review.didLoad { await reload() } }
            .sheet(isPresented: Binding(get: { pickerPersonID != nil },
                                        set: { if !$0 { pickerPersonID = nil } })) {
                if let personID = pickerPersonID {
                    AlbumPickerView(title: "目标相簿") { name in
                        review.updateTarget(name, for: personID)
                    }
                }
            }
            .alert("重命名人物", isPresented: Binding(get: { renamePersonID != nil },
                                                     set: { if !$0 { renamePersonID = nil } })) {
                TextField("名称", text: $renameText)
                Button("取消", role: .cancel) { renamePersonID = nil }
                Button("保存") { commitRename() }
            }
            .alert("完成", isPresented: Binding(get: { message != nil },
                                              set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
            .fullScreenCover(item: $previewTarget) { target in
                PhotoViewerView(assetIdentifiers: target.assetIDs, initialIndex: target.index)
            }
            .sheet(item: $detailTarget) { target in
                PhotoDetailView(assetLocalIdentifier: target.id)
            }
        }
    }

    /// 单张缩略图：点图看大图、点右上角圆圈勾选、长按看详情 / 去「照片」搜索
    private func thumbnail(item: PendingClassification,
                           assetID: String,
                           index: Int) -> some View {
        let selected = review.isSelected(assetID, in: item.personID)
        return ZStack(alignment: .topTrailing) {
            AssetThumbnailView(localIdentifier: assetID, contentMode: .fill, side: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture {
                    previewTarget = PreviewTarget(assetIDs: item.assetIDs, index: index)
                }

            Button {
                review.toggle(assetID, in: item.personID)
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(selected ? .accentColor : .white)
                    .padding(4)
                    .background(Circle().fill(.thinMaterial))
            }
            .buttonStyle(.plain)
            .padding(3)
        }
        .contextMenu {
            Button {
                previewTarget = PreviewTarget(assetIDs: item.assetIDs, index: index)
            } label: {
                Label("查看大图", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button {
                detailTarget = PhotoDetailTarget(id: assetID)
            } label: {
                Label("查看图片详情", systemImage: "info.circle")
            }
            Button {
                PhotoLibraryService.searchSystemPhotos(forAssetLocalIdentifier: assetID)
            } label: {
                Label("在「照片」中按日期搜索", systemImage: "photo.on.rectangle.angled")
            }
        }
    }

    private var totalCount: Int {
        review.items.reduce(0) { $0 + $1.assetIDs.count }
    }

    private func reload() async {
        await review.reload(people: model.people, samples: model.samples)
    }

    private func proposal(_ item: PendingClassification) -> some View {
        let selectedCount = review.selectedAssetIDs(for: item).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(item.personName).font(.headline)
                Text(item.albumExists ? "已有相簿" : "新建相簿")
                    .font(.caption2)
                    .foregroundColor(item.albumExists ? .secondary : .accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((item.albumExists ? Color.secondary : Color.accentColor).opacity(0.15),
                                in: Capsule())
                Spacer()
                Button("重命名") {
                    renameText = item.personName
                    renamePersonID = item.personID
                }
                .font(.caption)
            }

            HStack {
                Text("目标相簿：\(item.targetAlbumName)").font(.subheadline)
                Spacer()
                Button("更改") { pickerPersonID = item.personID }
                    .font(.caption)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(item.assetIDs.enumerated()), id: \.element) { index, assetID in
                        thumbnail(item: item, assetID: assetID, index: index)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                Button("确认加入") { confirm(item, action: .copy) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCount == 0 || busyPersonID != nil)
                Button("移动加入") { confirm(item, action: .move) }
                    .buttonStyle(.bordered)
                    .disabled(selectedCount == 0 || busyPersonID != nil)
                Spacer()
                Button("跳过") { review.remove(item.personID) }
                    .buttonStyle(.bordered)
                    .disabled(busyPersonID != nil)
            }
            .font(.footnote)

            HStack {
                Text("已选 \(selectedCount)/\(item.assetIDs.count) 张")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(review.allSelected(in: item.personID) ? "取消全选" : "全选") {
                    review.selectAll(!review.allSelected(in: item.personID), in: item.personID)
                }
                .font(.caption2)
            }
        }
        .padding(.vertical, 4)
    }

    private func confirm(_ item: PendingClassification, action: RuleAction) {
        let assetIDs = review.selectedAssetIDs(for: item)
        guard !assetIDs.isEmpty else { return }
        busyPersonID = item.personID
        Task {
            let result = await model.exportAssetsToAlbum(assetIDs,
                                                         albumName: item.targetAlbumName,
                                                         action: action)
            message = result
            review.remove(item.personID)
            busyPersonID = nil
        }
    }

    private func commitRename() {
        defer { renamePersonID = nil }
        guard let personID = renamePersonID,
              let person = model.people.first(where: { $0.id == personID }) else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.renamePerson(person, to: name)
        review.updatePersonName(name, for: personID)
        review.updateTarget(name, for: personID)
    }
}
