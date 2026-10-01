import SwiftUI
import UIKit

/// 全屏看图 + 单张调整，左右滑动切换同一分组内的上一张/下一张。
///
/// 缩略图很小，放大后必然糊。点开后这里先给一张中等尺寸预览，
/// 再替换为**原图**（`PHImageManagerMaximumSize`，iCloud 照片会联网下载），
/// 双指缩放 / 双击放大查看细节。只展示整张照片，不做人脸裁剪。
///
/// 两种入口：
/// - 人物分组：带上 `[FaceSample]`，右上角菜单可以把当前这张
///   「移到其他人物 / 移出人物 / 标记非人物」；
/// - 系统相簿：只有照片标识，没有样本，不显示按人物调整的菜单。
struct PhotoViewerView: View {
    let assetIdentifiers: [String]
    /// 与 assetIdentifiers 一一对应的样本；来自相簿浏览时为 nil
    let samples: [FaceSample]?

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// 当前这张的原图
    @State private var fullImage: UIImage?
    /// 已加载的中等预览，左右滑动时先显示它，避免白屏
    @State private var previews: [String: UIImage] = [:]
    @State private var loadingOriginal = true
    @State private var showMove = false
    @State private var showDetail = false
    @State private var showAlbumPicker = false
    @State private var albumMessage: String?

    @State private var index: Int
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    /// 未缩放时左右拖动的跟手位移
    @State private var dragX: CGFloat = 0

    /// 人物分组入口：整组人脸样本
    init(samples: [FaceSample], initialIndex: Int) {
        self.assetIdentifiers = samples.map { $0.assetLocalIdentifier }
        self.samples = samples
        _index = State(initialValue: Self.clampedIndex(initialIndex, count: samples.count))
    }

    /// 系统相簿入口：只按照片标识浏览
    init(assetIdentifiers: [String], initialIndex: Int) {
        self.assetIdentifiers = assetIdentifiers
        self.samples = nil
        _index = State(initialValue: Self.clampedIndex(initialIndex, count: assetIdentifiers.count))
    }

    private static func clampedIndex(_ index: Int, count: Int) -> Int {
        min(max(index, 0), max(0, count - 1))
    }

    private var count: Int { assetIdentifiers.count }

    private var currentIdentifier: String? {
        assetIdentifiers.indices.contains(index) ? assetIdentifiers[index] : assetIdentifiers.first
    }

    /// 当前这张对应的样本（相簿入口为 nil，此时不显示按人物调整的菜单）
    private var currentSample: FaceSample? {
        guard let samples, samples.indices.contains(index) else { return nil }
        return samples[index]
    }

    private var displayedImage: UIImage? {
        guard let currentIdentifier else { return nil }
        return fullImage ?? previews[currentIdentifier]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle(count > 1 ? "\(index + 1) / \(count)" : "查看")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // 相簿入口也有这些操作：查看详情 / 去系统「照片」App 打开
                        Button { showDetail = true } label: {
                            Label("查看详情", systemImage: "info.circle")
                        }
                        Button {
                            PhotoLibraryService.openSystemPhotosApp()
                        } label: {
                            Label("在系统相册中打开", systemImage: "photo.on.rectangle")
                        }
                        Button { showAlbumPicker = true } label: {
                            Label("移到系统相簿…", systemImage: "rectangle.stack.badge.minus")
                        }
                        if currentSample != nil {
                            Divider()
                            Button { showMove = true } label: {
                                Label("移到其他人物…", systemImage: "arrow.triangle.branch")
                            }
                            Button {
                                if let currentSample { model.moveSamples([currentSample], to: nil) }
                                dismiss()
                            } label: {
                                Label("移出人物", systemImage: "person.badge.minus")
                            }
                            Button(role: .destructive) {
                                if let currentSample { model.ignoreSamples([currentSample]) }
                                dismiss()
                            } label: {
                                Label("标记非人物", systemImage: "eye.slash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task(id: currentIdentifier) {
            if let currentIdentifier { await load(currentIdentifier) }
        }
        .onChange(of: index) { _, _ in
            fullImage = nil
            loadingOriginal = true
        }
        .sheet(isPresented: $showMove) {
            PersonPickerView(title: "移动到", people: model.people) { target in
                if let currentSample { model.moveSamples([currentSample], to: target) }
                showMove = false
                dismiss()
            }
        }
        .sheet(isPresented: $showDetail) {
            if let currentIdentifier {
                PhotoDetailView(assetLocalIdentifier: currentIdentifier)
            }
        }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPickerView(title: "移到系统相簿") { albumName in
                moveCurrent(to: albumName)
            }
        }
        .alert("完成",
               isPresented: Binding(get: { albumMessage != nil },
                                    set: { if !$0 { albumMessage = nil } })) {
            Button("好", role: .cancel) { albumMessage = nil }
        } message: {
            Text(albumMessage ?? "")
        }
    }

    /// 把当前这张照片移到选定的系统相簿
    private func moveCurrent(to albumName: String) {
        guard let currentIdentifier else { return }
        Task {
            albumMessage = await model.moveAssetsToAlbum([currentIdentifier], albumName: albumName)
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
                    // 双击放大；单击退出（单击会先等双击判定失败，属正常行为）
                    .onTapGesture(count: 2) { toggleZoom() }
                    .onTapGesture { dismiss() }
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

            Text("\(index + 1) / \(count)")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.85))

            Button { go(to: index + 1) } label: {
                Image(systemName: "chevron.right").font(.title3)
            }
            .disabled(index >= count - 1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 20)
    }

    // MARK: - 切换

    private func go(to newIndex: Int) {
        guard assetIdentifiers.indices.contains(newIndex), newIndex != index else {
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

    private func load(_ localIdentifier: String) async {
        // 1) 先来一张中等尺寸的预览（本地有缓存时几乎瞬时），避免白屏
        if previews[localIdentifier] == nil,
           let preview = await ThumbnailCache.shared.preview(localIdentifier: localIdentifier,
                                                             maxSide: 1600),
           currentIdentifier == localIdentifier {
            cache(preview, for: localIdentifier)
        }
        // 2) 再换原图；失败也结束「加载中」，不要把用户困在转圈里
        let original = await ThumbnailCache.shared.original(localIdentifier: localIdentifier)
        guard currentIdentifier == localIdentifier else { return }
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
