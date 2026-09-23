import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var autoScan: AutoScanManager

    var body: some View {
        NavigationStack {
            Form {
                Section("隐私") {
                    Text("所有识别人脸在设备本地完成，图片与人脸特征不会上传到任何服务器。缓存仅存于 App 沙盒，卸载 App 即自动清除。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("自动扫描") {
                    Toggle("启用增量自动扫描", isOn: $model.autoScanEnabled)
                        .onChange(of: model.autoScanEnabled) { autoScan.setEnabled($0) }
                    Toggle("仅充电时后台扫描", isOn: $model.chargeOnlyBackground)
                        .disabled(!model.autoScanEnabled)
                    if let date = autoScan.lastRunDate {
                        LabeledContent("最近自动扫描", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let msg = autoScan.lastRunMessage {
                        Text(msg).font(.caption).foregroundColor(.secondary)
                    }
                    Text("后台扫描受 iOS 系统调度限制，不能保证实时。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("识别与聚类") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("聚类阈值")
                            Spacer()
                            Text(String(format: "%.2f", model.clusterThreshold))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $model.clusterThreshold, in: 0.5...1.5, step: 0.05)
                        Text("越小分组越细（同一人易被拆开）；越大越粗（不同人易被合并）。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Button("按新阈值重新聚类") { model.recluster() }
                }

                Section("缓存管理") {
                    Button("清空人脸识别缓存") { model.clearFaceCache() }
                    Button("清空执行日志") { model.clearLogs() }
                }

                Section("扫描范围") {
                    NavigationLink {
                        ExcludedAlbumsView()
                    } label: {
                        Label("排除相簿", systemImage: "eye.slash")
                    }
                }

                Section("权限") {
                    Button("打开系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("人物数", value: "\(model.people.count)")
                    LabeledContent("规则数", value: "\(model.rules.count)")
                }
            }
            .navigationTitle("设置")
        }
    }
}
