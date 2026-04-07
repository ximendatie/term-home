# Spec: core-mvp

## 背景

根据根目录 `README.md`，`term-home` 的工程目标是：
- 提供 macOS 顶部状态层（notch / live island 风格）。
- 提供统一 CLI/Agent 事件总线。
- 让长任务、审批、失败、重试等动作可见、可控。

并参考：
- https://github.com/farouqaldori/claude-island（快速落地实践）
- https://github.com/TheBoredTeam/boring.notch（友好 UI 风格）

## 版本分层

当前仓库中的 `app.py` 是前置验证原型，用于验证：
- 统一事件协议是否足够简单。
- 任务状态机是否成立。
- 人工动作与状态更新是否闭环。

它不是最终定义的 MVP。  
正式 MVP 应为原生 macOS 顶部状态层。

## 版本目标（V0 / Core Prototype）

以“先落地核心功能”为原则，V0 只交付最小闭环：

1. 统一事件协议与事件接入 API。
2. 任务状态机（running/completed/failed/awaiting_approval/cancelled）。
3. 人工动作入口（stop/retry/approve/reject）。
4. 本地单机可运行、可演示。

## V1 目标（Native MVP）

V1 是真正对外可用的最小版本，范围严格收敛：

1. 原生 macOS 常驻 app。
2. 顶部胶囊 / notch 风格收起态。
3. 点击后展开简单详情面板。
4. 单任务视图，只聚焦当前 1 个活动任务。
5. 任务基础状态：`running` / `awaiting_approval` / `completed` / `failed`。
6. 核心动作：`approve` / `reject` / `retry`。
7. 接入 1 个真实 CLI / Agent 事件源。
8. 最小本地状态保留与最近少量任务展示。

## V2 目标（增强版）

在 V1 稳定后再扩展：

1. 多任务列表与切换。
2. 最近任务历史与详情页。
3. 日志预览。
4. 回跳终端。
5. 系统通知联动。
6. 开机启动与基础设置。
7. 多 CLI / 多 Agent 接入。
8. 动效与交互细节优化。

## 非目标（V1 不做）

- 音乐控制、日历、文件 shelf 等桌面工具能力。
- HUD replacement。
- 复杂多功能桌面增强集合。
- 复杂插件系统。
- XPC helper 与重型系统扩展。
- 多屏、锁屏、全屏等深度兼容打磨。
- 完整聊天记录查看器。
- 多用户鉴权与云端同步。
- 全量持久化数据库。

## 工程约束

- 所有新增代码模块必须包含模块级说明。
- 所有新增函数、方法和关键构造入口必须包含简洁的函数级注释。
- 注释应说明职责、输入输出或边界，不写低信息量的语法复述。
- 后续功能开发、运行时修复和交互改动，继续以项目内 `openspec/` 作为唯一规格来源。
- 新需求先更新 spec / plan / tasks，再进行实现与验证，避免代码和文档漂移。

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
- 通过 `/stream` 可以订阅到任务增量更新。
- 调用动作接口后，任务状态会发生对应变化。
- `/tasks` 能返回结构化任务快照。
- `/stream` 以 SSE 提供增量更新。

## 验收标准（V1）

- 应用以原生 macOS app 形态常驻运行，而不是依赖浏览器页面。
- 顶部收起态可稳定展示当前任务状态。
- 在等待审批时，用户可直接在顶部界面执行 `approve` 或 `reject`。
- 展开面板可查看当前任务的标题、状态、摘要和可执行动作。
- 至少有 1 个真实 CLI / Agent 能把事件发送到应用。
- 在没有任务、连接断开、收到非法事件时，界面有清晰兜底状态。

## 当前实现补充（2026-04 Native Runtime / Interaction）

### 运行时同步

- 原生壳层通过 `GET /tasks` + `GET /stream`（SSE）消费本地总线状态。
- 展开时会主动拉取一次最新快照，避免只依赖 SSE 增量推送。
- 顶部主位任务优先展示真实来源任务，降低 `term-home-ui` 合成动作事件的优先级。
- 本地总线支持最小任务清理入口，便于开发态移除残留测试任务，避免旧 `running` 状态长期污染任务列表。

### 动作回写

- `approve` / `reject` / `retry` 已能从原生界面回写到本地总线。
- 当前动作能力属于“事件回写可用”，还不是“真实 CLI 后端恢复执行闭环已完成”。
- `retry` 与 `approve` 目前会更新任务摘要；`reject` 可落到失败态；真实后端恢复仍需继续补齐。

### CLI 接入

- 当前已支持 `codex-cli` bridge，可通过 `codex exec --json` 发布结构化生命周期事件。
- 当前新增 `coco-cli` bridge，可通过 `coco -p --json` 发布最小任务生命周期事件。
- 当前新增通用命令 bridge，可包装任意 shell 命令并发布最小生命周期事件。
- `coco-cli` 当前优先保证 `started -> completed/failed` 闭环；由于一次性 JSON 输出模型，默认不提供细粒度中间进度事件。
- CLI bridge 现已抽象成统一 adapter 骨架，按输出能力分为 `streaming adapter` 和 `print adapter` 两类。
- 后续新增 CLI 应优先复用公共 bridge 能力，只补命令组装、输出解析和少量事件映射，而不是复制整份脚本。
- 通用命令 bridge 的第一版只保证 `started -> running -> completed/failed`，并可通过可选 `ready-pattern` 更新“服务已启动”类摘要，不负责深度语义理解。
- 为避免入口分散，当前新增统一命令入口 `term_home.py run -- <command>`，底层复用通用命令 bridge。

### 宿主交互

- 收起态点击岛体区域可展开。
- 展开态点击岛体外部区域应直接收起，并尽量把鼠标事件透传给底层窗口。
- 宿主层交互实现参考 `claude-island` 的 `NotchPanel` / `NotchWindowController` 模型。
