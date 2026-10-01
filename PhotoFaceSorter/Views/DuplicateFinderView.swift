import SwiftUI

/// 重复图片检测的状态（只读展示，不删除照片）。
@MainActor
final class DuplicateScanModel: ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var analyzed = 0
    @Published private(set) var total = 0
    @Published private(set) var skipped = 0
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var hasRun = false

    private var task: Task<Void, Never>?

    var summary: String {
        if isScanning {
            return total > 0 ? "正在分析 \(analyzed)/\(total)…" : "正在读取照片库…"
        }
        guard hasRun else { return "" }
        guard !groups.isEmpty else { return "没有发现重复照片" }
        let count = groups.reduce(0) { $0 + $1.assets.count }
        let wasted = groups.reduce(Int64(0)) { $0 + $1.wastedBytes }
        return "\(groups.count) 组 · 共 \(count) 张 · 可省约 \(Self.sizeText(wasted))"
    }

    func start() {
        guard !isScanning else { return }
        isScanning = true
        hasRun = true
        analyzed = 0
        total = 0
        skipped = 0
        groups = []
        task = Task {
            let result = await DuplicateDetector.detect { [weak self] done, total in
                self?.analyzed = done
                self?.total = total
            }
            guard !Task.isCancelled else {
                isScanning = false
                return
            }
            groups = result.groups.sorted { $0.wastedBytes > $1.wastedBytes }
            skipped = result.skipped
            analyzed = result.analyzed
            total = result.total
            isScanning = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isScanning = false
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// 重复图片：列出视觉重复的分组与可省空间，**不删除**任何照片。
struct DuplicateFinderView: View {
    @StateObject private var model = DuplicateScanModel()

    var body: some View {
        List {
            Section {
                if model.isScanning {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: model.total > 0
                                     ? Double(model.analyzed) / Double(model.total)
                                     : 0)
                        Text(model.summary).font(.footnote).foregroundColor(.secondary)
                    }
                    Button("停止", role: .destructive) { model.cancel() }
                } else {
                    Button {
                        model.start()
                    } label: {
                        Label(model.hasRun ? "重新查找" : "开始查找重复照片",
                              systemImage: "square.on.square")
                    }
                }
            } footer: {
                Text("按感知哈希找出视觉重复（重复导入、连拍、缩放/压缩后的同一张）。"
                     + "只列出结果，不会删除任何照片；iCloud 未下载的照片会跳过。")
            }

            if model.hasRun && !model.isScanning {
                Section {
                    Text(model.summary).font(.subheadline)
                    if model.skipped > 0 {
                        Text("有 \(model.skipped) 张因未下载原图（iCloud）被跳过。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(model.groups) { group in
                    DuplicateGroupRow(group: group)
                }
            }
        }
        .navigationTitle("重复图片")
        .onDisappear { model.cancel() }
    }
}

private struct DuplicateGroupRow: View {
    let group: DuplicateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(group.assets.count) 张").font(.subheadline).bold()
                Spacer()
                Text("可省约 \(DuplicateScanModel.sizeText(group.wastedBytes))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(group.assets) { asset in
                        VStack(spacing: 4) {
                            AssetThumbnailView(localIdentifier: asset.id,
                                               contentMode: .fill,
                                               side: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(asset.dimensionsText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(asset.sizeText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
