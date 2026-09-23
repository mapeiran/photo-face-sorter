import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

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
                    Toggle("仅充电时后台扫描", isOn: $model.chargeOnlyBackground)
                        .disabled(!model.autoScanEnabled)
                    Text("后台扫描受 iOS 系统调度限制，不能保证实时。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("缓存管理") {
                    Button("清空人脸识别缓存") { model.clearFaceCache() }
                    Button("清空执行日志") { model.clearLogs() }
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
