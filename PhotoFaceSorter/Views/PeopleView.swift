import SwiftUI

struct PeopleView: View {
    @EnvironmentObject var model: AppModel

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
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(model.people) { person in
                                if editMode {
                                    Button { toggle(person) } label: { personCell(person) }
                                        .buttonStyle(.plain)
                                } else {
                                    NavigationLink {
                                        PersonDetailView(person: person)
                                    } label: {
                                        personCell(person)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("人物")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        model.recluster()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.store.samples.isEmpty)
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

    private func personCell(_ person: Person) -> some View {
        let sample = model.samples(of: person).first
        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let sample {
                        AssetThumbnailView(localIdentifier: sample.assetLocalIdentifier,
                                           boundingBox: sample.boundingBox,
                                           side: 80)
                    } else {
                        Color(.secondarySystemBackground)
                            .overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())

                if editMode {
                    Image(systemName: selected.contains(person.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(selected.contains(person.id) ? .accentColor : .secondary)
                        .background(Circle().fill(.background))
                        .offset(x: 2, y: -2)
                }
            }

            Text(person.displayName).font(.caption).lineLimit(1)
            Text("\(model.samples(of: person).count) 张")
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
