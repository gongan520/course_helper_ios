import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - 宠物形象

/// 用 SwiftUI 图形绘制的宠物「小豆」（不依赖图片资源，避免打包丢失）。
@available(iOS 16.1, *)
struct PetFace: View {
    /// idle / happy / busy / sleep
    var mood: String
    var size: CGFloat

    private var faceGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.82, blue: 0.40),
                Color(red: 1.00, green: 0.55, blue: 0.28)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var earWidth: CGFloat { size * 0.26 }
    private var earHeight: CGFloat { size * 0.34 }
    private var eyeSize: CGFloat { max(2.0, size * 0.13) }

    var body: some View {
        ZStack {
            // 耳朵
            HStack(spacing: size * 0.26) {
                ear.rotationEffect(.degrees(-14))
                ear.rotationEffect(.degrees(14))
            }
            .offset(y: -size * 0.42)

            // 脸
            Circle()
                .fill(faceGradient)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.12), lineWidth: max(0.6, size * 0.02))
                )
                .frame(width: size, height: size)

            // 五官
            VStack(spacing: size * 0.09) {
                HStack(spacing: size * 0.24) {
                    eye
                    eye
                }
                mouth
            }
            .offset(y: size * 0.06)
        }
        .frame(width: size * 1.06, height: size * 1.24)
        .accessibilityLabel("宠物小豆")
    }

    private var ear: some View {
        Ellipse()
            .fill(Color(red: 1.00, green: 0.70, blue: 0.36))
            .frame(width: earWidth, height: earHeight)
    }

    @ViewBuilder
    private var eye: some View {
        switch mood {
        case "happy":
            // 弯弯的笑眼
            Capsule()
                .fill(Color.black.opacity(0.75))
                .frame(width: eyeSize * 1.5, height: max(1.4, eyeSize * 0.40))
        case "sleep":
            // 闭眼
            Capsule()
                .fill(Color.black.opacity(0.55))
                .frame(width: eyeSize * 1.4, height: max(1.2, eyeSize * 0.22))
        case "busy":
            // 专注的大眼
            Circle()
                .fill(Color.black.opacity(0.82))
                .frame(width: eyeSize * 1.15, height: eyeSize * 1.15)
        default:
            Circle()
                .fill(Color.black.opacity(0.78))
                .frame(width: eyeSize, height: eyeSize)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case "happy":
            // 张口笑
            RoundedRectangle(cornerRadius: eyeSize)
                .fill(Color.black.opacity(0.68))
                .frame(width: eyeSize * 1.6, height: eyeSize * 0.95)
        case "sleep":
            Capsule()
                .fill(Color.black.opacity(0.35))
                .frame(width: eyeSize * 0.9, height: max(1.0, eyeSize * 0.20))
        default:
            // 微笑弧线
            SmileArc()
                .stroke(
                    Color.black.opacity(0.58),
                    style: StrokeStyle(lineWidth: max(1.0, eyeSize * 0.26), lineCap: .round)
                )
                .frame(width: eyeSize * 1.5, height: eyeSize * 0.8)
        }
    }
}

/// 微笑弧线（独立成 Shape 便于复用与缩放）。
@available(iOS 16.1, *)
struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

// MARK: - 锁屏 / 展开卡片

@available(iOS 16.1, *)
struct PetLockScreenView: View {
    let state: SignInActivityAttributes.ContentState

    /// 宠物「说话」的内容
    private var speech: String {
        if state.statusText.contains("成功") { return "刚签到一个，好耶！" }
        if state.statusText.contains("手动") { return "有个签到要你亲自来" }
        if state.hostingCount > 0 { return "\(state.hostingCount) 门课我盯着呢" }
        return state.statusText
    }

    private var petStatus: String {
        if state.statusText.contains("成功") { return "心情很好" }
        if state.hostingCount > 0 { return "在后台值班" }
        return "在小憩"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PetFace(mood: state.mood, size: 50)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(SignInActivityKeys.petName)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.orange)
                    Text("· \(petStatus)")
                        .font(.caption2)
                        .foregroundColor(Color.white.opacity(0.55))
                }

                Text(speech)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    pill("托管 \(state.hostingCount)")
                    pill("今日 \(state.signedCount) 签")
                    Text("轻点回到 App")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.45))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Color.white.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.white.opacity(0.14))
            )
    }
}

// MARK: - Widget

/// 灵动岛 + 锁屏「实时活动」：以宠物形式表示 App 正在后台运行。
@available(iOS 16.1, *)
struct SignInActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SignInActivityAttributes.self) { context in
            PetLockScreenView(state: context.state)
                .activityBackgroundTint(Color(red: 0.07, green: 0.07, blue: 0.09))
                .activitySystemActionForegroundColor(Color.white)
                .widgetURL(URL(string: SignInActivityKeys.openURL))

        } dynamicIsland: { context in
            DynamicIsland {
                // 展开：左侧宠物 + 名字
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        PetFace(mood: context.state.mood, size: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(SignInActivityKeys.petName)
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.orange)
                            Text(context.state.hostingCount > 0
                                 ? "后台值班中"
                                 : "在后台")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 展开：右侧今日签到数
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(context.state.signedCount)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        Text("今日已签")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }

                // 展开：中间说话气泡
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.statusText.contains("成功")
                         ? "刚签到一个，好耶！"
                         : context.state.statusText)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                }

                // 展开：底部提示
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        if !context.state.signedAccounts.isEmpty {
                            Text("最近：\(context.state.signedAccounts)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("轻点回到 App")
                            .font(.system(size: 10))
                            .foregroundColor(.orange.opacity(0.9))
                    }
                }
            } compactLeading: {
                PetFace(mood: context.state.mood, size: 19)
            } compactTrailing: {
                Text("\(context.state.signedCount)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange)
            } minimal: {
                PetFace(mood: context.state.mood, size: 17)
            }
            .widgetURL(URL(string: SignInActivityKeys.openURL))
            .keylineTint(Color.orange)
        }
    }
}

/// Extension 侧兜底读取 App Group 数据（活动状态异常时用于降级展示）。
@available(iOS 16.1, *)
func readSharedState() -> SignInActivityAttributes.ContentState {
    let defaults = UserDefaults(suiteName: SignInActivityKeys.appGroup)
    let status = defaults?.string(forKey: "live_status_text") ?? "正在后台托管"
    let accounts = defaults?.string(forKey: "live_signed_accounts") ?? ""
    let count = defaults?.integer(forKey: "live_hosting_count") ?? 0
    let mood = defaults?.string(forKey: "live_mood") ?? "idle"
    let signedCount = defaults?.integer(forKey: "live_signed_count") ?? 0
    return SignInActivityAttributes.ContentState(
        statusText: status,
        signedAccounts: accounts,
        hostingCount: count,
        mood: mood,
        signedCount: signedCount
    )
}
