import SwiftUI

struct RulesView: View {
    @EnvironmentObject var model: AppModel
    @State private var editingRule: ClassifyRule?

    @State private var previewCount = 0
    @State private var showRunConfirm = false
    @State private var runMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if model.rules.isEmpty {
                    Text("还没有规则，点右上角 + 新建")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(model.rules) { rule in
                        Button {
                            editingRule = rule
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(rule.name).font(.headline)
                                    Spacer()
                                    Text(rule.enabled ? "已启用" : "已停用")
                                        .font(.caption)
                                        .foregroundColor(rule.enabled ? .green : .secondary)
                                }
                                Text("\(rule.action.rawValue) → 「\(rule.targetAlbumName)」"
                                     + (rule.sourceAlbumLocalID == nil ? "" : " · 限定来源相簿"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                model.deleteRule(rule)
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                    .onMove { source, destination in
                        model.moveRules(from: source, to: destination)
                    }
                }
            }
            .navigationTitle("规则")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink { ExecutionLogView() } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    // 进入编辑态后即可拖动排序
                    EditButton()
                        .disabled(model.rules.count < 2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            previewAndRun()
                        } label: {
                            Image(systemName: "play.circle")
                        }
                        .disabled(model.rules.isEmpty)

                        Button {
                            editingRule = ClassifyRule(name: "新规则", targetAlbumName: "新相簿")
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(item: $editingRule) { rule in
                RuleEditView(rule: rule)
                    .environmentObject(model)
            }
            .confirmationDialog("执行全部规则？", isPresented: $showRunConfirm, titleVisibility: .visible) {
                Button("执行") { executeRules() }
                Button("取消", role: .cancel) {}
            } message: {
                let moveCount = model.rules.filter { $0.enabled && $0.action == .move }.count
                Text(moveCount > 0
                     ? "预计匹配 \(previewCount) 张；含 \(moveCount) 条「移动」规则：照片会被移出其它相簿（原图不会被删除），可从执行日志回退。"
                     : "预计匹配 \(previewCount) 张，将复制到对应相簿。")
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

    private func previewAndRun() {
        previewCount = RuleRunner().previewCount(rules: model.rules,
                                                 samples: model.samples,
                                                 records: model.store.records)
        showRunConfirm = true
    }

    private func executeRules() {
        Task {
            let outcome = await RuleRunner().runAll(rules: model.rules,
                                                    samples: model.samples,
                                                    records: model.store.records)
            await MainActor.run {
                outcome.logs.forEach { model.appendLog($0) }
                runMessage = outcome.summary
            }
        }
    }
}
