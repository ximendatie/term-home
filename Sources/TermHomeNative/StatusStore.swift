import Foundation
import SwiftUI

/// 原生壳层支持的界面级任务状态。
enum TaskPhase: String {
    case idle
    case running
    case awaitingApproval = "awaiting_approval"
    case completed
    case failed

    /// 将任务状态映射为胶囊上的强调色。
    var color: Color {
        switch self {
        case .idle:
            return Color.gray.opacity(0.8)
        case .running:
            return Color.blue
        case .awaitingApproval:
            return Color.orange
        case .completed:
            return Color.green
        case .failed:
            return Color.red
        }
    }

    /// 将任务状态映射为面向用户的状态文案。
    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .awaitingApproval:
            return "Needs approval"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
}

/// Python 事件总线快照接口返回的任务结构。
struct RemoteTask: Decodable, Identifiable {
    let taskID: String
    let source: String
    let status: String
    let title: String
    let summary: String
    let progress: Int?
    let updatedAt: Double
    let logs: [String]

    var id: String { taskID }
    var phase: TaskPhase { TaskPhase(status: status) }

    /// 将 snake_case 的接口字段映射为 Swift 风格属性名。
    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case source
        case status
        case title
        case summary
        case progress
        case updatedAt = "updated_at"
        case logs
    }
}

/// `GET /tasks` 返回的顶层响应结构。
struct TasksSnapshot: Decodable {
    let tasks: [RemoteTask]
}

/// 总线 SSE 更新中携带的最小事件包结构。
struct StreamEnvelope: Decodable {
    let task: RemoteTask?
}

/// 已解析的 SSE 消息，包含可选事件名和原始数据。
struct StreamMessage {
    let event: String?
    let data: String
}

/// 用于读取快照、订阅流和发送动作的轻量总线客户端。
struct EventBusClient {
    let baseURL = URL(string: "http://127.0.0.1:8765")!

    /// 从本地总线读取最新的完整任务快照。
    func fetchSnapshot() async throws -> TasksSnapshot {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appending(path: "tasks"))
        return try JSONDecoder().decode(TasksSnapshot.self, from: data)
    }

    /// 打开一个长连接 SSE 流以接收实时任务更新。
    func streamEvents() -> AsyncThrowingStream<StreamMessage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var request = URLRequest(url: baseURL.appending(path: "stream"))
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                var currentEvent: String?
                var dataLines: [String] = []

                for try await rawLine in bytes.lines {
                    let line = String(rawLine)
                    if line.isEmpty {
                        if !dataLines.isEmpty {
                            continuation.yield(
                                StreamMessage(
                                    event: currentEvent,
                                    data: dataLines.joined(separator: "\n")
                                )
                            )
                        }
                        currentEvent = nil
                        dataLines.removeAll(keepingCapacity: true)
                        continue
                    }

                    if line.hasPrefix("event:") {
                        currentEvent = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                        continue
                    }

                    if line.hasPrefix("data:") {
                        let data = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        dataLines.append(data)
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 将当前任务上的用户动作回写到本地总线。
    func postAction(taskID: String, action: String) async throws {
        var request = URLRequest(
            url: baseURL.appending(path: "tasks").appending(path: taskID).appending(path: "actions")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["action": action])
        _ = try await URLSession.shared.data(for: request)
    }
}

/// 让原生壳层与本地事件总线保持同步的主界面状态存储。
@MainActor
final class StatusStore: ObservableObject {
    @Published var phase: TaskPhase = .idle
    @Published var title = "term-home"
    @Published var summary = "Waiting for the local event bus."
    @Published var isExpanded = false
    @Published var recentTasks: [RemoteTask] = []

    var onLayoutChange: (() -> Void)?

    private let client = EventBusClient()
    private var streamTask: Task<Void, Never>?
    private var currentTaskID: String?

    /// 启动初始快照拉取，并建立长连接 SSE 订阅。
    init() {
        connect()
    }

    deinit {
        streamTask?.cancel()
    }

    /// 切换胶囊展开状态，并通知窗口重新布局。
    func toggleExpanded() {
        isExpanded.toggle()
        onLayoutChange?()
    }

    /// 为当前活动任务发送批准动作。
    func approve() {
        performAction("approve", fallback: "No active task to approve.")
    }

    /// 为当前活动任务发送拒绝动作。
    func reject() {
        performAction("reject", fallback: "No active task to reject.")
    }

    /// 为当前活动任务发送重试动作。
    func retry() {
        performAction("retry", fallback: "No active task to retry.")
    }

    /// 标记当前界面是否存在可执行动作的活动任务。
    var hasActiveTask: Bool {
        currentTaskID != nil
    }

    /// 连接事件总线、维持 SSE 长连接，并在断开后自动重试。
    private func connect() {
        streamTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await refreshSnapshot()
                    for try await message in client.streamEvents() {
                        handleStreamMessage(message)
                    }
                } catch {
                    handleDisconnect()
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// 拉取最新完整快照并应用到界面状态。
    private func refreshSnapshot() async throws {
        let snapshot = try await client.fetchSnapshot()
        applySnapshot(snapshot)
    }

    /// 将总线返回的完整快照应用到当前界面状态。
    private func applySnapshot(_ snapshot: TasksSnapshot) {
        recentTasks = Array(snapshot.tasks.prefix(3))

        if let current = snapshot.tasks.first {
            applyCurrentTask(current)
        } else {
            currentTaskID = nil
            phase = .idle
            title = "term-home"
            summary = "No active tasks from the local event bus."
        }
    }

    /// 处理一条来自总线的 SSE 消息，包括快照和增量任务更新。
    private func handleStreamMessage(_ message: StreamMessage) {
        let decoder = JSONDecoder()

        if message.event == "snapshot",
           let data = message.data.data(using: .utf8),
           let snapshot = try? decoder.decode(TasksSnapshot.self, from: data) {
            applySnapshot(snapshot)
            return
        }

        guard let data = message.data.data(using: .utf8),
              let envelope = try? decoder.decode(StreamEnvelope.self, from: data),
              let task = envelope.task
        else {
            return
        }

        mergeTask(task)
    }

    /// 将增量任务更新合并到最近任务列表和当前任务头部状态。
    private func mergeTask(_ task: RemoteTask) {
        var tasks = recentTasks.filter { $0.taskID != task.taskID }
        tasks.insert(task, at: 0)
        recentTasks = Array(tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(3))

        if recentTasks.first?.taskID == task.taskID {
            applyCurrentTask(task)
        }
    }

    /// 将顶部任务同步到胶囊头部的显著展示状态。
    private func applyCurrentTask(_ task: RemoteTask) {
        currentTaskID = task.taskID
        phase = task.phase
        title = task.title
        summary = task.summary.isEmpty ? "No summary yet." : task.summary
    }

    /// 在无法连接事件总线时应用清晰的离线兜底状态。
    private func handleDisconnect() {
        currentTaskID = nil
        recentTasks = []
        phase = .idle
        title = "term-home"
        summary = "Event bus offline at http://127.0.0.1:8765."
    }

    /// 向总线发送动作，并由后续实时流更新界面状态。
    private func performAction(_ action: String, fallback: String) {
        guard let currentTaskID else {
            summary = fallback
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.postAction(taskID: currentTaskID, action: action)
            } catch {
                await MainActor.run {
                    self.summary = "Failed to send \(action) to the local event bus."
                }
            }
        }
    }
}

extension TaskPhase {
    /// 将事件总线里的任务状态归一化到壳层使用的较小状态集合。
    init(status: String) {
        switch status {
        case "running":
            self = .running
        case "awaiting_approval":
            self = .awaitingApproval
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        default:
            self = .idle
        }
    }
}
