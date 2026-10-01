# 相册人像归类（PhotoFaceSorter）

iPhone 相册辅助工具：**端侧**人脸识别 + 人脸聚类，按人物把照片自动归类到系统相簿。
图片与人脸特征**全程不上云**，所有识别都在设备本地完成。

配套文档：[产品需求文档.md](产品需求文档.md) · [产品原型页面清单.md](产品原型页面清单.md)

## 环境要求

- Xcode 16 或更高（工程使用 `objectVersion = 77` 与 `PBXFileSystemSynchronizedRootGroup`）
- iOS 17.0+
- 仅 iPhone（`TARGETED_DEVICE_FAMILY = 1`）

## 构建与测试

```bash
# 构建
xcodebuild build \
  -project PhotoFaceSorter.xcodeproj \
  -scheme PhotoFaceSorter \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# 单元测试
xcodebuild test \
  -project PhotoFaceSorter.xcodeproj \
  -scheme PhotoFaceSorter \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

代码风格：

```bash
swiftlint lint --strict
swiftformat PhotoFaceSorter PhotoFaceSorterTests
```

真机运行需要在 Xcode 里设置你自己的 `DEVELOPMENT_TEAM`（工程里刻意没有提交团队 ID）。

## 目录结构

```
PhotoFaceSorter/
├── App/          入口、AppDelegate（后台任务注册）、全局 AppModel
├── Models/       Person / FaceSample / AssetRecord / ClassifyRule / ExecutionLog
├── Services/     扫描、人脸检测与特征、聚类、规则引擎、缓存、相册访问
└── Views/        SwiftUI 页面（人物 / 扫描 / 规则 / 设置）
PhotoFaceSorterTests/   逻辑层单元测试
```

## 架构要点

- **共享单例对象**：`AppModel` / `ScanCoordinator` / `AutoScanManager` 由 `AppDelegate` 持有并在
  `didFinishLaunching` 中装配。原因是系统以后台方式拉起 App 执行刷新任务时窗口可能不出现，
  只有该回调一定会执行；`BGTaskScheduler.register` 也必须在此刻完成。
- **单一扫描协调器**：手动扫描与自动增量扫描共用同一个 `ScanCoordinator`，
  否则两者会各自快照扫描状态并互相覆盖。
- **线程模型**：重活（枚举相册、解码缓存、全量聚类、Vision 推理）都在后台线程；
  `CacheStore` 由锁保护并标注 `@unchecked Sendable`，逻辑层在
  `-strict-concurrency=complete` 下无告警。
- **持久化**：人脸样本存为二进制 `samples.bin`（`SampleBinaryCoding`），扫描记录存为
  `records.bin`（`AssetRecordBinaryCoding`），共用 `BinaryFormat` 的字节原语。
  样本若走 JSON，特征向量必须 base64，体积膨胀约 33%，实测二进制可降至 JSON 的约 69%；
  记录走 JSON 还会把 `assetLocalIdentifier` 在键和值里各存一遍。
  人物 / 规则 / 日志仍是 JSON（体积小、可读性好）。
  样本与记录的写入做了**合并**（只保留最新值 + 单个在途写入循环），
  落盘间隔为每 100 张（`ScanCoordinator.flushInterval`）—— 间隔太小会让大相册扫描时
  反复整份编码；落盘是幂等的，崩溃丢掉的进度重扫即可。
  进入后台前会 `flushPendingWrites()`。
  旧版本的 `samples.json` / `records.json` 会**无损迁移**为二进制（写成功才删旧文件）。
  解码失败的文件会被改名保留为 `<name>.corrupt`，不会被静默丢弃。
- **二进制布局有黄金样本测试**：格式一旦变动会导致老用户的缓存读不出来，
  因此 `SampleBinaryCodingTests` / `AssetRecordBinaryCodingTests` 里固定了逐字节的期望值。
- **手工修正优先**：`FaceSample.assignmentIsManual` 标记用户手动指定的归属
  （合并、拆分、移出、标记非人物），重聚类时这些样本完全不被改动。
- **不隐式删除用户的分组**：把人脸移出某个分组**不会**删掉该分组本身。
  空分组只有在名字是自动生成（「人物 N」）时才会被重聚类清理；
  用户命名过的空分组会保留（可在人物页多选删除）。
  注意 `AppModel.persistSamples` 仍然会把 `@Published people` 与存储层同步 ——
  `deletePerson` / `mergePerson` / `split` 都依赖这一行刷新界面。
- **规则回退是精确的**：`RuleEngine.execute` 只把「还不在目标相簿里」的照片加进去，
  并且**只把这批新增照片**记进日志（`RuleExecutionPolicy`）。
  因此回退时不会误删别的规则或用户自己放进该相簿的照片；
  匹配到的照片若都已在相簿中，则不写相册也不记日志。
- **聚类质心按样本数加权**：早期实现用 `(质心 + 新样本) / 2`，会让每个新扫到的照片占一半权重，
  质心被拖向最后扫描的照片（实测 0…9 的质心会偏到 8.0 而非 4.5）。现在用真实均值，
  并在建簇后按最终质心整体重分配一次。
- **阈值标定与特征提取方式绑定**：`ClusterThreshold` 把默认阈值定在 0.25、可调区间 0.10…0.35。
  实测 `vision-featureprint-256` 下 1038 张人脸两两最大**平方**距离只有约 0.19，
  旧的默认值 0.9 会让全部照片并成一个「人物 1」。`AppModel` 用一个标定版本号做一次性迁移：
  旧值（>0.35）会被重置为 0.25 并自动重聚一次。换特征模型时必须重新实测这个区间。
- **归类「相簿优先、AI 兜底」**：`ClusterRebuilder` 先按照片所属的**自定义相簿**决定归属
  （`PersonNamingPolicy.albumName`：照片在多个相簿里时取成员最少、最专有的那个，
  避免「全家福」盖过「妈妈」），剩下的照片才按人脸聚类分组；身份已确定的样本参与投票，
  所以「没有相簿、但和某相簿照片聚成一簇」的照片会跟着走。
  只认 `fetchCustomAlbums()`（`.albumRegular`，用户自己在「照片」App 里建的）：
  系统生成的相簿（同步 / 导入 / 智能）不参与，否则会出现「最近项目」这种人物。
  相簿命名的人物带 `Person.nameIsAuto`，是**可重新推导**的：相簿删掉或改名会随之更新；
  用户亲手起的名字（`renamePerson` 置 `nameIsAuto = false`）绝不被覆盖。
  注意这条规则很激进：事件相簿（如「旅行 2024」）里的人也会被当成一个人物。
- **「人物 N」不参与归属投票**：投票只认**用户命名的**与**本轮按相簿命名的**人物。
  否则一旦上一轮把所有脸错误地并成一个「人物 1」，投票会把新一轮的每个簇都拉回同一个人，
  重聚类永远分不开 —— 这正是「人物页始终只有一个分组」的根因。
- **人物展示用整张原图**：人物页的封面与照片网格都按比例显示**整张原图**
  （`contentMode: .fit`、圆角矩形），不再显示人脸裁剪图/特写。
  点开由 `PhotoViewerView` 先给一张 1600px 预览、再替换为**原图**
  （`PHImageManagerMaximumSize`，iCloud 照片会联网下载），支持双指缩放 / 双击放大。
  原图失败也会结束「加载中」，不会把用户困在转圈里（原图太大，不入 `NSCache`）。
- **增量扫描会更新已有人物**：新扫到的照片只要在那个相簿里就会并入对应人物，
  没有相簿但和该人物的照片聚成一簇也会跟着走，而不是又建一个「人物 N」——
  这条有 `testIncrementalScanMergesNewPhotoIntoExistingAlbumNamedPerson` 守着。
- **单次扫描有可配置上限**：设置里的「单次扫描上限」（0 = 不限制）经 `ScanBatchPolicy`
  换算成 `ScanCoordinator.start(limit:)` 的上限，并保证**永不为 0/负数** ——
  `Array.prefix(_:)` 收到负数会直接崩溃，那才是真的卡死。
  一批扫完就落盘并回到「已完成」，界面上提示还剩多少张（`ScanCoordinator.remaining`），
  可再次点「开始扫描」继续；后台刷新另有 60 张的硬上限（用户设置更小时以用户为准）以控制耗电。

## 隐私

- 不联网、不上传任何图片或人脸特征。
- 声明见 [PrivacyInfo.xcprivacy](PhotoFaceSorter/PrivacyInfo.xcprivacy)。
- 缓存仅存于 App 沙盒，卸载即清除；设置页可一键清空识别缓存与执行日志。

## 已知限制与后续计划

1. **人脸特征用的是 `VNGenerateImageFeaturePrintRequest`**，这是通用图像特征而非身份特征，
   跨照片的同一人相似度有限，聚类准确度是当前最大的短板。
   计划换用 Core ML 的人脸识别模型（ArcFace / MobileFaceNet）+ 关键点对齐 +
   L2 归一化与余弦阈值。
   **换模型时的安全性已有保障**：`FaceEmbeddingService.signature` 会随样本一起记录，
   `EmbeddingConsistency` 在新旧签名不一致时要求全量重扫，
   不会把不可比的新旧特征混在一起聚类（那会静默产出垃圾分组）。
   改动特征提取语义时**必须同时改 `signature`**。
   **缓解措施**：阈值已按该特征实测重标定（`ClusterThreshold`，默认 0.25），
   并且归类改为**相簿优先、AI 兜底**（用户按人建的自定义相簿是最可靠的身份来源；
   系统生成的相簿不参与）。
   注意这么用是「激进」的：自定义相簿若按事件命名（如「旅行 2024」），
   该分组也会被叫成「旅行 2024」，并与其他同名分组合并。
2. **聚类仍是「在线贪心 + 一次细化」**：第二遍重分配与样本顺序无关，
   但第一遍建簇本质上是顺序相关的。真正与顺序完全无关的方案
   （连通分量 / 层次聚类）代价是 O(n²)，计划与上面更换特征模型时一起评估。
3. **落盘仍是「整份重写」而非增量追加**：已消除 base64 膨胀、把记录也改为二进制，
   并用合并写入 + 每 100 张一次的间隔把重复编码压了下去。但每次落盘仍是全量编码一次，
   几十万样本时可进一步改为追加式日志 + 定期压缩，或 SQLite 增量写入。
4. **增量扫描以 `modificationDate` 判断变更**，并按 `ScanPlanPolicy` 决定范围。
   iCloud 尚未下载、或读取失败的照片**不会**被标记为已扫描（`ScanRecordPolicy`），
   下次扫描会自动重试，扫描页也会提示有多少张被跳过。
   尚未处理：多次重试仍失败的坏照片会一直留在待扫描集合里。
5. 规则条件的「来源相簿」已支持单选（`ClassifyRule.sourceAlbumLocalID`），
   暂不支持多相簿组合；照片时间 / 地点条件属于二期规划。
6. 逻辑层已开启 `SWIFT_STRICT_CONCURRENCY = complete`；视图层尚未逐一核对。
