import ActivityKit
import Foundation

/// 签到状态 Live Activity 的数据结构。
/// contentState 是会在灵动岛/锁屏上动态刷新的内容。
/// 此文件同时被主 App 与 Widget Extension 编译，故加 availability 标记。
@available(iOS 16.1, *)
struct SignInActivityAttributes: ActivityAttributes {

    /// 会随状态变化的宠物数据。
    public struct ContentState: Codable, Hashable {
        /// 状态文本，如「正在后台托管」「刚刚签到成功」
        var statusText: String
        /// 最近签到的账号名（逗号分隔）
        var signedAccounts: String
        /// 托管模式的账号数
        var autoCount: Int
        /// 定时模式的账号数
        var scheduledCount: Int
        /// 手动模式的账号数
        var manualCount: Int
        /// 已开启 AI 答题的账号数
        var aiCount: Int
        /// 宠物心情：idle / happy / busy / sleep
        var mood: String
        /// 今日已签到次数
        var signedCount: Int
        /// 动画帧：主 App 侧定时递增，用来驱动「蜡笔小新遛狗」的走动画面
        var frame: Int

        public init(
            statusText: String,
            signedAccounts: String = "",
            autoCount: Int = 0,
            scheduledCount: Int = 0,
            manualCount: Int = 0,
            aiCount: Int = 0,
            mood: String = "idle",
            signedCount: Int = 0,
            frame: Int = 0
        ) {
            self.statusText = statusText
            self.signedAccounts = signedAccounts
            self.autoCount = autoCount
            self.scheduledCount = scheduledCount
            self.manualCount = manualCount
            self.aiCount = aiCount
            self.mood = mood
            self.signedCount = signedCount
            self.frame = frame
        }

        /// 手写解码：字段缺失时回退默认值。
        /// ActivityKit 会在跨版本升级时用旧状态解码，缺字段不能直接失败，
        /// 否则旧活动读不出来，灵动岛会「卡住不动」。
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            statusText = try c.decodeIfPresent(String.self, forKey: .statusText) ?? ""
            signedAccounts = try c.decodeIfPresent(String.self, forKey: .signedAccounts) ?? ""
            autoCount = try c.decodeIfPresent(Int.self, forKey: .autoCount) ?? 0
            scheduledCount = try c.decodeIfPresent(Int.self, forKey: .scheduledCount) ?? 0
            manualCount = try c.decodeIfPresent(Int.self, forKey: .manualCount) ?? 0
            aiCount = try c.decodeIfPresent(Int.self, forKey: .aiCount) ?? 0
            mood = try c.decodeIfPresent(String.self, forKey: .mood) ?? "idle"
            signedCount = try c.decodeIfPresent(Int.self, forKey: .signedCount) ?? 0
            frame = try c.decodeIfPresent(Int.self, forKey: .frame) ?? 0
        }
    }

    /// 启动时固定的属性。
    var title: String
}

/// 供主 App 与 Extension 共享的常量（避免重复定义字符串）。
enum SignInActivityKeys {
    static let appGroup = "group.com.gongan520.coursehelper"
    /// 点击灵动岛时使用的 URL，需与 Info.plist 的 CFBundleURLTypes 一致
    static let openURL = "coursehelper://live"
    /// 角色名（原「小豆」换成蜡笔小新）
    static let petName = "蜡笔小新"
    /// 主标语
    static let slogan = "蜡笔小新正在守护你的课堂"
}
