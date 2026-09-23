import Foundation

/// 本地缓存/持久化（JSON 文件，卸载 App 自动清除）
final class CacheStore {
    private let root: URL

    init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("PhotoFaceSorter", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    var people: [Person] {
        get { read([Person].self, "people.json") ?? [] }
        set { write(newValue, "people.json") }
    }

    var samples: [FaceSample] {
        get { read([FaceSample].self, "samples.json") ?? [] }
        set { write(newValue, "samples.json") }
    }

    var records: [String: AssetRecord] {
        get { read([String: AssetRecord].self, "records.json") ?? [:] }
        set { write(newValue, "records.json") }
    }

    var rules: [ClassifyRule] {
        get { read([ClassifyRule].self, "rules.json") ?? [] }
        set { write(newValue, "rules.json") }
    }

    var logs: [ExecutionLog] {
        get { read([ExecutionLog].self, "logs.json") ?? [] }
        set { write(newValue, "logs.json") }
    }

    /// 清空人脸识别缓存（样本/人物/已处理标记）
    func clearFaceCache() {
        try? FileManager.default.removeItem(at: url("samples.json"))
        try? FileManager.default.removeItem(at: url("people.json"))
        try? FileManager.default.removeItem(at: url("records.json"))
    }

    func clearLogs() {
        try? FileManager.default.removeItem(at: url("logs.json"))
    }
}
