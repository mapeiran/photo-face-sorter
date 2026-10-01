import Foundation

/// 把感知哈希聚成重复分组。
///
/// 用「代表元」分组而不是并查集：每张照片只跟每个分组的第一张比距离，
/// 避免 A≈B、B≈C 但 A≉C 的链式传递把一大批不相似的照片连成一组。
enum DuplicateGroupingPolicy {

    /// - Parameters:
    ///   - hashes: 每张照片的 (标识, 64 位哈希)，顺序一般按创建时间。
    ///   - threshold: 汉明距离不超过它的算重复。
    /// - Returns: 成员数 > 1 的分组（保持输入顺序）。
    static func groups(hashes: [(id: String, hash: UInt64)], threshold: Int) -> [[String]] {
        var representatives: [(hash: UInt64, members: [String])] = []
        for item in hashes {
            if let index = representatives.firstIndex(where: {
                PerceptualHash.hammingDistance($0.hash, item.hash) <= threshold
            }) {
                representatives[index].members.append(item.id)
            } else {
                representatives.append((item.hash, [item.id]))
            }
        }
        return representatives.map(\.members).filter { $0.count > 1 }
    }
}
