import SwiftUI
import UIKit

/// 全屏看图。
///
/// 人脸网格里的缩略图只有 80pt，放大后必然糊。点开后这里先给一张中等尺寸预览，
/// 再替换为**原图**（`PHImageManagerMaximumSize`，iCloud 照片会联网下载），
/// 并用双指缩放 / 双击放大查看细节。带人脸框时还能一键切到「人脸特写」。
struct PhotoViewerView: View {
    let localIdentifier: String
    /// 人脸框（Vision 归一化坐标，左下原点）。有值时提供「人脸特写」。
    var boundingBox: CGRect? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var loadingOriginal = true
    @State private var mode: Mode = .original

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private enum Mode: String, CaseIterable {
        case original = "原图"
        case face = "人脸特写"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("查看")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                if boundingBox != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Picker("显示范围", selection: $mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                }
            }
        }
        .task(id: localIdentifier) { await load() }
        .onChange(of: mode) { _, _ in resetZoom() }
    }

    /// 「人脸特写」用原图按人脸框裁出来 —— 比缩略图清晰得多
    private var displayed: UIImage? {
        guard let image else { return nil }
        guard mode == .face, let boundingBox else { return image }
        return ThumbnailCache.cropToFace(image, boundingBox: boundingBox) ?? image
    }

    @ViewBuilder
    private var content: some View {
        if let displayed {
            GeometryReader { geo in
                Image(uiImage: displayed)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnifyGesture)
                    .simultaneousGesture(dragGesture)
                    .onTapGesture(count: 2) { toggleZoom() }
            }
            .overlay(alignment: .bottom) {
                if loadingOriginal {
                    Label("正在加载原图…", systemImage: "arrow.down.circle")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundColor(.white)
                        .padding(.bottom, 24)
                } else {
                    Text("双指缩放 · 双击放大")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 24)
                }
            }
        } else {
            ProgressView("正在加载…")
                .tint(.white)
                .foregroundColor(.white)
        }
    }

    // MARK: - 手势

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(baseScale * value, 1), 8)
            }
            .onEnded { _ in
                baseScale = scale
                if scale <= 1 { resetZoom() }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: baseOffset.width + value.translation.width,
                                height: baseOffset.height + value.translation.height)
            }
            .onEnded { _ in baseOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if scale > 1 {
                resetZoom()
            } else {
                scale = 2.5
                baseScale = 2.5
            }
        }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = 1
            baseScale = 1
            offset = .zero
            baseOffset = .zero
        }
    }

    // MARK: - 加载

    private func load() async {
        // 1) 先来一张中等尺寸的预览（本地有缓存时几乎瞬时），避免白屏
        if let preview = await ThumbnailCache.shared.preview(localIdentifier: localIdentifier,
                                                             maxSide: 1600) {
            image = preview
        }
        // 2) 再换原图；失败也结束「加载中」，不要把用户困在转圈里
        if let original = await ThumbnailCache.shared.original(localIdentifier: localIdentifier) {
            image = original
        }
        loadingOriginal = false
    }
}
