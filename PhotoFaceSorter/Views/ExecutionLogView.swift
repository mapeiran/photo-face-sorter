import SwiftUI

struct ExecutionLogView: View {
    @EnvironmentObject var model: AppModel

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
                            Button("回退本次归类") {
                                Task {
                                    try? await RuleEngine().rollback(log: log)
                                    await MainActor.run { model.markLogRolledBack(log) }
                                }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("执行日志")
    }
}
