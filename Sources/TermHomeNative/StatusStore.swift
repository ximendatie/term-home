import Foundation
import SwiftUI

/// 原生壳层支持的界面级任务状态。
enum TaskPhase: String {
    case idle
    case running
    case awaitingApproval = "awaiting_approval"
    case completed
    case failed
    case cancelled

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
        case .cancelled:
            return Color.gray.opacity(0.72)
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
        case .cancelled:
            return "Cancelled"
        }
    }
}

/// Python 事件总线快照接口返回的任务结构。
struct RemoteTask: Decodable, Identifiable {
    let taskID: String
    let sessionID: String
    let terminalApp: String
    let tty: String
    let cwd: String
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
        case sessionID = "session_id"
        case terminalApp = "terminal_app"
        case tty
        case cwd
        case source
        case status
        case title
        case summary
        case progress
        case updatedAt = "updated_at"
        case logs
    }

    /// 兼容旧任务快照中缺失的新字段，避免一次 schema 增量导致整个列表解码失败。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try container.decode(String.self, forKey: .taskID)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        terminalApp = try container.decodeIfPresent(String.self, forKey: .terminalApp) ?? ""
        tty = try container.decodeIfPresent(String.self, forKey: .tty) ?? ""
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        source = try container.decode(String.self, forKey: .source)
        status = try container.decode(String.self, forKey: .status)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        progress = try container.decodeIfPresent(Int.self, forKey: .progress)
        updatedAt = try container.decode(Double.self, forKey: .updatedAt)
        logs = try container.decodeIfPresent([String].self, forKey: .logs) ?? []
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
    @Published var currentTask: RemoteTask?

    var onLayoutChange: (() -> Void)?

    private let client = EventBusClient()
    private var streamTask: Task<Void, Never>?
    private var currentTaskID: String?
    private var lastExpandedAt: Date?

    /// 启动初始快照拉取，并建立长连接 SSE 订阅。
    init() {
        connect()
    }

    deinit {
        streamTask?.cancel()
    }

    /// 展开胶囊，并通知窗口重新布局。
    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        lastExpandedAt = Date()
        onLayoutChange?()
        Task { [weak self] in
            guard let self else { return }
            try? await self.refreshSnapshot()
        }
    }

    /// 收起胶囊，并通知窗口重新布局。
    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        onLayoutChange?()
    }

    /// 在需要时切换胶囊展开状态，并通知窗口重新布局。
    func toggleExpanded() {
        isExpanded.toggle()
        if isExpanded {
            lastExpandedAt = Date()
        }
        onLayoutChange?()
    }

    /// 判断当前是否处于刚展开后的短暂保护期，避免被瞬时失焦误收起。
    func shouldIgnoreImmediateCollapse(now: Date = Date()) -> Bool {
        guard let lastExpandedAt else { return false }
        return now.timeIntervalSince(lastExpandedAt) < 0.18
    }

    /// 根据当前状态返回更贴近留海形态的首选窗口尺寸。
    var preferredPanelSize: NSSize {
        if !isExpanded {
            return NSSize(width: 320, height: 36)
        }

        let taskCount = min(recentTasks.count, 3)
        let recentTasksHeight = CGFloat(taskCount) * 42
        let baseHeight: CGFloat = 138
        let totalHeight = baseHeight + recentTasksHeight
        return NSSize(width: 480, height: max(272, totalHeight))
    }

    /// 判断任务是否具备足够的终端元信息，支持回跳到原 tab。
    func canOpenInTerminal(_ task: RemoteTask) -> Bool {
        !task.tty.isEmpty && !task.terminalApp.isEmpty
    }

    /// 按任务携带的终端元信息尝试回跳到原始 terminal tab/session。
    func openInTerminal(_ task: RemoteTask) {
        guard canOpenInTerminal(task) else { return }

        let script = appleScriptForTerminalJump(task: task)
        guard !script.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
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
        onLayoutChange?()

        if let current = preferredTask(from: snapshot.tasks) {
            applyCurrentTask(current)
        } else {
            currentTaskID = nil
            currentTask = nil
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
        onLayoutChange?()

        if let current = preferredTask(from: recentTasks),
           current.taskID == task.taskID {
            applyCurrentTask(current)
        }
    }

    /// 从快照中挑出最值得放到顶部主位的任务，避免被合成动作长期污染。
    private func preferredTask(from tasks: [RemoteTask]) -> RemoteTask? {
        tasks.sorted { lhs, rhs in
            taskPriority(lhs) > taskPriority(rhs)
        }.first
    }

    /// 给任务分配排序权重，优先展示真实来源的待处理任务。
    private func taskPriority(_ task: RemoteTask) -> (Int, Double) {
        let sourcePenalty = task.source == "term-home-ui" ? 1 : 0

        switch task.phase {
        case .awaitingApproval:
            return (500 - sourcePenalty, task.updatedAt)
        case .running:
            return (400 - sourcePenalty, task.updatedAt)
        case .failed:
            return (300 - sourcePenalty, task.updatedAt)
        case .completed:
            return (200 - sourcePenalty, task.updatedAt)
        case .cancelled:
            return (180 - sourcePenalty, task.updatedAt)
        case .idle:
            return (100 - sourcePenalty, task.updatedAt)
        }
    }

    /// 将顶部任务同步到胶囊头部的显著展示状态。
    private func applyCurrentTask(_ task: RemoteTask) {
        currentTaskID = task.taskID
        currentTask = task
        phase = task.phase
        title = task.title
        summary = task.summary.isEmpty ? "No summary yet." : task.summary
    }

    /// 在无法连接事件总线时应用清晰的离线兜底状态。
    private func handleDisconnect() {
        currentTaskID = nil
        currentTask = nil
        recentTasks = []
        phase = .idle
        title = "term-home"
        summary = "Event bus offline at http://127.0.0.1:8765."
        onLayoutChange?()
    }

    /// 按已知 terminal 类型生成对应的 AppleScript 回跳脚本。
    private func appleScriptForTerminalJump(task: RemoteTask) -> String {
        let escapedTTY = task.tty.replacingOccurrences(of: "\"", with: "\\\"")

        if task.terminalApp == "Apple_Terminal" || task.terminalApp == "Terminal" {
            return """
            set targetTTY to "\(escapedTTY)"
            tell application "Terminal"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is targetTTY then
                            set selected tab of w to t
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        }

        if task.terminalApp == "iTerm.app" || task.terminalApp == "iTerm2" || task.terminalApp == "iTerm" {
            return """
            set targetTTY to "\(escapedTTY)"
            tell application id "com.googlecode.iterm2"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is targetTTY then
                                select t
                                set index of w to 1
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        }

        return ""
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
        case "cancelled":
            self = .cancelled
        default:
            self = .idle
        }
    }
}
