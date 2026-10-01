import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var autoScan: AutoScanManager
    @EnvironmentObject var coordinator: ScanCoordinator

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
                        .onChange(of: model.autoScanEnabled) { _, newValue in autoScan.setEnabled(newValue) }
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
                        Slider(value: $model.clusterThreshold,
                               in: ClusterThreshold.range,
                               step: ClusterThreshold.step)
                        Text("越小分组越细（同一人易被拆开）；越大越粗（不同人易被合并）。"
                             + "自动分组会优先用照片所在相簿的名字命名。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Button(model.isReclustering ? "正在重新聚类…" : "按新阈值重新聚类") { model.recluster() }
                        // 扫描进行中不能重聚类：两者都会读改写 store.samples，会互相覆盖
                        .disabled(model.isReclustering || coordinator.state == .scanning)
                    if coordinator.state == .scanning {
                        Text("扫描进行中，结束后才能重新聚类。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section("网络识别人像") {
                    Toggle("启用（以图搜图）", isOn: $model.visualSearchEnabled)
                    SecureField("Bing Visual Search 密钥", text: $model.visualSearchAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("关闭时一切都在本地完成。开启后，只有你主动点「网络识别人像」时，"
                         + "才会把当前这一张照片上传到 Bing Visual Search 换取网页结果。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("缓存管理") {
                    Button("清空人脸识别缓存") { model.clearFaceCache() }
                    Button("清空执行日志") { model.clearLogs() }
                    NavigationLink {
                        ExecutionLogView()
                    } label: {
                        Label("执行日志（可回退归类）", systemImage: "list.bullet.rectangle")
                    }
                }

                Section("扫描范围") {
                    Picker("单次扫描上限", selection: $model.maxPhotosPerScan) {
                        Text("不限制").tag(0)
                        Text("100 张").tag(100)
                        Text("200 张").tag(200)
                        Text("500 张").tag(500)
                        Text("1000 张").tag(1000)
                    }
                    Text("每次扫描最多处理这么多张，扫完一批就结束（进度已保存），可再次点「开始扫描」继续。相册很大时设个上限，避免长时间占用设备。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    NavigationLink {
                        ExcludedAlbumsView()
                    } label: {
                        Label("排除相簿", systemImage: "eye.slash")
                    }
                }

                Section("照片整理") {
                    NavigationLink {
                        DuplicateFinderView()
                    } label: {
                        Label("重复图片", systemImage: "square.on.square")
                    }
                    Text("按感知哈希找出视觉重复的照片，只列出分组与可省空间，不会删除照片。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
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
                }
            }
            .navigationTitle("设置")
        }
    }
}
