import Foundation

/// 判断一个相簿名是否「像人名」。
///
/// 归类只让像人名的**自定义相簿**参与，否则「旅行 2024」「截图」这类相簿
/// 会凭空生成一个人物。这里是启发式规则（长度、数字、常见非人名关键词），
/// 宁可漏判也不把事件/分类相簿当成人名 —— 漏判的相簿只是退回 AI 聚类，不会丢照片。
enum PersonNameHeuristic {

    /// 名字最长多少字符，超过基本不是人名
    static let maxLength = 12

    /// 含这些词的相簿不当作人名（事件 / 分类 / 用途类相簿）
    static let stopWords: [String] = [
        "旅行", "旅游", "出游", "自驾", "露营", "徒步", "爬山", "滑雪", "潜水", "度假",
        "婚礼", "订婚", "求婚", "生日", "聚会", "聚餐", "团建", "会议", "活动", "比赛",
        "演唱会", "音乐会", "展览", "漫展", "毕业", "开学", "军训", "运动会",
        "节日", "春节", "中秋", "国庆", "圣诞", "元旦", "跨年", "万圣", "感恩",
        "母亲节", "父亲节", "儿童节", "情人节", "元宵", "端午", "清明",
        "全家福", "合影", "合照", "自拍", "证件", "截图", "屏幕", "录屏", "壁纸", "头像",
        "表情包", "素材", "设计", "作品", "项目", "工作", "学习", "笔记", "文档", "收据",
        "发票", "合同", "扫描", "下载", "微信", "相册", "照片", "图片", "视频", "相机",
        "手机", "备份", "存档", "旧照", "宠物", "美食", "食物", "风景", "建筑", "街拍",
        "植物", "天空", "回忆", "随手拍", "生活", "日常", "打卡", "游记", "攻略", "装修",
        "健身", "运动", "游戏", "电影", "追剧", "番剧", "动漫"
    ]

    /// 名字里出现这些字符基本不是人名（日期、编号、列表分隔符）
    static let forbiddenCharacters = CharacterSet(charactersIn: "0123456789/\\|:：#*?!？()（）[]【】<>《》")

    static func looksLikePersonName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return false }
        guard trimmed.rangeOfCharacter(from: forbiddenCharacters) == nil else { return false }
        guard !stopWords.contains(where: { trimmed.contains($0) }) else { return false }
        return true
    }
}
