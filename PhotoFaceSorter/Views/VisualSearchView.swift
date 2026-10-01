import SwiftUI

/// `.sheet(item:)` 用：以图搜图的目标照片标识。
struct VisualSearchTarget: Identifiable {
    let id: String
}

/// 网络识别人像（以图搜图）：把当前这一张照片上传到 Bing Visual Search，
/// 展示识别到的标签、包含它的网页与相似图片。
struct VisualSearchView: View {
    let assetLocalIdentifier: String

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isLoading = true
    @State private var result: VisualSearchResult?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在上传并搜索…").foregroundColor(.secondary)
                        Text("只上传当前这一张照片").font(.caption2).foregroundColor(.secondary)
                    }
                } else if let errorMessage {
                    ContentUnavailableView("识别失败",
                                           systemImage: "wifi.exclamationmark",
                                           description: Text(errorMessage))
                } else if let result {
                    List {
                        if !result.tags.isEmpty {
                            Section("可能的人 / 物") {
                                ForEach(result.tags, id: \.self) { tag in
                                    Text(tag).font(.headline)
                                }
                            }
                        }
                        if !result.pages.isEmpty {
                            Section("包含这张图的网页") {
                                ForEach(result.pages) { page in
                                    Button { open(page.url) } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(page.name).font(.subheadline).foregroundColor(.primary)
                                            if let host = page.host {
                                                Text(host).font(.caption2).foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if !result.similarImages.isEmpty {
                            Section("相似图片") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 8) {
                                        ForEach(result.similarImages) { image in
                                            similarThumbnail(image)
                                        }
                                    }
                                }
                            }
                        }
                        Section {
                            Text("结果来自 Bing Visual Search；本次只上传了当前这一张照片。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("网络识别人像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await run() }
        }
    }

    @ViewBuilder
    private func similarThumbnail(_ image: VisualSearchImage) -> some View {
        if let url = URL(string: image.thumbnailURL ?? image.contentURL ?? "") {
            AsyncImage(url: url) { phase in
                if let loaded = phase.image {
                    loaded.resizable().scaledToFill()
                } else {
                    Color(.secondarySystemBackground)
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func run() async {
        guard model.visualSearchEnabled else {
            errorMessage = "网络识别人像未启用。请到「设置 → 网络识别人像」填写密钥并打开开关。"
            isLoading = false
            return
        }
        let key = model.visualSearchAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "还没有填写 Bing Visual Search 密钥（设置 → 网络识别人像）。"
            isLoading = false
            return
        }
        guard let data = await PhotoLibraryService.shared.uploadImageData(for: assetLocalIdentifier) else {
            errorMessage = "读取这张照片失败（可能尚未从 iCloud 下载）。"
            isLoading = false
            return
        }
        do {
            let found = try await VisualSearchService.search(imageData: data, apiKey: key)
            if found.isEmpty {
                errorMessage = "没有搜到结果，换一张更清晰的正面照可能更好。"
            } else {
                result = found
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        openURL(url)
    }
}
