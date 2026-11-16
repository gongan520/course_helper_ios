import ActivityKit
import WidgetKit
import SwiftUI

/// 签到状态 Live Activity 的数据结构。
/// contentState 是会在灵动岛/锁屏上动态刷新的内容。
/// 此文件同时被主 App 与 Widget Extension 编译，故加 availability 标记。
@available(iOS 16.1, *)
struct SignInActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 当前状态文本，如「正在托管签到」「已签到」等
        var statusText: String
        /// 已签到的账号名（可多个，用逗号分隔）
        var signedAccounts: String
        /// 托管中的账号数量
        var hostingCount: Int
    }

    /// 启动时固定的属性（本次活动的标题）
    var title: String
}

/// 供主 App 侧共享的常量（避免重复定义字符串）。
enum SignInActivityKeys {
    static let appGroup = "group.com.gongan520.coursehelper"
}
