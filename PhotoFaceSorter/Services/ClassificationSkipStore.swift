import Foundation

/// 「归类审核」里被**跳过**的分组（人物 ID）：
/// 跳过后不再展示，直到用户手动恢复。持久化在 UserDefaults。
enum ClassificationSkipStore {

    static let defaultsKey = "skippedClassificationPersonIDs"

    static func load(from defaults: UserDefaults = .standard) -> Set<UUID> {
        Set((defaults.stringArray(forKey: defaultsKey) ?? []).compactMap { UUID(uuidString: $0) })
    }

    static func save(_ ids: Set<UUID>, to defaults: UserDefaults = .standard) {
        defaults.set(ids.map { $0.uuidString }.sorted(), forKey: defaultsKey)
    }
}
