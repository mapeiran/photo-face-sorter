import SwiftUI

struct PeopleView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var coordinator: ScanCoordinator

    @State private var editMode = false
    @State private var selected: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if model.people.isEmpty {
                    ContentUnavailableView("暂无人物",
                                           systemImage: "person.2",
                                           description: Text("先到「扫描」识别人像"))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if !model.newAlbumNames.isEmpty {
                                newAlbumsBanner
                            }
                            ForEach(folderSections) { group in
                                section(group.title, people: group.people)
                            }
                            if !otherPeople.isEmpty {
                                section("AI 分组（没有相簿）", people: otherPeople)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("人物")
            // 系统「照片」App 里的相簿文件夹会变，进页面时刷新一次
            .task { model.refreshFolderGrouping() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        model.recluster()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    // 扫描进行中不能重聚类：两者都会读改写 store.samples，会互相覆盖
                    .disabled(model.samples.isEmpty || model.isReclustering || coordinator.state == .scanning)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editMode ? "完成" : "选择") {
                        editMode.toggle()
                        selected.removeAll()
                    }
                    .disabled(model.people.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if editMode {
                    HStack(spacing: 24) {
                        Button("合并") { mergeSelected() }
                            .disabled(selected.count < 2)
                        Button("删除", role: .destructive) { deleteSelected() }
                            .disabled(selected.isEmpty)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

    /// 有新相簿时顶部提示：新增的相簿已经按文件夹归位，只是打了「新增」标记
    private var newAlbumsBanner: some View {
        HStack(spacing: 12) {
            Label("新增相簿 \(model.newAlbumNames.count) 个", systemImage: "sparkles")
                .font(.subheadline)
            Spacer()
            Button("标记已查看") { model.markNewAlbumsViewed() }
                .font(.footnote)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 分组

    /// 所有相簿命名的人物（含还没标记已查看的新相簿）
    private var albumPeople: [Person] {
        model.people.filter { $0.nameIsAuto == true }
    }

    /// 其余：AI 聚类出的自动编号人物，以及用户手动命名的人物
    private var otherPeople: [Person] {
        model.people.filter { $0.nameIsAuto != true }
    }

    /// 人物页的相簿分节：跟随系统「照片」App 的文件夹
    private struct FolderSection: Identifiable {
        let id: String
        let title: String
        let people: [Person]
    }

    /// 按系统文件夹分节；系统里完全没有文件夹时退回一个「相簿」节
    private var folderSections: [FolderSection] {
        let albums = albumPeople
        guard !albums.isEmpty else { return [] }
        guard !model.folderByAlbumName.isEmpty else {
            return [FolderSection(id: "相簿", title: "相簿", people: albums)]
        }
        var byFolder: [String: [Person]] = [:]
        var ungrouped: [Person] = []
        for person in albums {
            if let folder = model.folderByAlbumName[person.name] {
                byFolder[folder, default: []].append(person)
            } else {
                ungrouped.append(person)
            }
        }
        var sections: [FolderSection] = []
        for folder in model.folderOrder where byFolder[folder] != nil {
            sections.append(FolderSection(id: folder,
                                          title: folder,
                                          people: byFolder.removeValue(forKey: folder) ?? []))
        }
        for folder in byFolder.keys.sorted() {
            sections.append(FolderSection(id: folder,
                                          title: folder,
                                          people: byFolder[folder] ?? []))
        }
        if !ungrouped.isEmpty {
            sections.append(FolderSection(id: "未分组", title: "未分组", people: ungrouped))
        }
        return sections
    }

    private func isNew(_ person: Person) -> Bool {
        model.newAlbumNames.contains(person.name)
    }

    private func section(_ title: String, people: [Person]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(title)（\(people.count)）").font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(people) { person in
                    if editMode {
                        Button { toggle(person) } label: { personCell(person) }
                            .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            PersonDetailView(personID: person.id)
                        } label: {
                            personCell(person)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func personCell(_ person: Person) -> some View {
        let personSamples = model.samples(of: person)
        let sample = personSamples.first
        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let sample {
                        // 展示整张原图（按比例缩小），不要人脸裁剪图
                        AssetThumbnailView(localIdentifier: sample.assetLocalIdentifier,
                                           contentMode: .fit,
                                           side: 80)
                    } else {
                        Color(.secondarySystemBackground)
                            .overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if isNew(person) {
                        Text("新增")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                            .padding(3)
                    }
                }

                if editMode {
                    Image(systemName: selected.contains(person.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(selected.contains(person.id) ? .accentColor : .secondary)
                        .background(Circle().fill(.background))
                        .offset(x: 2, y: -2)
                }
            }

            Text(person.displayName).font(.caption).lineLimit(1)
            Text("\(personSamples.count) 张")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func toggle(_ person: Person) {
        if selected.contains(person.id) { selected.remove(person.id) }
        else { selected.insert(person.id) }
    }

    private func mergeSelected() {
        let picked = model.people.filter { selected.contains($0.id) }
        guard let target = picked.first else { return }
        for other in picked.dropFirst() {
            model.mergePerson(other, into: target)
        }
        editMode = false
        selected.removeAll()
    }

    private func deleteSelected() {
        for person in model.people where selected.contains(person.id) {
            model.deletePerson(person)
        }
        editMode = false
        selected.removeAll()
    }
}
