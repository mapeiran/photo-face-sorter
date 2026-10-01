import SwiftUI

struct ExecutionLogView: View {
    @EnvironmentObject var model: AppModel

    @State private var rollingBack: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if model.logs.isEmpty {
                Text("暂无执行记录").foregroundColor(.secondary)
            } else {
                ForEach(model.logs) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(log.ruleName).font(.headline)
                            Spacer()
                            if log.rolledBack {
                                Text("已回退").font(.caption).foregroundColor(.orange)
                            }
                        }
                        Text("\(log.date.formatted()) · \(log.action.rawValue) → 「\(log.targetAlbumName)」 · \(log.assetLocalIdentifiers.count) 张")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !log.rolledBack {
                            Button(rollingBack.contains(log.id) ? "回退中…" : "回退本次归类") {
                                rollback(log)
                            }
                            .font(.caption)
                            .disabled(rollingBack.contains(log.id))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("执行日志")
        .alert("回退失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// 只有真正回退成功才标记「已回退」，避免失败时误导用户以为已经撤销
    private func rollback(_ log: ExecutionLog) {
        rollingBack.insert(log.id)
        Task {
            do {
                try await RuleEngine().rollback(log: log)
                await MainActor.run {
                    model.markLogRolledBack(log)
                    rollingBack.remove(log.id)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "无法回退「\(log.ruleName)」：\(error.localizedDescription)"
                    rollingBack.remove(log.id)
                }
            }
        }
    }
}
