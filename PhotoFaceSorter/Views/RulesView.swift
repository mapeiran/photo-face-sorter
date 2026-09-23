import SwiftUI

struct RulesView: View {
    @EnvironmentObject var model: AppModel
    @State private var editingRule: ClassifyRule?

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
                                Text("\(rule.action.rawValue) → 「\(rule.targetAlbumName)」")
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
                }
            }
            .navigationTitle("规则")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editingRule = ClassifyRule(name: "新规则", targetAlbumName: "新相簿")
                    } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink { ExecutionLogView() } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
            .sheet(item: $editingRule) { rule in
                RuleEditView(rule: rule)
                    .environmentObject(model)
            }
        }
    }
}
