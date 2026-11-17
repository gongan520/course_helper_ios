import Foundation
import ActivityKit

/// 主 App 侧的 Live Activity 管理器。
///
/// 负责：启动 / 更新 / 结束「宠物」实时活动，并写入 App Group 共享数据。
///
/// 设计要点：
/// 1. 支持 iOS 16.1（旧 API 兜底）与 16.2+（ActivityContent 新 API）；
/// 2. 冷启动会「认领」进程外残留的活动，避免重复创建 / 灵动岛不刷新；
/// 3. 活动被系统回收或用户划走后，`update` 会自动重建；
/// 4. 失败原因记入 `lastError`，通过 `statusPayload()` 抛给 Flutter 展示。
@available(iOS 16.1, *)
final class LiveActivityManager {

    static let shared = LiveActivityManager()

    private var activity: Activity<SignInActivityAttributes>?
    private var lastError: String?

    private init() {}

    // MARK: - 状态

    /// 供 Flutter 侧诊断使用。
    func statusPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "systemEnabled": ActivityAuthorizationInfo().areActivitiesEnabled,
            "activityCount": Activity<SignInActivityAttributes>.activities.count,
            "hasActivity": activity != nil,
            "lastError": lastError ?? "",
            "state": "none"
        ]
        if #available(iOS 16.2, *) {
            if let current = activity {
                payload["state"] = Self.stateName(current.activityState)
            }
        } else if activity != nil {
            payload["state"] = "active"
        }
        return payload
    }

    /// 启动（或复用）宠物实时活动。
    @discardableResult
    func start(
        statusText: String,
        signedAccounts: String,
        hostingCount: Int,
        mood: String,
        signedCount: Int
    ) -> [String: Any] {
        let state = makeState(
            statusText: statusText,
            signedAccounts: signedAccounts,
            hostingCount: hostingCount,
            mood: mood,
            signedCount: signedCount
        )
        writeSharedState(
            status: statusText,
            accounts: signedAccounts,
            count: hostingCount,
            mood: mood,
            signedCount: signedCount
        )

        // 系统层面关闭了「实时活动」时请求必然失败，直接给出明确原因
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "系统未允许实时活动"
            return statusPayload()
        }

        // 1. 已有活动（含冷启动后残留的）→ 复用并更新
        if let existing = adoptExisting() {
            activity = existing
            push(state: state, to: existing)
            lastError = nil
            return statusPayload()
        }

        // 2. 新建
        do {
            let created: Activity<SignInActivityAttributes>
            if #available(iOS 16.2, *) {
                created = try Activity.request(
                    attributes: SignInActivityAttributes(title: "JUST DO IT"),
                    content: ActivityContent(
                        state: state,
                        staleDate: Date().addingTimeInterval(8 * 3600)
                    ),
                    pushType: nil
                )
            } else {
                created = try Activity.request(
                    attributes: SignInActivityAttributes(title: "JUST DO IT"),
                    contentState: state,
                    pushType: nil
                )
            }
            activity = created
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            NSLog("LiveActivity 启动失败: \(error)")
        }
        return statusPayload()
    }

    /// 更新状态；活动已丢失时自动重建。
    @discardableResult
    func update(
        statusText: String,
        signedAccounts: String,
        hostingCount: Int,
        mood: String,
        signedCount: Int
    ) -> [String: Any] {
        let state = makeState(
            statusText: statusText,
            signedAccounts: signedAccounts,
            hostingCount: hostingCount,
            mood: mood,
            signedCount: signedCount
        )
        writeSharedState(
            status: statusText,
            accounts: signedAccounts,
            count: hostingCount,
            mood: mood,
            signedCount: signedCount
        )

        if let current = activity, isUsable(current) {
            push(state: state, to: current)
            return statusPayload()
        }

        // 活动已被系统回收 / 用户清除，重新拉起
        return start(
            statusText: statusText,
            signedAccounts: signedAccounts,
            hostingCount: hostingCount,
            mood: mood,
            signedCount: signedCount
        )
    }

    /// 结束并清除所有活动（用户关闭开关时调用）。
    func stop() {
        writeSharedState(status: "已停止", accounts: "", count: 0, mood: "sleep", signedCount: 0)
        let targets = Activity<SignInActivityAttributes>.activities
        activity = nil
        guard !targets.isEmpty else { return }

        let finalState = makeState(
            statusText: "已停止托管",
            signedAccounts: "",
            hostingCount: 0,
            mood: "sleep",
            signedCount: 0
        )
        for target in targets {
            end(target, with: finalState)
        }
    }

    // MARK: - 内部实现

    private func makeState(
        statusText: String,
        signedAccounts: String,
        hostingCount: Int,
        mood: String,
        signedCount: Int
    ) -> SignInActivityAttributes.ContentState {
        SignInActivityAttributes.ContentState(
            statusText: statusText,
            signedAccounts: signedAccounts,
            hostingCount: hostingCount,
            mood: mood,
            signedCount: signedCount
        )
    }

    private func isUsable(_ target: Activity<SignInActivityAttributes>) -> Bool {
        if #available(iOS 16.2, *) {
            return target.activityState == .active || target.activityState == .stale
        }
        return true
    }

    /// 认领仍然有效的活动：保留最后一个，其余立即结束（避免多活动堆叠）。
    private func adoptExisting() -> Activity<SignInActivityAttributes>? {
        let all = Activity<SignInActivityAttributes>.activities
        guard !all.isEmpty else { return nil }

        guard #available(iOS 16.2, *) else {
            return all.last
        }

        let alive = all.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        guard let keep = alive.last else { return nil }

        if alive.count > 1 {
            let finalState = makeState(
                statusText: "正在后台托管",
                signedAccounts: "",
                hostingCount: 0,
                mood: "idle",
                signedCount: 0
            )
            for extra in alive where extra.id != keep.id {
                end(extra, with: finalState)
            }
        }
        return keep
    }

    private func push(
        state: SignInActivityAttributes.ContentState,
        to target: Activity<SignInActivityAttributes>
    ) {
        if #available(iOS 16.2, *) {
            Task {
                await target.update(
                    ActivityContent(state: state, staleDate: Date().addingTimeInterval(8 * 3600))
                )
            }
        } else {
            Task {
                await target.update(using: state)
            }
        }
    }

    private func end(
        _ target: Activity<SignInActivityAttributes>,
        with state: SignInActivityAttributes.ContentState
    ) {
        if #available(iOS 16.2, *) {
            Task {
                await target.end(
                    ActivityContent(state: state, staleDate: Date()),
                    dismissalPolicy: .immediate
                )
            }
        } else {
            Task {
                await target.end(using: state, dismissalPolicy: .immediate)
            }
        }
    }

    /// 写入 App Group 共享数据（Extension 侧兜底读取用）。
    private func writeSharedState(
        status: String,
        accounts: String,
        count: Int,
        mood: String,
        signedCount: Int
    ) {
        let defaults = UserDefaults(suiteName: SignInActivityKeys.appGroup)
        defaults?.set(status, forKey: "live_status_text")
        defaults?.set(accounts, forKey: "live_signed_accounts")
        defaults?.set(count, forKey: "live_hosting_count")
        defaults?.set(mood, forKey: "live_mood")
        defaults?.set(signedCount, forKey: "live_signed_count")
    }

    @available(iOS 16.2, *)
    private static func stateName(_ state: ActivityState) -> String {
        switch state {
        case .active: return "active"
        case .stale: return "stale"
        case .ended: return "ended"
        case .dismissed: return "dismissed"
        @unknown default: return "unknown"
        }
    }
}
