import SwiftUI
import UIKit

/// 全屏看图 + 单张调整。
///
/// 缩略图很小，放大后必然糊。点开后这里先给一张中等尺寸预览，
/// 再替换为**原图**（`PHImageManagerMaximumSize`，iCloud 照片会联网下载），
/// 并用双指缩放 / 双击放大查看细节。只展示整张照片，不做人脸裁剪。
/// 右上角菜单可以顺带把这一张「移到其他人物 / 移出人物 / 标记非人物」。
struct PhotoViewerView: View {
    let sample: FaceSample

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var loadingOriginal = true
    @State private var showMove = false

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showMove = true } label: {
                            Label("移到其他人物…", systemImage: "arrow.triangle.branch")
                        }
                        Button {
                            model.moveSamples([sample], to: nil)
                            dismiss()
                        } label: {
                            Label("移出人物", systemImage: "person.badge.minus")
                        }
                        Button(role: .destructive) {
                            model.ignoreSamples([sample])
                            dismiss()
                        } label: {
                            Label("标记非人物", systemImage: "eye.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task(id: sample.assetLocalIdentifier) { await load() }
        .sheet(isPresented: $showMove) {
            PersonPickerView(title: "移动到", people: model.people) { target in
                model.moveSamples([sample], to: target)
                showMove = false
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            GeometryReader { geo in
                Image(uiImage: image)
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
        let localIdentifier = sample.assetLocalIdentifier
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
