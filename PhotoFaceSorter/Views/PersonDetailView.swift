import SwiftUI

struct PersonDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// 只持有 id，人物本身每次渲染都从 model 取。
    ///
    /// 之前是把 `Person` 值本身放进 `@State`，那是一个**快照**：
    /// 重命名、合并、或重聚类改动之后，这个页面会继续显示并操作过期数据
    /// （例如把过期副本再拿去调用 `model.renamePerson` / `mergePerson`）。
    let personID: UUID

    private enum AlertKind { case rename, split }
    @State private var alertKind: AlertKind?
    @State private var newName = ""
    @State private var splitName = ""

    @State private var showMerge = false
    @State private var showMove = false

    @State private var selectMode = false
    @State private var selected: Set<UUID> = []
    /// 点击缩略图后全屏查看原图
    @State private var previewSample: FaceSample?

    private var person: Person? { model.people.first { $0.id == personID } }
    private var samples: [FaceSample] { person.map { model.samples(of: $0) } ?? [] }
    private var selectedSamples: [FaceSample] { samples.filter { selected.contains($0.id) } }

    var body: some View {
        Group {
            if let person {
                detail(for: person)
            } else {
                // 人物已被删除或合并（例如最后一个样本人脸被移走），自动退回列表。
                // 用 onAppear 而不是 task：dismiss() 不必跨并发边界。
                Color.clear.onAppear { dismiss() }
            }
        }
    }

    private func detail(for person: Person) -> some View {
        List {
            Section("名称") {
                HStack {
                    Text(person.displayName)
                    Spacer()
                    Button("重命名") {
                        newName = person.name
                        alertKind = .rename
                    }
                }
            }

            Section {
                Toggle("选择模式（批量调整）", isOn: $selectMode)
                    .onChange(of: selectMode) { _, newValue in if !newValue { selected.removeAll() } }
            }

            Section("照片（\(samples.count)）") {
                if samples.isEmpty {
                    Text("暂无样本人脸").foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
                        ForEach(samples) { sample in
                            sampleCell(sample)
                        }
                    }
                }
            }
        }
        .navigationTitle(person.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showMerge = true } label: {
                        Label("合并到其他人物", systemImage: "arrow.triangle.merge")
                    }
                    Button(role: .destructive) {
                        model.deletePerson(person)
                        dismiss()
                    } label: {
                        Label("删除该人物", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selectMode && !selected.isEmpty {
                HStack(spacing: 16) {
                    Button("移出为新人") {
                        splitName = ""
                        alertKind = .split
                    }
                    Button("移到其他人物") { showMove = true }
                    Button("标记非人物", role: .destructive) {
                        model.ignoreSamples(selectedSamples)
                        clearSelection()
                    }
                }
                .font(.subheadline)
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .alert(alertKind == .rename ? "重命名" : "拆分新人物",
               isPresented: Binding(get: { alertKind != nil },
                                    set: { if !$0 { alertKind = nil } })) {
            if alertKind == .rename {
                TextField("名称", text: $newName)
                Button("取消", role: .cancel) { alertKind = nil }
                Button("保存") {
                    // 只改 model；页面显示的 name 会自动跟着更新，不需要再手动改本地副本
                    model.renamePerson(person, to: newName)
                    alertKind = nil
                }
            } else {
                TextField("新人物名称", text: $splitName)
                Button("取消", role: .cancel) { alertKind = nil }
                Button("创建") {
                    model.split(selectedSamples, name: splitName)
                    clearSelection()
                    alertKind = nil
                }
            }
        }
        .sheet(isPresented: $showMerge) {
            PersonPickerView(title: "合并到", people: model.people.filter { $0.id != person.id }) { target in
                model.mergePerson(person, into: target)
                dismiss()
            }
        }
        .sheet(isPresented: $showMove) {
            PersonPickerView(title: "移动到", people: model.people.filter { $0.id != person.id }) { target in
                model.moveSamples(selectedSamples, to: target)
                clearSelection()
            }
        }
        .fullScreenCover(item: $previewSample) { sample in
            PhotoViewerView(localIdentifier: sample.assetLocalIdentifier,
                            boundingBox: sample.boundingBox)
        }
    }

    @ViewBuilder
    private func sampleCell(_ sample: FaceSample) -> some View {
        let thumb = AssetThumbnailView(localIdentifier: sample.assetLocalIdentifier,
                                       boundingBox: sample.boundingBox,
                                       side: 80)
            .cornerRadius(6)

        if selectMode {
            Button {
                if selected.contains(sample.id) { selected.remove(sample.id) }
                else { selected.insert(sample.id) }
            } label: {
                thumb.overlay(alignment: .topTrailing) {
                    Image(systemName: selected.contains(sample.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selected.contains(sample.id) ? .accentColor : .white)
                        .padding(2)
                }
            }
            .buttonStyle(.plain)
        } else {
            // 缩略图只有 80pt，点开看原图/更清晰的画面
            Button {
                previewSample = sample
            } label: {
                thumb
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    model.moveSamples([sample], to: nil)
                } label: {
                    Label("移出人物", systemImage: "person.badge.minus")
                }
                Button(role: .destructive) {
                    model.ignoreSamples([sample])
                } label: {
                    Label("标记非人物", systemImage: "eye.slash")
                }
            }
        }
    }

    private func clearSelection() {
        selected.removeAll()
        selectMode = false
    }
}
