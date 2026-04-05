import SwiftUI

enum TaskPhase: String {
    case idle
    case running
    case awaitingApproval = "awaiting_approval"
    case completed
    case failed

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

struct TasksSnapshot: Decodable {
    let tasks: [RemoteTask]
}

struct EventBusClient {
    let baseURL = URL(string: "http://127.0.0.1:8765")!

    func fetchSnapshot() async throws -> TasksSnapshot {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appending(path: "tasks"))
        return try JSONDecoder().decode(TasksSnapshot.self, from: data)
    }

    func postAction(taskID: String, action: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "tasks").appending(path: taskID).appending(path: "actions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["action": action])
        _ = try await URLSession.shared.data(for: request)
    }
}

@MainActor
final class StatusStore: ObservableObject {
    @Published var phase: TaskPhase = .idle
    @Published var title = "term-home"
    @Published var summary = "Waiting for the local event bus."
    @Published var isExpanded = false
    @Published var recentTasks: [RemoteTask] = []

    var onLayoutChange: (() -> Void)?

    private let client = EventBusClient()
    private var pollingTask: Task<Void, Never>?
    private var currentTaskID: String?

    init() {
        startPolling()
    }

    deinit {
        pollingTask?.cancel()
    }

    func toggleExpanded() {
        isExpanded.toggle()
        onLayoutChange?()
    }

    func approve() {
        performAction("approve", fallback: "No active task to approve.")
    }

    func reject() {
        performAction("reject", fallback: "No active task to reject.")
    }

    func retry() {
        performAction("retry", fallback: "No active task to retry.")
    }

    var hasActiveTask: Bool {
        currentTaskID != nil
    }

    private func startPolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() async {
        do {
            let snapshot = try await client.fetchSnapshot()
            recentTasks = Array(snapshot.tasks.prefix(3))

            if let current = snapshot.tasks.first {
                currentTaskID = current.taskID
                phase = TaskPhase(status: current.status)
                title = current.title
                summary = current.summary.isEmpty ? "No summary yet." : current.summary
            } else {
                currentTaskID = nil
                phase = .idle
                title = "term-home"
                summary = "No active tasks from the local event bus."
            }
        } catch {
            currentTaskID = nil
            recentTasks = []
            phase = .idle
            title = "term-home"
            summary = "Event bus offline at http://127.0.0.1:8765."
        }
    }

    private func performAction(_ action: String, fallback: String) {
        guard let currentTaskID else {
            summary = fallback
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.postAction(taskID: currentTaskID, action: action)
                await refresh()
            } catch {
                await MainActor.run {
                    self.summary = "Failed to send \(action) to the local event bus."
                }
            }
        }
    }
}

extension TaskPhase {
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
