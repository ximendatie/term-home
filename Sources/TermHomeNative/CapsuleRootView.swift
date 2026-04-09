import SwiftUI

/// 留海两种形态下使用的圆角参数。
private let islandCornerInsets = (
    expanded: (top: CGFloat(19), bottom: CGFloat(24)),
    compact: (top: CGFloat(6), bottom: CGFloat(14))
)

/// 复刻 `claude-island` 轮廓思路的岛体形状。
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    /// 创建用于收起态或展开态的岛体轮廓。
    init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 14) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    /// 让顶部和底部圆角在状态切换时保持平滑插值。
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    /// 按参考仓库的二次曲线路径绘制岛体轮廓。
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        path.addLine(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius)
        )

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        path.addLine(
            to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY)
        )

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        path.addLine(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius)
        )

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

/// 原生顶部岛体主视图，负责收起态与展开态的统一骨架。
struct CapsuleRootView: View {
    @ObservedObject var store: StatusStore
    @State private var expandedRecentSessionID: String?

    /// 返回当前状态下的顶部内圆角半径。
    private var topCornerRadius: CGFloat {
        store.isExpanded ? islandCornerInsets.expanded.top : islandCornerInsets.compact.top
    }

    /// 返回当前状态下的底部外圆角半径。
    private var bottomCornerRadius: CGFloat {
        store.isExpanded ? islandCornerInsets.expanded.bottom : islandCornerInsets.compact.bottom
    }

    /// 返回与当前状态一致的岛体轮廓。
    private var currentShape: NotchShape {
        NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
    }

    /// 返回当前状态下岛体两侧的安全区边距。
    private var horizontalInset: CGFloat {
        store.isExpanded ? islandCornerInsets.expanded.top : islandCornerInsets.compact.bottom
    }

    /// 统一控制头部可见高度，避免把整块展开高度错误分配给 header。
    private var headerHeight: CGFloat {
        max(24, compactHeight)
    }

    /// 头部始终基于收起态高度计算，避免展开后左右槽位被放大。
    private var compactHeight: CGFloat {
        36
    }

    /// 复用参考仓库的 side slot 宽度计算方式，锁定左右角标的边距感知。
    private var sideWidth: CGFloat {
        max(0, compactHeight - 12) + 10
    }

    /// 计算收起态中心段宽度，避免中间内容挤压左右边距。
    private var compactCenterWidth: CGFloat {
        max(0, panelSize.width - sideWidth * 2)
    }

    /// 统一控制展开态底部留白，使内容和外轮廓保持稳定距离。
    private var bottomInset: CGFloat {
        store.isExpanded ? 12 : 0
    }

    /// 返回收起态和展开态共同使用的外层尺寸。
    private var panelSize: NSSize {
        store.preferredPanelSize
    }

    /// 组合收起态和展开态，始终贴齐屏幕顶部绘制。
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                islandBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    /// 构建与 `claude-island` 同一思路的岛体骨架。
    private var islandBody: some View {
        notchLayout
            .frame(maxWidth: store.isExpanded ? panelSize.width : nil, alignment: .top)
            .padding(
                .horizontal,
                store.isExpanded ? islandCornerInsets.expanded.top : islandCornerInsets.compact.bottom
            )
            .padding([.horizontal, .bottom], store.isExpanded ? 12 : 0)
            .background(Color.black)
            .clipShape(currentShape)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)
                    .padding(.horizontal, topCornerRadius)
            }
            .overlay {
                if !store.isExpanded {
                    currentShape
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
            .shadow(
                color: store.isExpanded ? Color.black.opacity(0.72) : Color.black.opacity(0.28),
                radius: store.isExpanded ? 8 : 4,
                y: store.isExpanded ? 2 : 1
            )
            .frame(
                maxWidth: store.isExpanded ? panelSize.width : nil,
                maxHeight: store.isExpanded ? panelSize.height : nil,
                alignment: .top
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if !store.isExpanded {
                    store.expand()
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: store.isExpanded)
    }

    /// 使用和参考仓库一致的单列骨架，头部始终存在，展开态只追加主体内容。
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .frame(height: max(24, compactHeight))

            if store.isExpanded {
                expandedContent
                    .frame(width: panelSize.width - 24, alignment: .leading)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.18)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    /// 构建靠两侧安全区分布的头部，直接复用参考仓库的单行槽位思路。
    private var headerRow: some View {
        HStack(spacing: 0) {
            headerLeading
                .frame(width: sideWidth, alignment: .center)

            Group {
                if store.isExpanded {
                    Spacer(minLength: 0)
                } else {
                    headerCompactCenter
                        .frame(width: compactCenterWidth)
                }
            }

            headerTrailing
                .frame(width: sideWidth, alignment: .center)
        }
        .frame(height: compactHeight)
    }

    /// 渲染左上角的品牌和状态元素。
    private var headerLeading: some View {
        Image(systemName: "terminal.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
    }

    /// 渲染收起态中间的状态槽，强化“灵动岛存在”而不是普通小控件。
    private var headerCompactCenter: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.white.opacity(0.015)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 132, height: 16)
            .padding(.horizontal, 10)
        .frame(height: 22)
        .background(Color.white.opacity(0.03))
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
        .clipShape(Capsule())
    }

    /// 渲染右上角的控制元素，保持与参考实现相同的角落占位思路。
    private var headerTrailing: some View {
        ZStack {
            Circle()
                .fill(store.phase.color.opacity(store.phase == .idle ? 0.42 : 0.92))
                .frame(width: 9, height: 9)

            if store.phase != .idle {
                Circle()
                    .stroke(store.phase.color.opacity(0.35), lineWidth: 1.2)
                    .frame(width: 13, height: 13)
            }
        }
        .frame(width: 18, height: 18)
    }

    /// 渲染展开态主体内容，只保留状态、标题、详情和最近任务。
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            currentTaskSection
            recentTasksSection
                .padding(.top, 18)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    /// 渲染当前任务概览，使用接近 Terminal 的文字层级突出标题与详情。
    private var currentTaskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("status")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))

                Text(store.phase.label)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(store.phase.color)

                Spacer(minLength: 8)

                if let currentTask = store.currentTask,
                   store.canOpenInTerminal(currentTask) {
                    TerminalJumpButton(isEnabled: true) {
                        store.openInTerminal(currentTask)
                    }
                }
            }

            Text(store.title)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(store.summary)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(3)
        }
    }

    /// 渲染按 session 聚合后的最近列表，避免同一 tab 下多条命令挤占空间。
    private var recentTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("terminal list")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.74))

            if store.recentSessions.isEmpty {
                Text("No recent tasks.")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                VStack(spacing: 12) {
                    ForEach(store.recentSessions.prefix(3)) { session in
                        recentTaskRow(session)
                    }
                }
            }
        }
    }

    /// 渲染单条最近 session，列表标题跟随该 tab 最近执行的任务。
    private func recentTaskRow(_ session: RemoteSessionSummary) -> some View {
        RecentTaskCard(
            session: session,
            isExpanded: expandedRecentSessionID == session.id,
            canJump: store.canOpenInTerminal(session.latestTask),
            onToggle: {
                if expandedRecentSessionID == session.id {
                    expandedRecentSessionID = nil
                } else {
                    expandedRecentSessionID = session.id
                }
            },
            onJump: {
                store.openInTerminal(session.latestTask)
            }
        )
    }
}

/// 统一渲染“回跳原始终端”按钮，提供一致的 hover 与 press 反馈。
private struct TerminalJumpButton: View {
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    /// 创建用于当前任务区和最近任务区的统一回跳按钮。
    init(isEnabled: Bool, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    /// 绘制带 hover 和按压反馈的回跳图标按钮。
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 26, height: 22)
                .background(backgroundColor)
                .overlay {
                    Capsule()
                        .stroke(borderColor, lineWidth: 1)
                }
                .clipShape(Capsule())
                .scaleEffect(isHovered && isEnabled ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    /// 根据状态返回更容易感知的图标颜色。
    private var iconColor: Color {
        return .white.opacity(0.96)
    }

    /// 根据状态返回按钮底色，强化 hover 的存在感。
    private var backgroundColor: Color {
        return isHovered ? .blue.opacity(0.28) : .white.opacity(0.09)
    }

    /// 为按钮补稳定轮廓，避免 disabled 时几乎看不见。
    private var borderColor: Color {
        return isHovered ? .blue.opacity(0.72) : .white.opacity(0.18)
    }
}

/// 渲染最近任务卡片，整行负责展开 detail，箭头单独负责回跳 terminal。
private struct RecentTaskCard: View {
    let session: RemoteSessionSummary
    let isExpanded: Bool
    let canJump: Bool
    let onToggle: () -> Void
    let onJump: () -> Void

    @State private var isHovered = false

    /// 创建一条同时具备详情展开和 terminal 回跳能力的最近任务卡片。
    init(
        session: RemoteSessionSummary,
        isExpanded: Bool,
        canJump: Bool,
        onToggle: @escaping () -> Void,
        onJump: @escaping () -> Void
    ) {
        self.session = session
        self.isExpanded = isExpanded
        self.canJump = canJump
        self.onToggle = onToggle
        self.onJump = onJump
    }

    /// 绘制整行 hover 高亮、detail 展开和箭头回跳的组合交互。
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(session.phase.color.opacity(0.9))
                .frame(width: 9, height: 9)
                .padding(.top, 7)

            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)

                    Text(session.detail)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(isExpanded ? 6 : 2)

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 3) {
                            if !session.phase.label.isEmpty {
                                detailRow(label: "status", value: session.phase.label)
                            }
                            if !session.latestTask.source.isEmpty {
                                detailRow(label: "source", value: session.latestTask.source)
                            }
                            if !session.latestTask.cwd.isEmpty {
                                detailRow(label: "cwd", value: session.latestTask.cwd)
                            }
                            if !session.latestTask.tty.isEmpty {
                                detailRow(label: "tty", value: session.latestTask.tty)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if canJump {
                TerminalJumpButton(isEnabled: true, action: onJump)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .animation(.easeOut(duration: 0.18), value: isExpanded)
    }

    /// 渲染展开态中的明细键值对，保持 Terminal 风格的信息密度。
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.38))
                .frame(width: 42, alignment: .leading)

            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(3)
        }
    }

    /// 根据 hover 与展开状态返回更明显的整行高亮背景。
    private var rowBackground: Color {
        if isExpanded {
            return .white.opacity(0.16)
        }
        if isHovered {
            return .white.opacity(0.14)
        }
        return .white.opacity(0.05)
    }
}
