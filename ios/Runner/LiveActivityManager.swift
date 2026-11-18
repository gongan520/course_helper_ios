import Foundation
import ActivityKit
import UIKit

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

    /// 是否应该持续显示（start/update 置 true，stop 置 false）。
    /// 看门狗只在「应该显示」时才会去补救，避免用户关掉开关后又被拉起。
    private var shouldRun = false

    /// 当前活动的创建时间。用于提前换班。
    private var activityStartedAt: Date?

    /// 看门狗：每 60 秒确认活动是否还活着、是否该换班。
    private var watchdogTimer: Timer?

    /// 上次重建时间，避免系统拒绝请求时疯狂重试。
    private var lastRebuildAt: Date?

    /// 后台降频用的计数器（每 5 次 ticker 才真正推送一帧）
    private var backgroundTickCounter: Int = 0

    /// 系统对 Live Activity 的硬限制：活跃 8 小时后被系统结束，锁屏再保留 4 小时。
    /// 也就是说任何活动最多存在 12 小时，这是 iOS 的规则，绕不过去。
    /// 对策是在 7 小时时主动换一个新活动，让用户看不到「消失」的瞬间。
    private static let maxActivityAge: TimeInterval = 7 * 3600

    /// 重建冷却时间
    private static let rebuildCooldown: TimeInterval = 60

    private init() {}

    // MARK: - 状态

    /// 供 Flutter 侧诊断使用。
    func statusPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "systemEnabled": ActivityAuthorizationInfo().areActivitiesEnabled,
            "activityCount": Activity<SignInActivityAttributes>.activities.count,
            "hasActivity": activity != nil,
            "animating": frameTimer != nil,
            "shouldRun": shouldRun,
            "watchdog": watchdogTimer != nil,
            "lastError": lastError ?? "",
            "state": "none"
        ]
        if let started = activityStartedAt {
            payload["ageSeconds"] = Int(Date().timeIntervalSince(started))
        }
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
        stopWatchdog()
        activity = nil
        activityStartedAt = nil
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
        shouldRun = true

        // 系统层面关闭了「实时活动」时请求必然失败，直接给出明确原因
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "系统未允许实时活动"
            return statusPayload()
        }

        // 1. 已有活动（含冷启动后残留的）→ 复用并更新
        if let existing = adoptExisting() {
            activity = existing
            // 冷启动认领的旧活动不知道真实创建时间，按现在算，
            // 最多再过 7 小时就会主动换一个新活动。
            if activityStartedAt == nil { activityStartedAt = Date() }
            push(state: state, to: existing)
            lastError = nil
            startTicker()
            startWatchdog()
            return statusPayload()
        }

        // 2. 新建
        _ = requestActivity(with: state)
        return statusPayload()
    }

    /// 新建一个实时活动。成功返回 true。
    ///
    /// `staleDate` 故意传 nil：设成固定时间的话，只要帧定时器被系统暂停，
    /// 到时内容就会被标成过期、变灰，最后被回收 —— 表现为「放着不动就没了」。
    private func requestActivity(
        with state: SignInActivityAttributes.ContentState
    ) -> Bool {
        do {
            let created: Activity<SignInActivityAttributes>
            if #available(iOS 16.2, *) {
                created = try Activity.request(
                    attributes: SignInActivityAttributes(title: "JUST DO IT"),
                    content: ActivityContent(state: state, staleDate: nil),
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
            activityStartedAt = Date()
            lastError = nil
            startTicker()
            startWatchdog()
            NSLog("LiveActivity 已创建")
            return true
        } catch {
            lastError = error.localizedDescription
            NSLog("LiveActivity 创建失败: \(error)")
            return false
        }
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
        shouldRun = true

        if let current = activity, isUsable(current) {
            if activityStartedAt == nil { activityStartedAt = Date() }
            push(state: state, to: current)
            startTicker()
            startWatchdog()
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
        shouldRun = false
        stopTicker()
        stopWatchdog()
        activityStartedAt = nil
        lastRebuildAt = nil
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
            // 活动被系统回收 / 用户划掉：清空引用并尽快重建。
            // 以前这里只是 stopTicker，靠下一次 update 补救 —— 但后台没有
            // update 调用，活动就永久消失了，只能手动关开开关。
            guard self.isUsable(target) else {
                NSLog("LiveActivity 活动已失效，安排重建")
                self.activity = nil
                self.activityStartedAt = nil
                self.stopTicker()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.ensureAlive("ticker 检测到活动失效")
                }
                return
            }
            guard !self.updating else { return }

            // 后台降频：0.4 秒一帧只在前台需要（看得见的流畅度）。
            // 挂在后台时高频更新会被系统惩罚性限流，反而更容易把活动掐掉，
            // 所以后台改成 2 秒一帧 —— 活动还活着、内容还在刷，只是跳得慢一点。
            let inBackground = UIApplication.shared.applicationState != .active
            if inBackground {
                self.backgroundTickCounter &+= 1
                if self.backgroundTickCounter % 5 != 0 { return }
            } else {
                self.backgroundTickCounter = 0
            }

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

    // MARK: - 保活（24 小时不掉线）

    /// 看门狗：每 60 秒确认一次活动还在、并且没到系统上限。
    ///
    /// 这是「隔一晚就必须关开开关」的根治手段：活动被系统结束或被用户划掉时，
    /// 帧定时器可能已经停了，没人会发现。看门狗独立于活动存在，能把它拉回来。
    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.ensureAlive("看门狗巡检")
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    /// 确保有一个可用且未超龄的活动，需要时重建 / 换班。
    private func ensureAlive(_ reason: String) {
        // 用户关掉开关后不再补救
        guard shouldRun else { return }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "系统未允许实时活动"
            return
        }

        let now = Date()

        if let current = activity, isUsable(current) {
            let age = activityStartedAt.map { now.timeIntervalSince($0) } ?? 0
            guard age > Self.maxActivityAge else {
                // 一切正常：确保帧定时器在跑（被系统暂停过就重新拉起）
                startTicker()
                return
            }
            // 接近 iOS 的 8 小时上限：主动结束，换一个新活动，避免到点被系统掐掉
            NSLog("LiveActivity 已运行 \(Int(age / 3600)) 小时，主动换班（\(reason)）")
            stopTicker()
            end(current, with: latest)
            activity = nil
            activityStartedAt = nil
            // 换班是计划内动作，不受重建冷却限制
            lastRebuildAt = nil
        }

        if let last = lastRebuildAt, now.timeIntervalSince(last) < Self.rebuildCooldown {
            return
        }
        lastRebuildAt = now
        NSLog("LiveActivity 重建（\(reason)）")
        _ = requestActivity(with: latest)
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
                // staleDate 传 nil：不用时间戳主动标过期。
                // 一旦设成「8 小时后过期」，后台更新被系统限流时内容就会变灰，
                // 接着被回收 —— 这正是「挂一晚就没了」的来源之一。
                await target.update(
                    ActivityContent(state: state, staleDate: nil)
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
