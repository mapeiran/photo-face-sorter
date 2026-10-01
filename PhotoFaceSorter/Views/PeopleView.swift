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
                // 即使还没有人物，只要系统里有文件夹/相簿，也要把结构展示出来
                if model.people.isEmpty && model.folderStructure.isEmpty {
                    ContentUnavailableView("暂无人物",
                                           systemImage: "person.2",
                                           description: Text("先到「扫描」识别人像"))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if !model.newAlbumNames.isEmpty {
                                newAlbumsBanner
                            }
                            ForEach(sections) { group in
                                section(group)
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

    /// 全部文件夹（含还没有人物的）+ 未分组相簿 + AI 分组
    private var sections: [PeopleSectionBuilder.Section] {
        PeopleSectionBuilder.sections(people: model.people, structure: model.folderStructure)
    }

    private func isNew(_ person: Person) -> Bool {
        model.newAlbumNames.contains(person.name)
    }

    private func section(_ group: PeopleSectionBuilder.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title).font(.headline)
                Text(subtitle(for: group))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if group.isEmpty {
                Text("（空文件夹）")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(group.people) { person in
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
                    ForEach(group.albumTitles, id: \.self) { title in
                        if editMode {
                            albumCell(title).opacity(0.5)
                        } else {
                            NavigationLink {
                                AlbumDetailView(albumTitle: title)
                            } label: {
                                albumCell(title)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func subtitle(for group: PeopleSectionBuilder.Section) -> String {
        var parts: [String] = []
        if !group.people.isEmpty { parts.append("\(group.people.count) 位人物") }
        if !group.albumTitles.isEmpty { parts.append("\(group.albumTitles.count) 个相簿") }
        return parts.joined(separator: " · ")
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

    /// 还没有对应人物的系统相簿：展示封面、名字与张数，点开可看相簿内容
    private func albumCell(_ title: String) -> some View {
        let summary = model.folderStructure.summaries[title]
        return VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let cover = summary?.coverLocalIdentifier {
                        AssetThumbnailView(localIdentifier: cover, contentMode: .fill, side: 80)
                    } else {
                        Color(.secondarySystemBackground)
                            .overlay(Image(systemName: "rectangle.stack").foregroundColor(.secondary))
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Image(systemName: "rectangle.stack.fill")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(.black.opacity(0.35), in: Circle())
                    .padding(3)
            }

            Text(title).font(.caption).lineLimit(1)
            Text("\(summary?.photoCount ?? 0) 张")
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
