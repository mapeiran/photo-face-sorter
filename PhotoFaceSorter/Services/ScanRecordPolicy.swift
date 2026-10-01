import Foundation

/// 扫描记录的写入策略。
///
/// 关键不变量：**只有真正取到图片时才能写扫描记录**。
/// 否则 iCloud 尚未下载、或读取失败的照片会被记成「已扫描、0 张人脸」，
/// 而 `modificationDate` 不会因此改变，增量扫描再也不会把它们挑出来 ——
/// 这些人脸就永久消失了，且完全没有报错。
enum ScanRecordPolicy {

    /// - Parameter imageAvailable: 是否成功取到了可分析的图片。
    /// - Returns: 需要写入的记录；返回 nil 表示本次不写，留待下次扫描重试。
    static func record(assetLocalIdentifier: String,
                       modificationDate: Date?,
                       imageAvailable: Bool,
                       faceCount: Int,
                       scannedAt: Date = Date()) -> AssetRecord? {
        guard imageAvailable else { return nil }
        return AssetRecord(assetLocalIdentifier: assetLocalIdentifier,
                           scannedAt: scannedAt,
                           faceCount: faceCount,
                           modificationDate: modificationDate)
    }
}
