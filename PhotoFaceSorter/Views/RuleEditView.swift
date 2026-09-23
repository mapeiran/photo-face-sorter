import SwiftUI

struct RuleEditView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State var rule: ClassifyRule
    @State private var testCount: Int?
    @State private var message: String?

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
                    if rule.action.isRisky {
                        Text("「移动」会从原相簿移除照片，操作不可逆，请谨慎。")
                            .font(.footnote)
                            .foregroundColor(.red)
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
        let ids = RuleEngine().matchedAssetIDs(for: rule,
                                               samples: model.store.samples,
                                               records: model.store.records)
        testCount = ids.count
    }
}
