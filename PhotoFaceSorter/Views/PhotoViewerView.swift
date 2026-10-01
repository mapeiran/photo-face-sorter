import SwiftUI
import UIKit

/// 全屏看图 + 单张调整，左右滑动切换同一分组内的上一张/下一张。
///
/// 缩略图很小，放大后必然糊。点开后这里先给一张中等尺寸预览，
/// 再替换为**原图**（`PHImageManagerMaximumSize`，iCloud 照片会联网下载），
/// 双指缩放 / 双击放大查看细节。只展示整张照片，不做人脸裁剪。
/// 右上角菜单可以顺带把当前这张「移到其他人物 / 移出人物 / 标记非人物」。
struct PhotoViewerView: View {
    let samples: [FaceSample]
    let initialIndex: Int

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// 当前这张的原图
    @State private var fullImage: UIImage?
    /// 已加载的中等预览，左右滑动时先显示它，避免白屏
    @State private var previews: [String: UIImage] = [:]
    @State private var loadingOriginal = true
    @State private var showMove = false

    @State private var index: Int
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    /// 未缩放时左右拖动的跟手位移
    @State private var dragX: CGFloat = 0

    init(samples: [FaceSample], initialIndex: Int) {
        self.samples = samples
        self.initialIndex = initialIndex
        let clamped = min(max(initialIndex, 0), max(0, samples.count - 1))
        _index = State(initialValue: clamped)
    }

    private var current: FaceSample? {
        samples.indices.contains(index) ? samples[index] : samples.first
    }

    private var displayedImage: UIImage? {
        guard let current else { return nil }
        return fullImage ?? previews[current.assetLocalIdentifier]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle(samples.count > 1 ? "\(index + 1) / \(samples.count)" : "查看")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let current {
                        Menu {
                            Button { showMove = true } label: {
                                Label("移到其他人物…", systemImage: "arrow.triangle.branch")
                            }
                            Button {
                                model.moveSamples([current], to: nil)
                                dismiss()
                            } label: {
                                Label("移出人物", systemImage: "person.badge.minus")
                            }
                            Button(role: .destructive) {
                                model.ignoreSamples([current])
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
        }
        .task(id: current?.assetLocalIdentifier) {
            if let current { await load(current) }
        }
        .onChange(of: index) { _, _ in
            fullImage = nil
            loadingOriginal = true
        }
        .sheet(isPresented: $showMove) {
            PersonPickerView(title: "移动到", people: model.people) { target in
                if let current { model.moveSamples([current], to: target) }
                showMove = false
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let displayedImage {
            GeometryReader { geo in
                Image(uiImage: displayedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(x: offset.width + dragX, y: offset.height)
                    .gesture(magnifyGesture)
                    .simultaneousGesture(dragGesture)
                    .onTapGesture(count: 2) { toggleZoom() }
            }
            .overlay(alignment: .top) { statusOverlay }
            .overlay(alignment: .bottom) { navigationOverlay }
        } else {
            ProgressView("正在加载…")
                .tint(.white)
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if loadingOriginal {
            Label("正在加载原图…", systemImage: "arrow.down.circle")
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundColor(.white)
                .padding(.top, 8)
        }
    }

    private var navigationOverlay: some View {
        HStack(spacing: 24) {
            Button { go(to: index - 1) } label: {
                Image(systemName: "chevron.left").font(.title3)
            }
            .disabled(index <= 0)

            Text("\(index + 1) / \(samples.count)")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.85))

            Button { go(to: index + 1) } label: {
                Image(systemName: "chevron.right").font(.title3)
            }
            .disabled(index >= samples.count - 1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 20)
    }

    // MARK: - 切换

    private func go(to newIndex: Int) {
        guard samples.indices.contains(newIndex), newIndex != index else {
            withAnimation(.easeOut(duration: 0.2)) { dragX = 0 }
            return
        }
        resetZoom()
        index = newIndex
        dragX = 0
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

    /// 放大后拖动＝平移；未放大时左右滑＝上一张/下一张
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1 {
                    offset = CGSize(width: baseOffset.width + value.translation.width,
                                    height: baseOffset.height + value.translation.height)
                } else {
                    dragX = value.translation.width
                }
            }
            .onEnded { value in
                guard scale > 1 else {
                    let threshold: CGFloat = 60
                    if value.translation.width < -threshold {
                        go(to: index + 1)
                    } else if value.translation.width > threshold {
                        go(to: index - 1)
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { dragX = 0 }
                    }
                    return
                }
                baseOffset = offset
            }
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

    private func load(_ sample: FaceSample) async {
        let localIdentifier = sample.assetLocalIdentifier
        // 1) 先来一张中等尺寸的预览（本地有缓存时几乎瞬时），避免白屏
        if previews[localIdentifier] == nil,
           let preview = await ThumbnailCache.shared.preview(localIdentifier: localIdentifier,
                                                             maxSide: 1600),
           current?.assetLocalIdentifier == localIdentifier {
            cache(preview, for: localIdentifier)
        }
        // 2) 再换原图；失败也结束「加载中」，不要把用户困在转圈里
        let original = await ThumbnailCache.shared.original(localIdentifier: localIdentifier)
        guard current?.assetLocalIdentifier == localIdentifier else { return }
        if let original { fullImage = original }
        loadingOriginal = false
    }

    /// 预览最多留 12 张，避免左右滑很久时把原图/预览都堆在内存里
    private func cache(_ image: UIImage, for key: String) {
        if previews.count >= 12, let oldest = previews.keys.first {
            previews.removeValue(forKey: oldest)
        }
        previews[key] = image
    }
}
