import SwiftUI

struct CapsuleRootView: View {
    @ObservedObject var store: StatusStore

    var body: some View {
        capsuleBody
    }

    private var capsuleBody: some View {
        VStack(spacing: 0) {
            headerButton

            if store.isExpanded {
                expandedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: store.isExpanded ? 24 : 999, style: .continuous)
                .fill(.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: store.isExpanded ? 24 : 999, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(6)
    }

    private var headerButton: some View {
        Button(action: store.toggleExpanded) {
            HStack(spacing: 10) {
                Circle()
                    .fill(store.phase.color)
                    .frame(width: 10, height: 10)

                Text(store.title)
                    .font(.system(size: 14, weight: .semibold))

                Text(store.phase.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Image(systemName: store.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 14) {
                currentTaskSection
                actionRow

                if !store.recentTasks.isEmpty {
                    recentTasksSection
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var currentTaskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current task")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(store.summary)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            ActionButton(title: "Approve", tint: .green, action: store.approve)
                .disabled(!store.hasActiveTask)
            ActionButton(title: "Reject", tint: .red, action: store.reject)
                .disabled(!store.hasActiveTask)
            ActionButton(title: "Retry", tint: .blue, action: store.retry)
                .disabled(!store.hasActiveTask)
        }
    }

    private var recentTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent tasks")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(store.recentTasks) { task in
                RecentTaskRow(task: task)
            }
        }
    }
}

private struct ActionButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(tint.opacity(0.35), lineWidth: 1)
                    )
            )
    }
}

private struct RecentTaskRow: View {
    let task: RemoteTask

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(task.phase.color)
                .frame(width: 8, height: 8)

            Text(task.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(task.phase.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
