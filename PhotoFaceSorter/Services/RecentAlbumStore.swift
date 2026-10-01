import Foundation

/// 「最近移动到的系统相簿」：相簿选择器顶部给个快捷入口。
/// 只记名字，展示时会过滤掉已经不存在（被删/改名）的相簿。
enum RecentAlbumStore {

    static let defaultsKey = "recentAlbumNames"
    static let maxCount = 5

    static func load(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: defaultsKey) ?? []
    }

    /// 记录一次「移动到这本相簿」，返回更新后的列表（最新在前、去重、最多 `maxCount` 个）。
    @discardableResult
    static func record(_ name: String, to defaults: UserDefaults = .standard) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return load(from: defaults) }
        var list = load(from: defaults)
        list.removeAll { $0 == trimmed }
        list.insert(trimmed, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        defaults.set(list, forKey: defaultsKey)
        return list
    }

    /// 过滤掉已经不存在（被删或改名）的相簿。
    static func existing(_ names: [String], in titles: Set<String>) -> [String] {
        names.filter { titles.contains($0) }
    }
}
