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
                            if !newAlbumPeople.isEmpty {
                                section("新增相簿", people: newAlbumPeople, showsMarkViewed: true)
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

    // MARK: - 分组

    /// 「新增相簿」：由相簿命名、但还没「标记已查看」的人物
    private var newAlbumPeople: [Person] {
        let new = model.newAlbumNames
        return model.people.filter { $0.nameIsAuto == true && new.contains($0.name) }
    }

    /// 「已有相簿」：相簿命名且已经标记过的人物
    private var existingAlbumPeople: [Person] {
        let new = model.newAlbumNames
        return model.people.filter { $0.nameIsAuto == true && !new.contains($0.name) }
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

    /// 按系统文件夹分节；没有文件夹时退回一个「已有相簿」节
    private var folderSections: [FolderSection] {
        let viewed = existingAlbumPeople
        guard !viewed.isEmpty else { return [] }
        guard !model.folderByAlbumName.isEmpty else {
            return [FolderSection(id: "已有相簿", title: "已有相簿", people: viewed)]
        }
        var byFolder: [String: [Person]] = [:]
        var ungrouped: [Person] = []
        for person in viewed {
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

    private func section(_ title: String,
                         people: [Person],
                         showsMarkViewed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(title)（\(people.count)）").font(.headline)
                Spacer()
                if showsMarkViewed {
                    Button("标记已查看") { model.markNewAlbumsViewed() }
                        .font(.footnote)
                }
            }
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
