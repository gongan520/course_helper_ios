import ActivityKit
import WidgetKit
import SwiftUI
import Foundation

// MARK: - 主题色

@available(iOS 16.1, *)
private enum ShinColor {
    static let skin = Color(red: 1.00, green: 0.87, blue: 0.74)
    static let red = Color(red: 0.90, green: 0.19, blue: 0.15)
    static let yellow = Color(red: 1.00, green: 0.82, blue: 0.24)
    static let ink = Color.black.opacity(0.85)
    static let dog = Color(red: 0.97, green: 0.97, blue: 0.97)
    static let leash = Color(red: 0.98, green: 0.98, blue: 0.98).opacity(0.8)
}

// MARK: - 蜡笔小新

/// 用 SwiftUI 图形绘制蜡笔小新（不依赖图片资源，避免打包丢图）。
/// 设计画布为 46×100，最终按 `height` 等比缩放。
@available(iOS 16.1, *)
struct ShinchanFigure: View {
    /// 动画帧（主 App 侧定时递增）
    var phase: Int
    /// 目标高度（pt）
    var height: CGFloat
    /// idle / happy / busy / sleep
    var mood: String = "idle"

    private let dw: CGFloat = 46
    private let dh: CGFloat = 82

    /// 一个完整步态周期 8 帧
    private var step: Double {
        let p = Double(((phase % 8) + 8) % 8)
        return p / 8.0 * 2.0 * Double.pi
    }

    private var legSwing: Double { sin(step) * 16.0 }
    private var armSwing: Double { sin(step + Double.pi) * 10.0 }
    private var bob: CGFloat { CGFloat(abs(sin(step))) * 1.2 }
    private var isSleeping: Bool { mood == "sleep" }
    private var isHappy: Bool { mood == "happy" }

    var body: some View {
        figure
    }

    /// 实际图形（放在普通计算属性里，才能用 `let` + `return`）。
    private var figure: some View {
        let s = height / dh
        return ZStack {
            // 腿（裤脚以下）
            leg(hipX: 17.5, angle: legSwing)
            leg(hipX: 29.0, angle: -legSwing)

            // 短裤
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ShinColor.yellow)
                .frame(width: 25, height: 11)
                .position(x: 23, y: 60)

            // 上衣
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ShinColor.red)
                .frame(width: 27, height: 22)
                .position(x: 23, y: 46)

            // 手臂：右手（画面右侧）牵着狗绳
            Capsule()
                .fill(ShinColor.skin)
                .frame(width: 13, height: 5)
                .rotationEffect(.degrees(-24 + armSwing), anchor: .leading)
                .position(x: 35, y: 42)

            // 手臂：左手
            Capsule()
                .fill(ShinColor.skin)
                .frame(width: 10, height: 5)
                .rotationEffect(.degrees(28 - armSwing), anchor: .trailing)
                .position(x: 12, y: 44)

            // 头发
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ShinColor.ink)
                .frame(width: 30, height: 18)
                .position(x: 23, y: 12)

            // 连脸侧的鬓角
            Capsule()
                .fill(ShinColor.ink)
                .frame(width: 5, height: 9)
                .position(x: 9, y: 16)
            Capsule()
                .fill(ShinColor.ink)
                .frame(width: 5, height: 9)
                .position(x: 37, y: 16)

            // 脸
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(ShinColor.skin)
                .frame(width: 26, height: 21)
                .position(x: 23, y: 25)

            // 眉毛（小新的标志：粗眉毛）
            eyebrow(x: 17.5)
            eyebrow(x: 29.0)

            // 眼睛
            eyes

            // 嘴
            mouth

            // 腮红
            Circle()
                .fill(Color(red: 1.0, green: 0.55, blue: 0.5).opacity(0.45))
                .frame(width: 4, height: 2.6)
                .position(x: 13, y: 30)
            Circle()
                .fill(Color(red: 1.0, green: 0.55, blue: 0.5).opacity(0.45))
                .frame(width: 4, height: 2.6)
                .position(x: 33, y: 30)
        }
        .frame(width: dw, height: dh)
        .scaleEffect(s, anchor: .topLeading)
        .frame(width: dw * s, height: dh * s, alignment: .topLeading)
        .offset(y: -bob)
        .accessibilityLabel("蜡笔小新")
    }

    // MARK: 零件

    private func leg(hipX: CGFloat, angle: Double) -> some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(ShinColor.skin)
                .frame(width: 5.5, height: 17)
            Capsule()
                .fill(Color.white)
                .frame(width: 7, height: 5)
                .offset(y: 1)
        }
        .rotationEffect(.degrees(angle), anchor: .top)
        .offset(y: 8)
        .position(x: hipX, y: 64)
    }

    private func eyebrow(x: CGFloat) -> some View {
        Capsule()
            .fill(ShinColor.ink)
            .frame(width: 9, height: 2.8)
            .rotationEffect(.degrees(x < 23 ? 8 : -8))
            .position(x: x, y: 20.5)
    }

    @ViewBuilder
    private var eyes: some View {
        if isSleeping {
            // 闭眼：两条短横线
            Capsule().fill(ShinColor.ink).frame(width: 5, height: 1.4)
                .position(x: 17.5, y: 27)
            Capsule().fill(ShinColor.ink).frame(width: 5, height: 1.4)
                .position(x: 29.0, y: 27)
        } else if isHappy {
            // 笑眼：弯弯的弧
            Capsule().fill(ShinColor.ink).frame(width: 5.4, height: 2.2)
                .position(x: 17.5, y: 26.6)
            Capsule().fill(ShinColor.ink).frame(width: 5.4, height: 2.2)
                .position(x: 29.0, y: 26.6)
        } else {
            Circle().fill(ShinColor.ink).frame(width: 4.4, height: 4.4)
                .position(x: 17.5, y: 27)
            Circle().fill(ShinColor.ink).frame(width: 4.4, height: 4.4)
                .position(x: 29.0, y: 27)
            Circle().fill(Color.white).frame(width: 1.5, height: 1.5)
                .position(x: 18.6, y: 25.8)
            Circle().fill(Color.white).frame(width: 1.5, height: 1.5)
                .position(x: 30.1, y: 25.8)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        if isSleeping {
            Capsule().fill(ShinColor.ink.opacity(0.7))
                .frame(width: 3, height: 1.2)
                .position(x: 23, y: 32.6)
        } else if isHappy {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(ShinColor.ink)
                .frame(width: 6, height: 4)
                .position(x: 23, y: 32.6)
        } else {
            Capsule().fill(ShinColor.ink.opacity(0.8))
                .frame(width: 5, height: 1.6)
                .position(x: 23, y: 32.4)
        }
    }
}

// MARK: - 小白（狗）

/// 设计画布 36×32。
@available(iOS 16.1, *)
struct ShiroFigure: View {
    var phase: Int
    var height: CGFloat
    var mood: String = "idle"

    private let dw: CGFloat = 36
    private let dh: CGFloat = 30

    private var step: Double {
        let p = Double(((phase % 8) + 8) % 8)
        return p / 8.0 * 2.0 * Double.pi
    }

    private var legSwing: CGFloat { CGFloat(sin(step)) * 2.2 }
    private var bob: CGFloat { CGFloat(abs(sin(step))) * 0.8 }
    private var tailUp: Bool { mood == "happy" }

    var body: some View {
        figure
    }

    /// 实际图形（放在普通计算属性里，才能用 `let` + `return`）。
    private var figure: some View {
        let s = height / dh
        return ZStack {
            // 尾巴
            Capsule()
                .fill(ShinColor.dog)
                .frame(width: 8, height: 3)
                .rotationEffect(.degrees(tailUp ? -55 : -25))
                .position(x: 5, y: tailUp ? 6 : 10)

            // 腿
            dogLeg(x: 10.5, dy: legSwing)
            dogLeg(x: 14.5, dy: -legSwing)
            dogLeg(x: 20.0, dy: -legSwing)
            dogLeg(x: 24.0, dy: legSwing)

            // 身体
            Capsule()
                .fill(ShinColor.dog)
                .frame(width: 21, height: 12)
                .position(x: 16, y: 16)

            // 头
            Circle()
                .fill(ShinColor.dog)
                .frame(width: 13, height: 13)
                .position(x: 27, y: 11)

            // 耳朵（小黑耳）
            Ellipse()
                .fill(ShinColor.ink)
                .frame(width: 6, height: 8.4)
                .rotationEffect(.degrees(-22))
                .position(x: 23, y: 6)
            Ellipse()
                .fill(ShinColor.ink)
                .frame(width: 6, height: 8.4)
                .rotationEffect(.degrees(24))
                .position(x: 31, y: 5.6)

            // 眼睛
            Circle()
                .fill(ShinColor.ink)
                .frame(width: 2.3, height: 2.3)
                .position(x: 28.4, y: 9.6)

            // 鼻子
            Circle()
                .fill(ShinColor.ink)
                .frame(width: 2.4, height: 2.4)
                .position(x: 32.6, y: 12.4)
        }
        .frame(width: dw, height: dh)
        .scaleEffect(s, anchor: .topLeading)
        .frame(width: dw * s, height: dh * s, alignment: .topLeading)
        .offset(y: -bob)
        .accessibilityLabel("小白")
    }

    private func dogLeg(x: CGFloat, dy: CGFloat) -> some View {
        Capsule()
            .fill(ShinColor.dog)
            .frame(width: 2.8, height: 8)
            .offset(x: dy * 0.35)
            .position(x: x, y: 24)
    }
}

// MARK: - 狗绳

/// 一条轻微下垂的狗绳（用于把左手与小白连起来）。
@available(iOS 16.1, *)
struct LeashCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.55),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height)
        )
        return path
    }
}

// MARK: - 组合场景（小新遛狗）

@available(iOS 16.1, *)
struct ShinchanWalkScene: View {
    var phase: Int
    /// 小新的高度；小白按比例缩小
    var height: CGFloat
    var mood: String = "idle"
    /// 来回走动的幅度（pt）
    var travel: CGFloat = 0
    /// 是否绘制狗绳
    var showsLeash: Bool = true

    private var walk: Double {
        let p = Double(((phase % 12) + 12) % 12)
        return p / 12.0 * 2.0 * Double.pi
    }

    private var sway: CGFloat {
        travel == 0 ? 0 : CGFloat(sin(walk)) * travel
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ShinchanFigure(phase: phase, height: height, mood: mood)

            if showsLeash {
                LeashCurve()
                    .stroke(
                        ShinColor.leash,
                        style: StrokeStyle(lineWidth: max(1, height * 0.022), lineCap: .round)
                    )
                    .frame(width: height * 0.24, height: height * 0.14)
                    .offset(y: -height * 0.13)
            } else {
                Spacer().frame(width: height * 0.06)
            }

            ShiroFigure(phase: phase, height: height * 0.46, mood: mood)
        }
        .offset(x: sway)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("蜡笔小新正在遛狗")
    }
}

// MARK: - 锁屏 / 展开卡片

@available(iOS 16.1, *)
struct PetLockScreenView: View {
    let state: SignInActivityAttributes.ContentState

    private var headline: String {
        if state.statusText.contains("成功") { return "刚刚帮你签到成功啦～" }
        if state.statusText.contains("手动") { return "有个签到要你亲自来一下" }
        return SignInActivityKeys.slogan
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ShinchanWalkScene(
                phase: state.frame,
                height: 46,
                mood: state.mood,
                travel: 3
            )
            .frame(width: 66, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(SignInActivityKeys.petName)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(ShinColor.yellow)
                    Text("· 在后台值班")
                        .font(.caption2)
                        .foregroundColor(Color.white.opacity(0.55))
                }

                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 5) {
                    pill("托管 \(state.autoCount)", tint: ShinColor.red)
                    pill("定时 \(state.scheduledCount)", tint: ShinColor.yellow)
                    pill("手动 \(state.manualCount)", tint: Color.white.opacity(0.35))
                    pill("AI 答题 \(state.aiCount)", tint: Color(red: 0.35, green: 0.78, blue: 0.98))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func pill(_ text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(tint).frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.white.opacity(0.88))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule().fill(Color.white.opacity(0.12))
        )
    }
}

// MARK: - Widget

@available(iOS 16.1, *)
struct SignInActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SignInActivityAttributes.self) { context in
            PetLockScreenView(state: context.state)
                .activityBackgroundTint(Color(red: 0.06, green: 0.06, blue: 0.08))
                .activitySystemActionForegroundColor(Color.white)
                .widgetURL(URL(string: SignInActivityKeys.openURL))

        } dynamicIsland: { context in
            island(phase: context.state.frame, mood: context.state.mood)
        }
    }

    /// 灵动岛内容。单独写成普通函数，避免 @ViewBuilder 里出现 `let` / `return`。
    private func island(phase: Int, mood: String) -> DynamicIsland {
        DynamicIsland {
            // 展开：左侧小新 + 半截狗绳
            DynamicIslandExpandedRegion(.leading) {
                HStack(spacing: 0) {
                    ShinchanFigure(phase: phase, height: 30, mood: mood)
                    LeashCurve()
                        .stroke(
                            ShinColor.leash,
                            style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                        )
                        .frame(width: 9, height: 5)
                        .offset(y: -3)
                }
                .padding(.leading, 2)
            }

            // 展开：右侧半截狗绳 + 小白
            DynamicIslandExpandedRegion(.trailing) {
                HStack(spacing: 0) {
                    LeashCurve()
                        .stroke(
                            ShinColor.leash,
                            style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                        )
                        .frame(width: 9, height: 5)
                        .rotationEffect(.degrees(180))
                        .offset(y: -3)
                    ShiroFigure(phase: phase, height: 15, mood: mood)
                }
                .padding(.trailing, 2)
            }

            // 展开：底部标语
            DynamicIslandExpandedRegion(.bottom) {
                HStack(spacing: 6) {
                    Text(SignInActivityKeys.slogan)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("轻点回到 App")
                        .font(.system(size: 10))
                        .foregroundColor(ShinColor.yellow.opacity(0.9))
                }
                .padding(.horizontal, 2)
            }
        } compactLeading: {
            HStack(spacing: 0) {
                ShinchanFigure(phase: phase, height: 21, mood: mood)
                LeashCurve()
                    .stroke(
                        ShinColor.leash,
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .frame(width: 8, height: 4)
                    .offset(y: -2)
            }
            .offset(x: CGFloat(sin(Double(phase % 12) / 12.0 * 2 * Double.pi)) * 1.5)
        } compactTrailing: {
            HStack(spacing: 0) {
                LeashCurve()
                    .stroke(
                        ShinColor.leash,
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .frame(width: 8, height: 4)
                    .rotationEffect(.degrees(180))
                    .offset(y: -2)
                ShiroFigure(phase: phase, height: 14, mood: mood)
            }
            .offset(x: -CGFloat(sin(Double(phase % 12) / 12.0 * 2 * Double.pi)) * 1.5)
        } minimal: {
            ShinchanFigure(phase: phase, height: 18, mood: mood)
        }
        .widgetURL(URL(string: SignInActivityKeys.openURL))
        .keylineTint(ShinColor.yellow)
    }
}

/// Extension 侧兜底读取 App Group 数据（活动状态异常时用于降级展示）。
@available(iOS 16.1, *)
func readSharedState() -> SignInActivityAttributes.ContentState {
    let defaults = UserDefaults(suiteName: SignInActivityKeys.appGroup)
    return SignInActivityAttributes.ContentState(
        statusText: defaults?.string(forKey: "live_status_text") ?? SignInActivityKeys.slogan,
        signedAccounts: defaults?.string(forKey: "live_signed_accounts") ?? "",
        autoCount: defaults?.integer(forKey: "live_auto_count") ?? 0,
        scheduledCount: defaults?.integer(forKey: "live_scheduled_count") ?? 0,
        manualCount: defaults?.integer(forKey: "live_manual_count") ?? 0,
        aiCount: defaults?.integer(forKey: "live_ai_count") ?? 0,
        mood: defaults?.string(forKey: "live_mood") ?? "idle",
        signedCount: defaults?.integer(forKey: "live_signed_count") ?? 0,
        frame: defaults?.integer(forKey: "live_frame") ?? 0
    )
}
