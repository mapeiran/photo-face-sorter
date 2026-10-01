import Foundation

/// 「扫描排除相簿」的持久化与判定。
///
/// 语义（三态）：
/// - 用户显式**排除**的相簿（`excludedKey`）→ 扫描跳过，且不参与按相簿命名；
/// - 用户显式**包含**的相簿（`includedKey`）→ 覆盖「自定义相簿默认跳过」，会被扫描；
/// - 其余：自定义相簿（`.albumRegular`）默认跳过（视为已归类），系统/同步相簿默认参与扫描。
///
/// 排除集合是纯数据，判定逻辑抽成纯函数便于单测。
enum AlbumExclusionStore {

    /// 显式排除的相簿 localIdentifier
    static let excludedKey = "excludedAlbumIDs"
    /// 显式包含（取消默认跳过）的自定义相簿 localIdentifier
    static let includedKey = "includedAlbumIDs"

    static func loadExcluded(from defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: excludedKey) ?? [])
    }

    static func saveExcluded(_ ids: Set<String>, to defaults: UserDefaults = .standard) {
        defaults.set(Array(ids).sorted(), forKey: excludedKey)
    }

    static func loadIncluded(from defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: includedKey) ?? [])
    }

    static func saveIncluded(_ ids: Set<String>, to defaults: UserDefaults = .standard) {
        defaults.set(Array(ids).sorted(), forKey: includedKey)
    }

    /// 这个相簿是否要从扫描中排除。
    /// - Parameters:
    ///   - isCustomAlbum: 是否为用户自建相簿（`.albumRegular`），它们默认跳过。
    ///   - excluded: 显式排除集合；
    ///   - included: 显式包含集合。
    static func isExcludedFromScan(albumLocalID: String,
                                   isCustomAlbum: Bool,
                                   excluded: Set<String>,
                                   included: Set<String>) -> Bool {
        if excluded.contains(albumLocalID) { return true }
        if included.contains(albumLocalID) { return false }
        return isCustomAlbum
    }
}
