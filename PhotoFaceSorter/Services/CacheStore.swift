import Foundation

/// 本地缓存/持久化（JSON 文件，卸载 App 自动清除）
final class CacheStore {
    private let root: URL
    private let writeQueue = DispatchQueue(label: "PhotoFaceSorter.cache.write")
    private var samplesCache: [FaceSample]?

    init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("PhotoFaceSorter", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // 旧版样本格式（[Float]）体积巨大且会拖慢解码，v2 起改为二进制；
        // v3 起一并清理已扫描标记（避免旧标记导致「扫描秒结束」）
        let version = UserDefaults.standard.integer(forKey: "cacheSchemaVersion")
        if version < 3 {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("samples.json"))
            try? FileManager.default.removeItem(at: root.appendingPathComponent("people.json"))
            try? FileManager.default.removeItem(at: root.appendingPathComponent("records.json"))
            UserDefaults.standard.set(3, forKey: "cacheSchemaVersion")
        }
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

    /// 人脸样本（内存缓存，写入异步，避免主线程阻塞）
    var samples: [FaceSample] {
        get {
            if let samplesCache { return samplesCache }
            let value = read([FaceSample].self, "samples.json") ?? []
            samplesCache = value
            return value
        }
        set {
            samplesCache = newValue
            let value = newValue
            writeQueue.async { [weak self] in self?.write(value, "samples.json") }
        }
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
        samplesCache = nil
        try? FileManager.default.removeItem(at: url("samples.json"))
        try? FileManager.default.removeItem(at: url("people.json"))
        try? FileManager.default.removeItem(at: url("records.json"))
    }

    func clearLogs() {
        try? FileManager.default.removeItem(at: url("logs.json"))
    }
}
