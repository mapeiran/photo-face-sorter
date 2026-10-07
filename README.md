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
└── Views/        SwiftUI 页面（人物 / 归类 / 扫描 / 设置）
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
- **归类回退是精确的**：底层 `RuleEngine.execute` 只把「还不在目标相簿里」的照片加进去，
  并且**只把这批新增照片**记进日志（`RuleExecutionPolicy`）。
  因此回退时不会误删用户自己放进该相簿的照片；照片若都已在相簿中，则不写相册也不记日志。
  这套引擎现在只服务「归类审核」的写入与单张移动 —— **规则页已移除**，
  日志入口移到了设置页（`ExecutionLogView`），仍然可以回退。
- **聚类质心按样本数加权**：早期实现用 `(质心 + 新样本) / 2`，会让每个新扫到的照片占一半权重，
  质心被拖向最后扫描的照片（实测 0…9 的质心会偏到 8.0 而非 4.5）。现在用真实均值，
  并在建簇后按最终质心整体重分配一次。
- **人脸识别用的是 ArcFace 模型**（v7）：先用 Vision 关键点做 **5 点相似变换对齐**到
  112×112（ArcFace 标准模板，**不加 padding**），再跑 Core ML 得到 512 维特征并 L2 归一化。
  对齐不能省：实测它把「不同人」的相似度地板从 0.35 压到 0.08，可分间隔扩大 **3.1×**；
  而「同一个人」的相似度几乎不变 —— 也就是说**光看同人相似度是验不出对齐做错的**，
  必须看异人地板或肉眼确认裁剪正立（`FaceAlignmentServiceTests` 把坐标系钉死了）。
  拿不到 5 点关键点的脸直接不入簇。
- **阈值标定与特征提取方式绑定**：`ClusterThreshold` 用**余弦距离**（默认 0.60 ⇔ 相似度 ≥ 0.40），
  可调区间 0.30…0.90。本机 9 张脸 / 4 个身份的实测（见 `build/modelwork/REPORT.md`）：
  同人相似度 ∈ [0.657, 0.984]，异人 ∈ [−0.095, 0.082]；余弦距离 0.343…0.918 之间任何阈值都 0 错误，
  默认取偏精度一侧。`AppModel` 用标定版本号做一次性迁移（v7 会重置阈值并自动重聚）。
  **换特征模型时必须重新实测这个区间。**
  换算关系：单位向量下 `平方欧氏距离 = 2(1 − cos)`，而 `FaceClusteringService.cluster`
  的入参是**距离**（内部自己平方），所以传进去的必须是 `√(2d)` —— 传 2d 等于把阈值又平方一次。
- **归类「相簿优先、AI 兜底」**：`ClusterRebuilder` 先按照片所属的**自定义相簿**决定归属
  （`PersonNamingPolicy.albumName`：照片在多个相簿里时，**优先复用本轮已存在的人物名** ——
  识别到的分组因此并入同名 / 同相簿的已有人物，而不是被「最专有」的新相簿另立一个分组；
  没有可复用的人名时才取成员最少、最专有的那个，避免「全家福」盖过「妈妈」），
  剩下的照片才按人脸聚类分组；身份已确定的样本参与投票，
  所以「没有相簿、但和某相簿照片聚成一簇」的照片会跟着走。
  最后按**照片**归一：同一张照片上的多张脸按多数票统一成一个人物，
  因此一张照片只会出现在一个人物（相簿）里；手动修正 / 忽略的样本不参与归一。
  只认 `fetchCustomAlbums()`（`.albumRegular`，用户自己在「照片」App 里建的），
  而且相簿名要**像人名**（`PersonNameHeuristic`：不含数字、长度合理、不含
  「旅行 / 全家福 / 截图 / 工作」这类事件与分类词）—— 系统相簿（同步 / 导入 / 智能）
  和事件相簿都不参与，不会凭空变成人物；被过滤掉的照片退回 AI 聚类，不会丢。
  相簿命名的人物带 `Person.nameIsAuto`，是**可重新推导**的：相簿删掉或改名会随之更新；
  用户亲手起的名字（`renamePerson` 置 `nameIsAuto = false`）绝不被覆盖。
- **「人物 N」不参与归属投票**：投票只认**用户命名的**与**本轮按相簿命名的**人物。
  否则一旦上一轮把所有脸错误地并成一个「人物 1」，投票会把新一轮的每个簇都拉回同一个人，
  重聚类永远分不开 —— 这正是「人物页始终只有一个分组」的根因。
- **人物页完整还原系统相册结构**：分节逻辑在 `PeopleSectionBuilder`（纯函数，有单测）。
  系统「照片」App 里的**每一个文件夹**都会成为一节（`AlbumFolderStructure.folderOrder`，
  顺序跟随系统，含没有相簿的空文件夹；嵌套文件夹扁平列出、相簿取最近一层）。
  每节里：已经有同名人物分组的显示成**人物卡片**；
  还没有人物的相簿显示成**相簿卡片**（封面 + 名字 + 张数，点开进 `AlbumDetailView`）——
  事件相簿、还没扫到的相簿都不会丢。不在任何文件夹里的相簿归「未分组」
  （系统里完全没有文件夹时这一节叫「相簿」），最后是 **AI 分组（没有相簿）**。
  人物按名字（相簿名）用 `localizedStandardCompare` 排序
  （中文按本地化顺序，名字里的数字按数值大小，「人物 2」在「人物 10」前），
  相簿命名的人物因此落在它所属的文件夹里。
  还没「标记已查看」的新相簿不单独成组，而是留在自己的文件夹里、角标「新增」，
  顶部横幅显示数量并提供「标记已查看」（`AppModel.markNewAlbumsViewed`，
  名单持久化在 `UserDefaults`）。
  **文件夹可以折叠/展开**：点分节标题即可折叠，右上角菜单可「展开全部 / 折叠全部」，
  相簿多时能一屏看清整体结构。

- **默认只扫「散图」，但相簿内照片可以随时重新识别**：某个相簿是否参与扫描由
  `AlbumExclusionStore` 的三态决定 —— 用户显式**排除**的相簿跳过；显式**包含**的相簿参与；
  其余**自定义相簿**（`.albumRegular`）默认跳过（视为已归类），系统 / 同步相簿默认参与。
  `ScanCoordinator.buildPlan` 用 `PhotoLibraryService.albumsExcludedFromScan()` 算出这些照片，
  再由 `ScanPlanPolicy.shouldScan(…, scope:)` 按「范围 × 增量」挑人（纯函数、有单测）：
  - `.loosePhotos`（默认增量）：只扫散图 —— 重复扫描大相册时不必再对已整理好的照片跑一遍识别；
  - `.albumPhotos`：扫**所有相簿（含系统 / 同步相簿）里的照片** —— 扫描页的
    「**重新识别相簿内照片**」用它，而且是**主动重扫**（`ScanScope.forcesRescan`：
    忽略增量记录，扫过没改过的也重认一遍 —— 否则换了识别模型之后点它等于什么都没做）。
    范围用的是 `PhotoLibraryService.albumPhotoAssetIdentifiers()`（**全部**相簿），
    **不是** `albumsExcludedFromScan()`（只有默认会跳过的那些）；并且**不设单次数量上限**
    （`limit: .max`），一次把所有相簿的照片识别完；
  - `.allPhotos`：「**全量重扫**」用它，清空缓存后连相簿内的照片一起重认。
  跳过**不会删掉这些照片已有的样本**：它们仍是「相簿优先」的锚点，
  新扫到的散图若和它们聚成一簇，会并入对应人物、显示在该相簿所属的文件夹里。
  **扫描 / 重认全程只读相簿，永远不会修改相簿内容。**

  三个范围**互斥、不并行**：`ScanCoordinator.start` 只在「空闲 / 已完成」时启动，
  返回 `false` 表示已有任务在跑（例如后台自动扫描），界面会明确提示而不是静默失败。
  破坏性准备一律放在确认能启动**之后**、或扫描计划**内部**完成
  （`ScanCoordinator.canStartScan` + `buildPlan` 里丢旧样本），
  避免出现「数据已经清掉、扫描却没跑起来」这种静默丢结果。

- **手动决定每个相簿是否参与扫描**：相簿结构里的每一行**长按**，或进
  `AlbumDetailView` 右上角，都能切换「从扫描中排除 / 取消排除，参与扫描」；
  被排除的相簿在列表里用 `eye.slash` 标出。设置页的「排除相簿」
  （`ExcludedAlbumsView`）也能逐条修改。状态持久化在 `UserDefaults`：
  `excludedAlbumIDs`（显式排除）与 `includedAlbumIDs`（对自定义相簿取消默认排除）。
  改动后立即重算扫描页的「相簿内 / 散图」计数。

- **把人物（尤其 AI 分组）写进系统相簿**：人物详情页的「写入系统相簿」分区，或人物页
  **长按**卡片，都有「复制到 / 移动到系统相簿」—— 以人物名新建或复用系统相簿
  （`PersonAlbumExporter` → 复用 `RuleEngine.execute`），把该人物的照片写进去；
  `AppModel.exportPersonToAlbum` 负责去重取照片并记一条执行日志，所以能在执行日志里
  **回退**。复制只增不改；「移动」会从其它相簿移除这些照片（原图始终不删除），带二次确认。
  **单张照片**同样可以移动：看图页右上角菜单、人物详情与相簿里的缩略图长按，都有
  「移到系统相簿…」—— 用 `AlbumPickerView` 选已有相簿或新建（已有相簿**按系统「照片」文件夹分节**
  `AlbumFolderSectioning`，顺序跟随系统，没进文件夹的归「未分组」；节内按名称排序
  `AlbumTitleOrdering`；文件夹可点击**展开 / 收起**，默认收起、左上角可一键展开全部、
  **搜索时自动展开**；顶部有**「最近移动」快捷区** —— 最近写入过的相簿排在前面（最多 5 个，
  已被删除/改名的自动过滤，`RecentAlbumStore`）；还可**搜索**相簿，搜不到时用关键词直接新建；
  **新建相簿时可选择放进哪个系统文件夹**（`PhotoLibraryService.createAlbum(named:inFolderID:)`
  → `PHCollectionListChangeRequest.addChildCollections`，默认「顶层」）），语义一致
  （`AppModel.moveAssetsToAlbum`，同样记一条可回退的执行日志）。

- **「归类审核」把 AI 的提议交给你确认**：底部第 2 个 Tab「归类」
  （`ClassificationReviewView`）。它把**不在任何系统相簿中**的人脸样本按人物分组
  （`ClassificationProposalPolicy`，纯函数、有单测），每组显示识别人物名、目标相簿和
  照片缩略图，并标注目标相簿是「已有相簿」还是「新建相簿」。你可以：勾选 / 取消要归类的
  照片、右上角 ⋯ 菜单里「更改目标相簿」（`AlbumPickerView` 选已有或新建）或「重命名人物」
  （同时把目标相簿名改成新名字）、「确认加入」（复制）/「移动加入」（从其它相簿移除）/「跳过」。
  **只有点确认才会真正写入系统相簿**，每次确认各记一条可回退的执行日志。
  写入后（无论从归类页确认，还是从看图页 / 缩略图菜单「移到系统相簿」）都会**自动刷新**：
  `AppModel.exportAssetsToAlbum` 成功时发 `.albumExportDidFinish` 通知，归类页收到后重新统计，
  已归类的照片立刻从待确认里消失；**部分确认只移除那几张**，整组还有剩余就保留（用户的勾选也保留）。
  点缩略图可**全屏看大图**（左右滑动翻看该组），长按可看**图片详情**（详情页里能**直接选择 /
  跳过这张**）/ 去「照片」按日期搜索 / **跳过这张**。
  点「**目标相簿：X**」**整行可点**：相簿已存在就直接进去看里面的内容；还没创建的会打开
  `ProposalPhotosView` 预览「确认后将会写入这本相簿的照片」，在这里可以**多选 / 全选**要写入
  的照片（与归类页的勾选同步），点缩略图也能看大图；选好后**底部直接执行**
  「复制加入 / 移动加入… / 跳过」，不必退回列表。「移动加入…」会先弹出相簿选择器，
  **由你挑目标系统相簿**（已有或新建，按文件夹分组、可搜索、新建时还能选放进哪个文件夹），
  再把选中的照片移过去；两者都记可回退的执行日志。
  **「跳过」是持久的**：`ClassificationSkipStore` 会记住被跳过的**分组**和**单张照片** ——
  分组在「跳过」按钮里跳，单张可在缩略图长按菜单或图片详情页里「跳过这张」；之后刷新 / 重开都不再
  展示，工具栏「恢复已跳过」可以把它们找回来。底部还有**「删除所选」**：确认后把照片移到系统
  「最近删除」（30 天内可恢复），并同步清掉 App 里这些人脸样本与扫描记录。
  没有人脸的照片（无法识别到某个人物）不会出现在这里。

- **扫描页先「看清楚要扫什么」**：扫描页顶部是扫描控件，下方是**系统相簿结构**浏览器 ——
  当前系统的全部文件夹（`AppModel.folderStructure`），每个文件夹可展开列出其中的相簿
  （封面 + 张数），点相簿进 `AlbumDetailView` 看内部照片。
  同时用 `PhotoLibraryService.photoCounts()`（纯策略 `LibraryPhotoCountPolicy`）
  把「照片总数」和**三个按钮各自会识别多少张**分开写清楚（曾经只标了「散图会被识别」，
  而「全量重扫」是连相簿内照片一起扫的，于是按散图数量选上限、实际却扫了上限那么多，
  看起来像没按实际数量扫）：
  - 增量扫描：「开始扫描（增量）」只识别**散图** \(M) 张（其余在默认跳过的相簿里）；
  - 全量重扫：「清空并重扫」识别**全部** \(T = M + N) 张（含相簿内照片）；
  - 重新识别：「重新识别相簿内照片」识别**所有相簿内** \(K) 张。
  点右上角刷新可重新读取。**单次扫描上限只是上限**：待识别不足时只扫实际数量
  （`ScanBatchPolicy.batch` 有单测钉住：上限 100 对 3 张只返回 3 张）。
  文件夹可逐个展开/折叠，也可一键「展开全部 / 折叠全部」。

- **扫描中途「人物」页实时更新**：每扫过 `flushInterval`（100 张）且距上次刷新超过
  `ScanCoordinator.liveRefreshInterval`（8 秒）时，就对已扫到的部分做一次聚类并落盘，
  再通过 `onResultsChanged` 回调让 `AppModel.reload()` + `loadSamplesAsync()` ——
  不用等整批扫完，人物页就会出现新的分组。刷新按时间节流，避免频繁全量聚类拖慢扫描；
  扫描结束仍会做一次完整聚类。实时聚类写回的归属会被读回扫描中的样本数组，
  防止下一轮 `persist` 覆盖掉；手工 / 自动扫描都会触发（回调在 `AppDelegate` 装配）。
- **看图页可翻页、可单张调整**：全屏看图左右滑动（或点底部 ‹ › 按钮）翻看
  **同一分组**的上一张/下一张，标题显示「第几张 / 共几张」；**单击退出**、
  双击放大、双指缩放；未放大时滑动翻页，放大后拖动改为平移
  （预览图最多缓存 12 张，原图只留当前这张）。
  右上角菜单能直接把当前这张「移到其他人物… / 移出人物 / 标记非人物」，
  不必退回列表长按（`PhotoViewerView`）。
  菜单里的「移到系统相簿…」成功后**自动翻到下一张**（并短暂提示结果），
  如果当前已经是**最后一张**就自动退出看图页、返回上一页。
  菜单里还有「**删除这张照片**」：二次确认后移到系统「最近删除」（30 天内可恢复），
  同样自动翻到下一张 / 最后一张退出，并清掉 App 里对应的人脸样本。

- **照片详情 / 在系统「照片」打开**：看图页右上角菜单、人物详情与相簿里的缩略图**长按**，
  都提供「查看详情」（`PhotoDetailView`：类型、尺寸、收藏、拍摄/修改时间、位置、文件名）
  与「在「照片」中按日期搜索」。注意：iOS **没有公开接口**能直接定位到某一张具体照片 ——
  Photos.app 确实注册了 `photos://asset?uuid=` / `photos://contentmode?...&assetuuid=`，
  但它们被标记为 `CFBundleURLIsPrivate = true`，外部 App 调用会被系统拒绝
  （模拟器实测 `LSApplicationWorkspaceErrorDomain error 115`）。所以这里改用**公开** scheme
  `photos-navigation://search?searchTerm=<拍摄日期>`（`PhotoLibraryService.searchSystemPhotos`）：
  会打开「照片」的搜索并填入拍摄日期、显示当天的照片，仍需自己找到那一张；
  读不到拍摄日期时退回 `photos-redirect://`（`openSystemPhotosApp`）只打开「照片」App。

- **重复图片（只列不删）**：设置 → 重复图片（`DuplicateFinderView`）用感知哈希 dHash
  （`PerceptualHash`：9×8 灰度差分 64 位）扫描照片库，按汉明距离 ≤
  `DuplicateDetector.hammingThreshold`（6）用「代表元」分组
  （`DuplicateGroupingPolicy`，不做链式传递，避免 A≈B、B≈C 把一大批照片连成一组），
  找出视觉重复（重复导入、连拍、缩放/压缩后的同一张）。结果按可省空间排序，每组显示
  缩略图、尺寸与原始字节数。**只列出，不删除任何照片**；iCloud 未下载的
  （`isNetworkAccessAllowed = false`）会跳过并计数。局限：只看亮度梯度不看颜色，
  且对大幅裁剪不敏感 —— 少量误报由用户自己判断。
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
- 人脸识别模型（6.6 MB）**内置在 App 包里**，安装后不需要联网下载、也不会在运行时请求模型。
- 声明见 [PrivacyInfo.xcprivacy](PhotoFaceSorter/PrivacyInfo.xcprivacy)。
- 缓存仅存于 App 沙盒，卸载即清除；设置页可一键清空识别缓存与执行日志。

## 已知限制与后续计划

1. **人脸识别已换成 ArcFace 模型**（`PhotoFaceSorter/ML/FaceRecognition.mlpackage`，
   MobileFaceNet / InsightFace `w600k_mbf`，512 维，6.6 MB），全流程离线：
   Vision 关键点 → 5 点相似变换对齐到 112×112 → Core ML（可走神经网络引擎）→ L2 归一化。
   ONNX 与 Core ML 的数值一致性实测 cos = 0.999993。
   **换模型时的安全性已有保障**：`FaceEmbeddingService.signature` 会随样本一起记录，
   `EmbeddingConsistency` 在新旧签名不一致时要求全量重扫，
   不会把不可比的新旧特征混在一起聚类（那会静默产出垃圾分组）。
   改动特征提取语义时**必须同时改 `signature`**。
   ⚠️ **模型授权**：InsightFace 的预训练模型仅限**非商业研究使用**。若要商业发行，
   需要换一个可商用的人脸识别模型；转换脚本 `build/modelwork/convert_mil.py`（ONNX → MIL，
   自写、不依赖 coremltools 的 ONNX 前端）可以直接复用，只需替换 ONNX 文件与模板。
   **剩余短板**：标定用的 9 张公开人像里 4 个人差异很大，异人相似度天然接近 0，
   是「乐观下界」；真实家庭相册（亲属、同龄同性）会更高。建议后续加一个
   「用自己相册重新标定阈值」的入口。
   另外归类仍是**相簿优先、AI 兜底**（用户按人建的自定义相簿是最可靠的身份来源；
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
5. 规则页已移除；`RuleEngine` / `ClassifyRule` 只作为「归类写入 + 回退」的底层实现保留，
   不再有规则编辑界面。没有人脸的照片（无法判断归属）不会进入归类审核。
6. 逻辑层已开启 `SWIFT_STRICT_CONCURRENCY = complete`；视图层尚未逐一核对。
