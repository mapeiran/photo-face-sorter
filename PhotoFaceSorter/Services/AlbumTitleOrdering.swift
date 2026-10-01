import Foundation

/// 相簿名的排序规则。
///
/// 用 `localizedStandardCompare`：中文按本地化顺序、名字里的数字按数值大小
/// （「相簿 2」排在「相簿 10」前），和人物页的排序规则保持一致。
enum AlbumTitleOrdering {

    static func isOrderedBefore(_ lhs: String?, _ rhs: String?) -> Bool {
        (lhs ?? "").localizedStandardCompare(rhs ?? "") == .orderedAscending
    }
}
