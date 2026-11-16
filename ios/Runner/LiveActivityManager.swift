import Foundation
import ActivityKit

/// 主 App 侧的 Live Activity 管理器。
/// 负责：启动、更新、结束签到状态 Live Activity，并写入 App Group 共享数据供 Widget 读取。
@available(iOS 16.2, *)
final class LiveActivityManager {

    static let shared = LiveActivityManager()

    private var currentActivity: Activity<SignInActivityAttributes>?

    /// 启动（或更新）Live Activity。
    func start(statusText: String, signedAccounts: String, hostingCount: Int) {
        // 1. 先写入 App Group 共享数据（Widget 侧会读取）
        writeSharedState(status: statusText, accounts: signedAccounts, count: hostingCount)

        // 2. 已有活动则更新内容，否则新建
        if let current = currentActivity {
            Task {
                await current.update(
                    ActivityContent(
                        state: SignInActivityAttributes.ContentState(
                            statusText: statusText,
                            signedAccounts: signedAccounts,
                            hostingCount: hostingCount
                        ),
                        staleDate: Date().addingTimeInterval(3600)
                    )
                )
            }
            return
        }

        // 3. 新建活动
        let attributes = SignInActivityAttributes(title: "JUST DO IT")
        let initialState = SignInActivityAttributes.ContentState(
            statusText: statusText,
            signedAccounts: signedAccounts,
            hostingCount: hostingCount
        )
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: initialState,
                    staleDate: Date().addingTimeInterval(3600)
                ),
                pushType: nil
            )
            currentActivity = activity
        } catch {
            // 无法创建（例如未授权或系统限制），静默处理
            NSLog("LiveActivity start failed: \(error)")
        }
    }

    /// 更新状态（签名结果变化时调用）。
    func update(statusText: String, signedAccounts: String, hostingCount: Int) {
        writeSharedState(status: statusText, accounts: signedAccounts, count: hostingCount)
        guard let current = currentActivity else {
            // 若无活动，尝试启动
            start(statusText: statusText, signedAccounts: signedAccounts, hostingCount: hostingCount)
            return
        }
        Task {
            await current.update(
                ActivityContent(
                    state: SignInActivityAttributes.ContentState(
                        statusText: statusText,
                        signedAccounts: signedAccounts,
                        hostingCount: hostingCount
                    ),
                    staleDate: Date().addingTimeInterval(3600)
                )
            )
        }
    }

    /// 结束 Live Activity（用户关闭托管时调用）。
    func stop() {
        writeSharedState(status: "已停止", accounts: "", count: 0)
        guard let current = currentActivity else { return }
        Task {
            await current.end(
                ActivityContent(
                    state: SignInActivityAttributes.ContentState(
                        statusText: "已停止",
                        signedAccounts: "",
                        hostingCount: 0
                    ),
                    staleDate: Date()
                ),
                dismissalPolicy: .immediate
            )
        }
        currentActivity = nil
    }

    /// 写入 App Group 共享数据。
    private func writeSharedState(status: String, accounts: String, count: Int) {
        let defaults = UserDefaults(suiteName: SignInActivityKeys.appGroup)
        defaults?.set(status, forKey: "live_status_text")
        defaults?.set(accounts, forKey: "live_signed_accounts")
        defaults?.set(count, forKey: "live_hosting_count")
    }
}
