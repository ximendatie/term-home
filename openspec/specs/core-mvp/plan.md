# Plan: core-mvp

## 实施策略

采用“原型验证先行，再收敛到原生 MVP”的路径。

## 已完成阶段（V0 / Core Prototype）

### Phase 1 — Event Bus
- 实现 HTTP 事件接入 `/events`。
- 实现内存态任务模型。
- 实现状态归一化逻辑。

### Phase 2 — Runtime Read APIs
- 提供 `/tasks` 快照读取。
- 提供 `/stream` SSE 订阅。

### Phase 3 — Top Layer UI
- 提供最小事件观察与动作验证方式。
- 验证状态流转与 SSE 推送。
- 验证 stop/retry/approve/reject 动作映射。

### Phase 4 — Demo & docs
- 补充运行说明。
- 提供最小事件注入样例。

## 下一阶段（V1 / Native MVP）

### Phase 5 — Native Shell
- 建立原生 macOS app 壳层。
- 实现顶部收起态与展开态。
- 以原生 UI 替代临时原型层，作为正式 MVP 载体。

### Phase 6 — Native Runtime Integration
- 复用或替换当前事件总线，使原生 app 能消费真实事件。
- 优先使用 SSE 长连接同步状态，避免持续轮询。
- 保留最小任务状态与最近任务数据。
- 建立错误、断连、空状态兜底。

### Phase 7 — First Real Workflow
- 接入 1 个真实 CLI / Agent。
- 跑通 `running -> completed/failed/cancelled` 的稳定状态闭环。
- 完成原生形态下的最小监测验证。

### Phase 7.2 — Additional CLI Bridges
- 在保留统一事件契约的前提下，扩展更多可脚本化 CLI。
- 优先接入支持一次性结构化输出的 CLI，降低 bridge 复杂度。
- 对不同 CLI 的输出能力分层：能流式就映射进度，只能一次性输出就先保证完成态闭环。
- 沉淀统一 bridge adapter 抽象，降低后续接入新 CLI 时的代码重复。
- 增加通用命令包装器，先覆盖 `npm run dev` 这类“只需要最简单监听”的本地命令场景。
- 增加统一命令入口，降低用户记忆多个 bridge 脚本名的成本。
- 增加 shell 集成辅助脚本，提供显式 `th <command>` 入口，保持 shell 默认行为不被破坏。

### Phase 7.5 — Runtime And Interaction Hardening
- 修正原生壳层与本地总线之间的快照 / SSE 同步问题。
- 修正顶部主位任务选择逻辑，优先展示真实来源任务。
- 从 MVP 范围中移除反馈式动作区，让原生壳层聚焦状态和信息监测。
- 增加开发态任务清理入口，支持移除残留测试任务。
- 对齐 `claude-island` 的宿主交互模型：收起态命中展开、展开态点外部收起、事件透传。
- 继续收敛展开 / 收起动画结构，减少宿主焦点与布局重算带来的不稳定。
- 修正 `th` / 通用命令 bridge 的前台中断语义：长运行命令允许占用终端，但用户 `Ctrl+C` 时必须优雅取消，不抛 Python traceback。
- 修正 `th` / 通用命令 bridge 的终端输出语义：包装后仍需回显原始 stdout/stderr，避免前台长命令变成“无输出黑屏”。

## 后续阶段（V2 / Enhanced）

### Phase 8 — Multi-task & details
- 支持多任务列表。
- 增加最近历史与详情视图。
- 增加日志预览与回跳终端。

### Phase 9 — Productization basics
- 增加系统通知联动。
- 增加开机启动与基础设置。
- 增加更多 CLI / Agent 接入。
- 优化动效和交互细节。

## 设计取舍

- **Python 标准库**：无第三方依赖，最快演示。
- **当前仓库原型只保留事件总线**：临时 UI 已移除，避免误导为正式 MVP。
- **原生 MVP 收敛范围**：先做顶部入口、单任务状态和详情查看，不做反馈式动作和桌面工具箱。
- **内存存储**：V0 追求速度，V1 只补最小本地状态，后续再扩展持久化。
- **OpenSpec 优先**：后续需求和修复先落到 `openspec/specs/core-mvp/`，再推进实现与验证。
