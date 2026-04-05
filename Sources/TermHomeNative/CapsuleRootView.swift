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
        store.isExpanded ? islandCornerInsets.expanded.top : 12
    }

    /// 统一控制头部可见高度，避免把整块展开高度错误分配给 header。
    private var headerHeight: CGFloat {
        store.isExpanded ? 44 : panelSize.height
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
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .frame(height: headerHeight)

            if store.isExpanded {
                expandedContent
                    .frame(width: panelSize.width - 24, alignment: .leading)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .top)
                                .combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding([.horizontal, .bottom], bottomInset)
        .frame(width: panelSize.width, height: panelSize.height, alignment: .top)
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
        .contentShape(Rectangle())
        .onTapGesture {
            if !store.isExpanded {
                store.expand()
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: store.isExpanded)
        .animation(.smooth, value: store.phase)
        .animation(.smooth, value: store.recentTasks.map(\.id))
    }

    /// 构建靠两侧安全区分布的头部，避免把内容压到留海中央。
    private var headerRow: some View {
        HStack(spacing: 0) {
            if !store.isExpanded {
                compactLeadingSlot
                Spacer(minLength: 0)
                headerCompactCenter
                Spacer(minLength: 0)
                compactTrailingSlot
            } else {
                headerLeading
                Spacer(minLength: 0)
                headerTrailing
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, store.isExpanded ? 11 : 8)
        .padding(.horizontal, store.isExpanded ? 18 : 18)
    }

    /// 渲染左上角的品牌和状态元素。
    private var headerLeading: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .font(.system(size: store.isExpanded ? 12 : 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))

            if store.isExpanded {
                Circle()
                    .fill(store.phase.color)
                    .frame(width: 8, height: 8)
            }
        }
    }

    /// 为收起态左侧保留稳定宽度，让中间状态槽更像岛体本体的一部分。
    private var compactLeadingSlot: some View {
        headerLeading
            .frame(width: 44, alignment: .leading)
    }

    /// 为收起态右侧保留稳定宽度，让中间状态槽保持居中。
    private var compactTrailingSlot: some View {
        headerTrailing
            .frame(width: 44, alignment: .trailing)
    }

    /// 渲染收起态中间的状态槽，强化“灵动岛存在”而不是普通小控件。
    private var headerCompactCenter: some View {
        HStack(spacing: 10) {
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
                .frame(width: 74, height: 16)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(store.phase.color)
                        .frame(width: 8, height: 8)
                        .padding(.leading, 5)
                }

            Text(store.phase == .idle ? "Idle" : store.phase.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
        }
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
                .frame(width: store.isExpanded ? 8 : 9, height: store.isExpanded ? 8 : 9)

            if store.phase != .idle {
                Circle()
                    .stroke(store.phase.color.opacity(0.35), lineWidth: 1.2)
                    .frame(width: store.isExpanded ? 12 : 13, height: store.isExpanded ? 12 : 13)
            }
        }
        .frame(width: 18, height: 18)
    }

    /// 渲染展开态主体内容，包括当前任务、动作区和最近任务。
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            currentTaskSection

            if store.hasActiveTask {
                actionRow
                    .padding(.top, 20)
            }

            recentTasksSection
                .padding(.top, store.hasActiveTask ? 22 : 18)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    /// 渲染当前任务概览，优先突出标题与状态。
    private var currentTaskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("当前任务")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text(store.phase.label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(store.phase.color)
            }

            Text(store.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(store.summary)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
        }
    }

    /// 渲染当前任务的核心动作按钮。
    private var actionRow: some View {
        HStack(spacing: 12) {
            ActionPillButton(title: "允许", tint: .green.opacity(0.28), stroke: .green.opacity(0.7)) {
                store.approve()
            }

            ActionPillButton(title: "拒绝", tint: .red.opacity(0.18), stroke: .red.opacity(0.52)) {
                store.reject()
            }

            ActionPillButton(title: "重试", tint: .blue.opacity(0.2), stroke: .blue.opacity(0.62)) {
                store.retry()
            }
        }
    }

    /// 渲染最近任务列表，保持紧凑的展开态节奏。
    private var recentTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近任务")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))

            if store.recentTasks.isEmpty {
                Text("还没有最近任务。")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                VStack(spacing: 12) {
                    ForEach(store.recentTasks.prefix(3)) { task in
                        recentTaskRow(task)
                    }
                }
            }
        }
    }

    /// 渲染单条最近任务，保证信息密度接近参考实现。
    private func recentTaskRow(_ task: RemoteTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(task.phase.color.opacity(0.9))
                .frame(width: 9, height: 9)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)

                Text(task.summary.isEmpty ? task.phase.label : task.summary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.top, 5)
        }
    }
}

/// 统一渲染展开态操作区的胶囊按钮。
private struct ActionPillButton: View {
    let title: String
    let tint: Color
    let stroke: Color
    let action: () -> Void

    /// 创建一个带描边和半透明底色的胶囊按钮。
    init(title: String, tint: Color, stroke: Color, action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.stroke = stroke
        self.action = action
    }

    /// 绘制按钮视觉样式，并保持与岛体整体风格一致。
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 42)
                .background(tint)
                .overlay {
                    Capsule()
                        .stroke(stroke, lineWidth: 1.5)
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
