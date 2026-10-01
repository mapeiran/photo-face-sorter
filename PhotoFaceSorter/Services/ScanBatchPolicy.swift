import Foundation

/// 单次扫描的照片数量上限。
///
/// 为什么要有上限：几万张的大相册如果一次性扫完，设备会长时间满负荷、
/// 界面长时间停在「扫描中」，用户很容易以为卡死并强行杀掉 App。
/// 把一次扫描拆成若干批后，每批扫完就落盘并回到「已完成」，
/// 用户（或后台任务）再点一次即可继续，进度一点都不会丢。
///
/// 约定：设置值 **小于等于 0** 表示不限制（`unlimited`）。
enum ScanBatchPolicy {

    /// 设置里的「不限制」取值，也是默认值。
    static let unlimited = 0

    /// 设置项在 `UserDefaults` 里的键。
    /// `AppModel` 用 `@AppStorage` 绑定同一个键，两处必须一致。
    static let defaultsKey = "maxPhotosPerScan"

    /// 把设置值换算成 `ScanCoordinator.start(limit:)` 需要的上限。
    ///
    /// - Parameters:
    ///   - setting: 用户设置；`<= 0` 表示不限制。
    ///   - cap: 额外的硬上限（例如后台刷新单次只处理 60 张以省电）。不限制时以它为准。
    /// - Returns: 严格大于 0 的上限；不限制时返回 `Int.max`。
    ///   绝不能返回 0 或负数 —— `Array.prefix(_:)` 收到负数会直接崩溃。
    static func limit(setting: Int, cap: Int? = nil) -> Int {
        let effectiveCap = (cap ?? 0) > 0 ? cap : nil
        guard setting > 0 else { return effectiveCap ?? Int.max }
        guard let effectiveCap else { return setting }
        return min(setting, effectiveCap)
    }

    /// 读取当前设置换算出的上限（给拿不到 `AppModel` 的调用方使用）。
    static func configuredLimit(cap: Int? = nil) -> Int {
        limit(setting: UserDefaults.standard.integer(forKey: defaultsKey), cap: cap)
    }

    /// 按上限把待扫描列表切成「本次要扫的」和「剩下的」。
    ///
    /// `remaining` 用来在界面上提示「还有多少张，再点一次继续」，
    /// 否则用户看到进度 100% 会以为相册已经扫完。
    static func batch<T>(_ pending: [T], limit: Int) -> (batch: [T], remaining: Int) {
        let maxLength = max(0, min(limit, pending.count))
        let batch = Array(pending.prefix(maxLength))
        return (batch, pending.count - batch.count)
    }
}
