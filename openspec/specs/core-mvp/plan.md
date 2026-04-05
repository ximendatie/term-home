# Plan: core-mvp

## 实施策略

采用“总线先行 + UI 验证”的最短路径：

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

## 设计取舍

- **Python 标准库**：无第三方依赖，最快演示。
- **Web UI 模拟 notch**：与参考项目风格对齐，先验证交互闭环。
- **内存存储**：V0 追求速度，后续再扩展持久化。
