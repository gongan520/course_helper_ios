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
        /// 托管中的账号数量
        var hostingCount: Int
        /// 宠物心情：idle / happy / busy / sleep
        var mood: String
        /// 今日已签到次数（宠物旁边的数字）
        var signedCount: Int
    }

    /// 启动时固定的属性。
    var title: String
}

/// 供主 App 与 Extension 共享的常量（避免重复定义字符串）。
enum SignInActivityKeys {
    static let appGroup = "group.com.gongan520.coursehelper"
    /// 点击灵动岛时使用的 URL，需与 Info.plist 的 CFBundleURLTypes 一致
    static let openURL = "coursehelper://live"
    /// 宠物名
    static let petName = "小豆"
}
