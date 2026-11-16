import ActivityKit
import WidgetKit
import SwiftUI

/// 灵动岛 + 锁屏「实时活动」的展示。
@available(iOS 16.1, *)
struct SignInActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SignInActivityAttributes.self) { context in
            // 锁屏展示
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(context.attributes.title)
                        .font(.headline)
                    Spacer()
                    Text(context.state.statusText)
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                if !context.state.signedAccounts.isEmpty {
                    Text("已签到：\(context.state.signedAccounts)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if context.state.hostingCount > 0 {
                    Text("托管 \(context.state.hostingCount) 个账号")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // 展开状态（长按灵动岛）
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.title)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.statusText)
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.signedAccounts.isEmpty
                             ? "等待签到"
                             : "已签到 \(context.state.signedAccounts)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                // 紧凑状态（收起时左侧）
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } compactTrailing: {
                // 紧凑状态（收起时右侧）
                Text(context.state.signedAccounts.isEmpty
                     ? "\(context.state.hostingCount)签"
                     : "\(context.state.hostingCount)签")
                    .font(.caption2)
            } minimal: {
                // 最小状态
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .widgetURL(URL(string: "coursehelper://signin"))
            .keylineTint(Color.green)
        }
    }
}

/// 提供 App Group 数据读取（Widget 侧读取主 App 写入的共享数据）。
@available(iOS 16.1, *)
func readSharedState() -> SignInActivityAttributes.ContentState {
    let defaults = UserDefaults(suiteName: SignInActivityKeys.appGroup)
    let status = defaults?.string(forKey: "live_status_text") ?? "正在托管签到"
    let accounts = defaults?.string(forKey: "live_signed_accounts") ?? ""
    let count = defaults?.integer(forKey: "live_hosting_count") ?? 0
    return SignInActivityAttributes.ContentState(
        statusText: status,
        signedAccounts: accounts,
        hostingCount: count
    )
}
