# Spec: core-mvp

## 背景

根据根目录 `README.md`，`term-home` 的工程目标是：
- 提供 macOS 顶部状态层（notch / live island 风格）。
- 提供统一 CLI/Agent 事件总线。
- 让长任务、审批、失败、重试等动作可见、可控。

并参考：
- https://github.com/farouqaldori/claude-island（快速落地实践）
- https://github.com/TheBoredTeam/boring.notch（友好 UI 风格）

## 版本目标（V0 / Core）

以“先落地核心功能”为原则，V0 只交付最小闭环：

1. 统一事件协议与事件接入 API。
2. 任务状态机（running/completed/failed/awaiting_approval/cancelled）。
3. 顶部状态层（Web 形态模拟 notch UI）。
4. 人工动作入口（stop/retry/approve/reject）。
5. 本地单机可运行、可演示。

## 非目标（V0 不做）

- 原生 macOS App（SwiftUI）与系统级浮层。
- 多用户鉴权与云端同步。
- 复杂插件系统。
- 全量持久化数据库。

## 事件契约（V0）

必填字段：
- `type`: 事件类型
- `task_id`: 任务唯一标识

可选字段：
- `source`, `title`, `summary`, `progress`, `line`

事件类型：
- `task.started`
- `task.progress`
- `task.summary`
- `task.awaiting_approval`
- `task.completed`
- `task.failed`
- `task.cancelled`
- `task.log`

## 验收标准

- 启动服务后可以通过 `/events` 写入任务事件。
- UI 能实时展示最新任务状态与摘要。
- 在 UI 点击动作按钮后，任务状态会发生对应变化。
- `/tasks` 能返回结构化任务快照。
- `/stream` 以 SSE 提供增量更新。
