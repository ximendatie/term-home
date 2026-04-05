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
- 提供顶部胶囊状态条。
- 展示任务列表和状态标签。
- 提供 stop/retry/approve/reject 操作按钮。

### Phase 4 — Demo & docs
- 补充运行说明。
- 提供最小事件注入样例。

## 下一阶段（V1 / Native MVP）

### Phase 5 — Native Shell
- 建立原生 macOS app 壳层。
- 实现顶部收起态与展开态。
- 将 Web 原型降级为内部验证资产，不再作为正式 MVP 载体。

### Phase 6 — Native Runtime Integration
- 复用或替换当前事件总线，使原生 app 能消费真实事件。
- 保留最小任务状态与最近任务数据。
- 建立错误、断连、空状态兜底。

### Phase 7 — First Real Workflow
- 接入 1 个真实 CLI / Agent。
- 跑通 `running -> awaiting_approval -> approve/reject -> completed/failed` 闭环。
- 完成原生形态下的最小使用验证。

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
- **Web UI 模拟 notch**：只用于前期验证，不作为正式 MVP 终态。
- **原生 MVP 收敛范围**：先做顶部入口、单任务状态和少量动作，不做桌面工具箱。
- **内存存储**：V0 追求速度，V1 只补最小本地状态，后续再扩展持久化。
