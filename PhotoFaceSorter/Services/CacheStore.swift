import Foundation

/// 本地缓存/持久化（卸载 App 自动清除）
///
/// 存储分工：
/// - 人脸样本 → `samples.bin`（二进制，见 `SampleBinaryCoding`）。特征向量走 JSON 必须 base64，
///   体积膨胀约 33%，且几万条样本的编解码代价很高。
/// - 其余（人物 / 规则 / 日志 / 扫描记录）→ JSON，体积小、可读性好，无需二进制化。
///
/// 会在主线程与后台扫描线程上同时被访问，因此用锁保护可变状态。
/// （`@unchecked` 的依据：所有可变状态都由 `lock`/`loadLock`/`writeQueue` 串行化。）
final class CacheStore: @unchecked Sendable {

    private static let samplesFile = "samples.bin"
    private static let legacySamplesFile = "samples.json"
    private static let recordsFile = "records.bin"
    private static let legacyRecordsFile = "records.json"
    private static let metaFile = "meta.json"

    private let root: URL
    private let writeQueue = DispatchQueue(label: "PhotoFaceSorter.cache.write")
    private let lock = NSLock()
    /// 串行化「首次从磁盘加载」，避免多线程同时触发迁移而重复写文件
    private let loadLock = NSLock()

    private var samplesCache: [FaceSample]?
    /// 扫描记录同样缓存一份：写入改为异步合并之后，若仍从磁盘读，
    /// 紧接其后的下一次扫描可能会读到尚未落盘的旧记录，从而重复扫描。
    private var recordsCache: [String: AssetRecord]?
    private var metaCache: CacheMeta?

    // 写入合并：样本与扫描记录体积很大，扫描过程中会被高频整体替换。
    // 若每次都排一次全量编码，队列会迅速堆积并产生 O(n²) 的重复编码。
    // 这里只保留「最新值」，由单个在途的写入循环取走。
    private var pendingSamples: [FaceSample]?
    private var samplesWriteScheduled = false
    private var pendingRecords: [String: AssetRecord]?
    private var recordsWriteScheduled = false

    /// - Parameter root: 仅供测试注入临时目录；正式运行传 nil 使用沙盒 Documents。
    init(root overrideRoot: URL? = nil) {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = overrideRoot ?? base.appendingPathComponent("PhotoFaceSorter", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // v3 起清理旧版样本格式（[Float] 体积巨大且会拖慢解码）与已扫描标记
        // （避免旧标记导致「扫描秒结束」）。
        // 注意：v3 → 二进制样本是**无损迁移**，不走这条破坏性分支，见 `readSamplesFromDisk`。
        let version = UserDefaults.standard.integer(forKey: "cacheSchemaVersion")
        if version < 3 {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(Self.samplesFile))
            try? FileManager.default.removeItem(at: root.appendingPathComponent(Self.legacySamplesFile))
            try? FileManager.default.removeItem(at: root.appendingPathComponent(Self.recordsFile))
            try? FileManager.default.removeItem(at: root.appendingPathComponent(Self.legacyRecordsFile))
            try? FileManager.default.removeItem(at: root.appendingPathComponent("people.json"))
            UserDefaults.standard.set(3, forKey: "cacheSchemaVersion")
        }
    }

    private func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    /// 把损坏文件改名保留为 `<name>.corrupt`。
    /// 否则解码失败会被静默当成空数据，随后又被空数据覆盖，用户数据就永久丢了。
    @discardableResult
    private func quarantine(_ name: String, reason: String) -> Bool {
        let fileURL = url(name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        let quarantineURL = url("\(name).corrupt")
        try? FileManager.default.removeItem(at: quarantineURL)
        try? FileManager.default.moveItem(at: fileURL, to: quarantineURL)
        NSLog("[CacheStore] %@，已保留为 %@.corrupt", reason, name)
        return true
    }

    /// 读取 JSON 缓存。
    ///
    /// 注意：Swift 合成的 `Decodable` 不会为缺失的键使用属性默认值，
    /// 所以给模型新增非可选字段会让旧缓存整个解码失败 —— 这条路径必须保留证据。
    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            quarantine(name, reason: "解码 \(name) 失败：\(error)")
            return nil
        }
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    // MARK: - 人脸样本（二进制）

    var samples: [FaceSample] {
        get { loadSamples() }
        set {
            lock.lock()
            samplesCache = newValue
            pendingSamples = newValue
            let shouldSchedule = !samplesWriteScheduled
            samplesWriteScheduled = true
            lock.unlock()

            guard shouldSchedule else { return }
            writeQueue.async { [weak self] in self?.flushSamples() }
        }
    }

    private func loadSamples() -> [FaceSample] {
        lock.lock()
        if let samplesCache {
            lock.unlock()
            return samplesCache
        }
        lock.unlock()

        loadLock.lock()
        defer { loadLock.unlock() }

        // 双重检查：可能已被另一个线程加载完成
        lock.lock()
        if let samplesCache {
            lock.unlock()
            return samplesCache
        }
        lock.unlock()

        let value = readSamplesFromDisk()

        lock.lock()
        samplesCache = value
        lock.unlock()
        return value
    }

    private func readSamplesFromDisk() -> [FaceSample] {
        if let data = try? Data(contentsOf: url(Self.samplesFile)) {
            if let decoded = SampleBinaryCoding.decode(data) {
                return decoded
            }
            quarantine(Self.samplesFile, reason: "二进制样本解码失败")
            return []
        }

        // 旧版本写的是 JSON。只在二进制文件不存在时做一次无损迁移；
        // 写成功才删除旧文件，避免写盘失败时丢数据。
        guard let legacy = read([FaceSample].self, Self.legacySamplesFile) else { return [] }
        if writeSamples(legacy) {
            try? FileManager.default.removeItem(at: url(Self.legacySamplesFile))
        }
        return legacy
    }

    @discardableResult
    private func writeSamples(_ samples: [FaceSample]) -> Bool {
        let data = SampleBinaryCoding.encode(samples)
        do {
            try data.write(to: url(Self.samplesFile), options: .atomic)
            return true
        } catch {
            NSLog("[CacheStore] 写入 %@ 失败：%@", Self.samplesFile, String(describing: error))
            return false
        }
    }

    // MARK: - 其余 JSON 缓存

    var people: [Person] {
        get { read([Person].self, "people.json") ?? [] }
        set { write(newValue, "people.json") }
    }

    var records: [String: AssetRecord] {
        get { loadRecords() }
        set {
            lock.lock()
            recordsCache = newValue
            pendingRecords = newValue
            let shouldSchedule = !recordsWriteScheduled
            recordsWriteScheduled = true
            lock.unlock()

            guard shouldSchedule else { return }
            writeQueue.async { [weak self] in self?.flushRecords() }
        }
    }

    private func loadRecords() -> [String: AssetRecord] {
        lock.lock()
        if let recordsCache {
            lock.unlock()
            return recordsCache
        }
        lock.unlock()

        loadLock.lock()
        defer { loadLock.unlock() }

        // 双重检查：可能已被另一个线程加载完成
        lock.lock()
        if let recordsCache {
            lock.unlock()
            return recordsCache
        }
        lock.unlock()

        let value = readRecordsFromDisk()

        lock.lock()
        recordsCache = value
        lock.unlock()
        return value
    }

    private func readRecordsFromDisk() -> [String: AssetRecord] {
        if let data = try? Data(contentsOf: url(Self.recordsFile)) {
            if let decoded = AssetRecordBinaryCoding.decode(data) {
                return Dictionary(decoded.map { ($0.assetLocalIdentifier, $0) },
                                  uniquingKeysWith: { _, latest in latest })
            }
            quarantine(Self.recordsFile, reason: "二进制扫描记录解码失败")
            return [:]
        }

        // 旧版本写的是 JSON。写成功才删除旧文件，避免写盘失败时丢数据。
        guard let legacy = read([String: AssetRecord].self, Self.legacyRecordsFile) else { return [:] }
        if writeRecords(legacy) {
            try? FileManager.default.removeItem(at: url(Self.legacyRecordsFile))
        }
        return legacy
    }

    @discardableResult
    private func writeRecords(_ records: [String: AssetRecord]) -> Bool {
        let data = AssetRecordBinaryCoding.encode(Array(records.values))
        do {
            try data.write(to: url(Self.recordsFile), options: .atomic)
            return true
        } catch {
            NSLog("[CacheStore] 写入 %@ 失败：%@", Self.recordsFile, String(describing: error))
            return false
        }
    }

    var rules: [ClassifyRule] {
        get { read([ClassifyRule].self, "rules.json") ?? [] }
        set { write(newValue, "rules.json") }
    }

    // MARK: - 元信息

    /// 缓存元信息（当前只记录生成样本人脸所用的特征提取方式）
    var meta: CacheMeta {
        get {
            lock.lock()
            if let metaCache {
                lock.unlock()
                return metaCache
            }
            lock.unlock()

            let value = read(CacheMeta.self, Self.metaFile) ?? CacheMeta()

            lock.lock()
            metaCache = value
            lock.unlock()
            return value
        }
        set {
            lock.lock()
            metaCache = newValue
            lock.unlock()
            write(newValue, Self.metaFile)
        }
    }

    /// 生成已缓存样本人脸所用的特征提取方式标识
    var embeddingSignature: String? {
        get { meta.embeddingSignature }
        set {
            var updated = meta
            updated.embeddingSignature = newValue
            meta = updated
        }
    }

    var logs: [ExecutionLog] {
        get { read([ExecutionLog].self, "logs.json") ?? [] }
        set { write(newValue, "logs.json") }
    }

    // MARK: - 清理

    /// 清空人脸识别缓存（样本/人物/已处理标记）
    func clearFaceCache() {
        lock.lock()
        samplesCache = nil
        recordsCache = nil
        metaCache = nil
        pendingSamples = nil
        pendingRecords = nil
        lock.unlock()

        // 先等在途写入结束再删文件，否则刚清空就可能被写回
        writeQueue.sync {}

        try? FileManager.default.removeItem(at: url(Self.samplesFile))
        try? FileManager.default.removeItem(at: url(Self.legacySamplesFile))
        try? FileManager.default.removeItem(at: url(Self.recordsFile))
        try? FileManager.default.removeItem(at: url(Self.legacyRecordsFile))
        try? FileManager.default.removeItem(at: url(Self.metaFile))
        try? FileManager.default.removeItem(at: url("people.json"))
    }

    func clearLogs() {
        writeQueue.sync {}
        try? FileManager.default.removeItem(at: url("logs.json"))
    }

    /// 等待尚未落盘的合并写入全部完成。
    /// 必须在 App 进入后台、以及后台任务上报完成之前调用，否则可能丢数据。
    func flushPendingWrites() {
        writeQueue.sync {}
    }

    // MARK: - 合并写入

    private func flushSamples() {
        while true {
            lock.lock()
            guard let value = pendingSamples else {
                samplesWriteScheduled = false
                lock.unlock()
                return
            }
            pendingSamples = nil
            lock.unlock()
            writeSamples(value)
        }
    }

    private func flushRecords() {
        while true {
            lock.lock()
            guard let value = pendingRecords else {
                recordsWriteScheduled = false
                lock.unlock()
                return
            }
            pendingRecords = nil
            lock.unlock()
            writeRecords(value)
        }
    }
}
