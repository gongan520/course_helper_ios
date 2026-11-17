import Foundation
import ActivityKit

/// 主 App 侧的 Live Activity 管理器。
///
/// 负责：启动 / 更新 / 结束「蜡笔小新」实时活动，并写入 App Group 共享数据。
///
/// 设计要点：
/// 1. 支持 iOS 16.1（旧 API 兜底）与 16.2+（ActivityContent 新 API）；
/// 2. 冷启动会「认领」进程外残留的活动，避免重复创建 / 灵动岛不刷新；
/// 3. 活动被系统回收或用户划走后，`update` 会自动重建；
/// 4. 失败原因记入 `lastError`，通过 `statusPayload()` 抛给 Flutter 展示；
/// 5. 内置帧定时器：Live Activity 本身不支持连续动画，只能靠不断更新
///    contentState 的 `frame` 字段来驱动「小新遛狗」的走动画面。
@available(iOS 16.1, *)
final class LiveActivityManager {

    static let shared = LiveActivityManager()

    private var activity: Activity<SignInActivityAttributes>?
    private var lastError: String?

    /// 当前完整状态（帧定时器只需改 frame 后重新推送）
    private var latest = SignInActivityAttributes.ContentState(statusText: "")

    /// 动画帧序号（取模 24：8 帧步态与 12 帧来回走动的最小公倍数）
    private var frameIndex: Int = 0

    /// 动画定时器（1.2 秒一帧，兼顾「看得出在走」与系统更新频率限制）
    private var frameTimer: Timer?

    /// 上一帧是否还在写入（避免系统变慢时更新任务堆叠）
    private var updating = false

    /// 写入批次号，用于超时复位 `updating`
    private var pushToken: Int = 0

    private init() {}

    // MARK: - 状态

    /// 供 Flutter 侧诊断使用。
    func statusPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "systemEnabled": ActivityAuthorizationInfo().areActivitiesEnabled,
            "activityCount": Activity<SignInActivityAttributes>.activities.count,
            "hasActivity": activity != nil,
            "animating": frameTimer != nil,
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

    /// 数据结构版本。
    ///
    /// v1.3.7 把 `hostingCount` 拆成了 auto/scheduled/manual/ai 四个字段。
    /// 系统会跨 App 升级保留旧的实时活动，旧活动是用旧结构编码的，
    /// 被新版本「认领」后容易出现 Widget 渲染不出来（灵动岛空白）的情况。
    /// 因此版本号变化时先把所有残留活动清掉，再重建一个全新的。
    private static let schemaVersion = 2
    private static let schemaKey = "live_schema_version"

    /// 升级后首次启动时清理旧结构残留活动。
    private func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.schemaKey) != Self.schemaVersion else { return }
        defaults.set(Self.schemaVersion, forKey: Self.schemaKey)

        stopTicker()
        activity = nil
        let leftovers = Activity<SignInActivityAttributes>.activities
        guard !leftovers.isEmpty else { return }
        let finalState = SignInActivityAttributes.ContentState(
            statusText: "已停止托管",
            mood: "sleep"
        )
        for old in leftovers {
            end(old, with: finalState)
        }
        NSLog("LiveActivity 清理旧版本残留活动 \(leftovers.count) 个")
    }

    /// 启动（或复用）实时活动。
    @discardableResult
    func start(
        statusText: String,
        signedAccounts: String,
        autoCount: Int,
        scheduledCount: Int,
        manualCount: Int,
        aiCount: Int,
        mood: String,
        signedCount: Int
    ) -> [String: Any] {
        migrateIfNeeded()
        let state = SignInActivityAttributes.ContentState(
            statusText: statusText,
            signedAccounts: signedAccounts,
            autoCount: autoCount,
            scheduledCount: scheduledCount,
            manualCount: manualCount,
            aiCount: aiCount,
            mood: mood,
            signedCount: signedCount,
            frame: frameIndex
        )
        latest = state
        writeSharedState(state)

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
            startTicker()
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
            startTicker()
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
        autoCount: Int,
        scheduledCount: Int,
        manualCount: Int,
        aiCount: Int,
        mood: String,
        signedCount: Int
    ) -> [String: Any] {
        let state = SignInActivityAttributes.ContentState(
            statusText: statusText,
            signedAccounts: signedAccounts,
            autoCount: autoCount,
            scheduledCount: scheduledCount,
            manualCount: manualCount,
            aiCount: aiCount,
            mood: mood,
            signedCount: signedCount,
            frame: frameIndex
        )
        latest = state
        writeSharedState(state)

        if let current = activity, isUsable(current) {
            push(state: state, to: current)
            startTicker()
            return statusPayload()
        }

        // 活动已被系统回收 / 用户清除，重新拉起
        return start(
            statusText: statusText,
            signedAccounts: signedAccounts,
            autoCount: autoCount,
            scheduledCount: scheduledCount,
            manualCount: manualCount,
            aiCount: aiCount,
            mood: mood,
            signedCount: signedCount
        )
    }

    /// 结束并清除所有活动（用户关闭开关时调用）。
    func stop() {
        stopTicker()
        latest = SignInActivityAttributes.ContentState(statusText: "已停止", mood: "sleep")
        writeSharedState(latest)
        let targets = Activity<SignInActivityAttributes>.activities
        activity = nil
        guard !targets.isEmpty else { return }

        let finalState = SignInActivityAttributes.ContentState(
            statusText: "已停止托管",
            mood: "sleep"
        )
        for target in targets {
            end(target, with: finalState)
        }
    }

    // MARK: - 动画帧

    /// 启动帧定时器：不断更新 frame，驱动灵动岛右侧那颗红心「跳动」。
    ///
    /// Live Activity 的视图不支持持续动画，只能靠不断更新 contentState 出帧。
    /// 4 帧一个心跳周期（正常 → 胀大 → 回落 → 微缩），0.4 秒一帧，约 1.6 秒跳一次；
    /// 再快（<0.25s）会被系统合并更新反而卡顿，也更耗电。
    private func startTicker() {
        guard frameTimer == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard let target = self.activity else {
                self.stopTicker()
                return
            }
            // 活动被系统回收 / 用户划掉：清空引用，交给下一次 update 重建，
            // 避免定格在一个已经消失的活动上。
            guard self.isUsable(target) else {
                self.activity = nil
                self.stopTicker()
                return
            }
            guard !self.updating else { return }
            // 4 帧一个心跳周期（正常 → 胀大 → 回落 → 微缩），0.4 秒一帧，1.6 秒跳一次。
            // 灵动岛上是静态场景，只有右边那颗红心需要这个 frame。
            self.frameIndex = (self.frameIndex + 1) % 4
            var state = self.latest
            state.frame = self.frameIndex
            self.push(state: state, to: target)
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func stopTicker() {
        frameTimer?.invalidate()
        frameTimer = nil
    }

    // MARK: - 内部实现

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
            let finalState = SignInActivityAttributes.ContentState(
                statusText: "正在后台托管",
                mood: "idle"
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
        updating = true
        pushToken &+= 1
        let token = pushToken

        // 兜底复位：即使 update 的 await 迟迟不返回（系统节流时会发生），
        // 也不能让 updating 永久卡住，否则后续所有帧都会被跳过。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if self.pushToken == token { self.updating = false }
        }

        if #available(iOS 16.2, *) {
            Task { [weak self] in
                await target.update(
                    ActivityContent(state: state, staleDate: Date().addingTimeInterval(8 * 3600))
                )
                guard let self = self else { return }
                if self.pushToken == token { self.updating = false }
            }
        } else {
            Task { [weak self] in
                await target.update(using: state)
                guard let self = self else { return }
                if self.pushToken == token { self.updating = false }
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
    private func writeSharedState(_ state: SignInActivityAttributes.ContentState) {
        let defaults = UserDefaults(suiteName: SignInActivityKeys.appGroup)
        defaults?.set(state.statusText, forKey: "live_status_text")
        defaults?.set(state.signedAccounts, forKey: "live_signed_accounts")
        defaults?.set(state.autoCount, forKey: "live_auto_count")
        defaults?.set(state.scheduledCount, forKey: "live_scheduled_count")
        defaults?.set(state.manualCount, forKey: "live_manual_count")
        defaults?.set(state.aiCount, forKey: "live_ai_count")
        defaults?.set(state.mood, forKey: "live_mood")
        defaults?.set(state.signedCount, forKey: "live_signed_count")
        defaults?.set(state.frame, forKey: "live_frame")
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
