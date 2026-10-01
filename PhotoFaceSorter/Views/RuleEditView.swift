import SwiftUI
import Photos

struct RuleEditView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State var rule: ClassifyRule
    @State private var testCount: Int?
    @State private var message: String?
    @State private var albums: [PHAssetCollection] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("规则名称", text: $rule.name)
                    Toggle("启用", isOn: $rule.enabled)
                }

                Section("条件") {
                    Picker("匹配方式", selection: $rule.matchMode) {
                        ForEach(RuleMatchMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Stepper("人脸数量 ≥ \(rule.minFaceCount)", value: $rule.minFaceCount, in: 1...10)
                }

                Section {
                    Picker("限定来源相簿", selection: $rule.sourceAlbumLocalID) {
                        Text("不限（全部照片）").tag(String?.none)
                        ForEach(albums, id: \.localIdentifier) { album in
                            Text(album.localizedTitle ?? "未命名").tag(String?.some(album.localIdentifier))
                        }
                    }
                } footer: {
                    Text("仅对来自该相簿的照片生效。留「不限」则扫描范围内的照片都会参与匹配。")
                }

                Section("包含人物（可多选）") {
                    if model.people.isEmpty {
                        Text("暂无人物，请先扫描").foregroundColor(.secondary)
                    } else {
                        ForEach(model.people) { person in
                            Button {
                                toggle(person)
                            } label: {
                                HStack {
                                    Text(person.displayName).foregroundColor(.primary)
                                    Spacer()
                                    if rule.personIDs.contains(person.id) {
                                        Image(systemName: "checkmark").foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("动作") {
                    Picker("动作", selection: $rule.action) {
                        ForEach(RuleAction.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("目标相簿名称", text: $rule.targetAlbumName)
                    if !albums.isEmpty {
                        Menu {
                            ForEach(albums, id: \.localIdentifier) { album in
                                Button(album.localizedTitle ?? "未命名") {
                                    rule.targetAlbumName = album.localizedTitle ?? ""
                                }
                            }
                        } label: {
                            Label("选择已有相簿", systemImage: "photo.on.rectangle")
                        }
                    }
                    if rule.action.isRisky {
                        Text("「移动」会把照片从其它相簿移出（原图不会被删除），之后可从执行日志回退。")
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }
                }

                Section {
                    Button("测试规则（预览匹配）") { testRule() }
                    if let testCount {
                        Text("匹配 \(testCount) 张照片").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("编辑规则")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                albums = PhotoLibraryService.shared.fetchUserAlbums()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        model.upsertRule(rule)
                        dismiss()
                    }
                    .disabled(rule.targetAlbumName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("提示", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func toggle(_ person: Person) {
        if let index = rule.personIDs.firstIndex(of: person.id) {
            rule.personIDs.remove(at: index)
        } else {
            rule.personIDs.append(person.id)
        }
    }

    private func testRule() {
        // 与真正执行时使用同一套来源相簿过滤，避免预览与实际结果不一致
        let engine = RuleEngine()
        let ids = engine.matchedAssetIDs(for: rule,
                                         samples: model.samples,
                                         records: model.store.records,
                                         albumMembership: engine.photoKitAlbumMembership())
        testCount = ids.count
    }
}
